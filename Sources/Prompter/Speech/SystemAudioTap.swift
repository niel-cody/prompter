import AVFoundation
import CoreAudio
import Foundation

/// Captures what the Mac is playing (the other side of a call) with a Core Audio process
/// tap, the same mechanism Granola-style note takers use. No virtual audio driver, no bot.
///
/// A global tap on every process is wrapped in a private aggregate device whose main
/// sub-device is the default output, and an IOProc on that device hands us the mixed
/// output audio. macOS asks for "System Audio Recording" the first time; a refusal does
/// not fail, it just delivers silence, which is why `peakLevel` is tracked.
///
/// Requires macOS 14.2 for the tap API; the app already needs 26 for SpeechAnalyzer.
final class SystemAudioTap: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "Prompter.SystemAudioTap")
    private(set) var format: AVAudioFormat?
    /// Loudest sample seen so far, so a caller can tell "nobody is talking" from "denied".
    private(set) nonisolated(unsafe) var peakLevel: Float = 0

    struct TapError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Start delivering buffers. `handler` runs on a private queue.
    func start(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Prompter Meetings"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw TapError(message: "Couldn't create a system audio tap (\(status)).") }
        tapID = tap

        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Prompter Meetings Tap",
            kAudioAggregateDeviceUIDKey as String: "com.nielcody.prompter.tap.\(description.uuid.uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [[kAudioSubDeviceUIDKey as String: outputUID]],
            kAudioAggregateDeviceTapListKey as String: [[
                kAudioSubTapDriftCompensationKey as String: true,
                kAudioSubTapUIDKey as String: description.uuid.uuidString,
            ]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else {
            stop()
            throw TapError(message: "Couldn't create the audio device for system audio (\(status)).")
        }
        aggregateID = device

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            stop()
            throw TapError(message: "Couldn't read the system audio format (\(status)).")
        }
        self.format = format

        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, queue) { [weak self] _, inputData, _, _, _ in
            guard let self, let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else { return }
            self.notePeak(of: buffer)
            handler(buffer)
        }
        guard status == noErr, let proc else {
            stop()
            throw TapError(message: "Couldn't listen to system audio (\(status)).")
        }
        procID = proc
        status = AudioDeviceStart(aggregateID, proc)
        guard status == noErr else {
            stop()
            throw TapError(message: "Couldn't start system audio capture (\(status)).")
        }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit { stop() }

    private func notePeak(of buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = data[channel]
            for i in stride(from: 0, to: Int(buffer.frameLength), by: 16) {
                peak = max(peak, abs(samples[i]))
            }
        }
        if peak > peakLevel { peakLevel = peak }
    }

    /// The UID of whatever the Mac is currently playing through.
    static func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { throw TapError(message: "No output device to tap.") }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw TapError(message: "Couldn't identify the output device.") }
        return uid.takeRetainedValue() as String
    }

    /// Fires when the default output changes (headphones in, AirPods on), so a capture can
    /// re-tap the new device. Returns a token to pass to `stopWatchingOutputChanges`.
    static func watchOutputChanges(_ handler: @escaping @Sendable () -> Void) -> AudioObjectPropertyListenerBlock {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        return block
    }

    static func stopWatchingOutputChanges(_ block: @escaping AudioObjectPropertyListenerBlock) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }
}
