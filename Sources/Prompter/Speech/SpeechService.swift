import AVFoundation
import CoreAudio
import Foundation
import Observation
import Speech

/// One piece of recognised speech. Volatile updates are replaced by later ones covering the
/// same audio; final ones are settled.
struct TranscriptUpdate: Sendable {
    let text: String
    let isFinal: Bool
    let start: TimeInterval
    let end: TimeInterval
}

/// Where a `SpeechService` gets its audio.
enum AudioSource: Equatable {
    /// The default microphone. With echo cancellation, what the Mac is playing (the other
    /// side of a call) is subtracted so it isn't heard twice in a two-channel capture.
    case microphone(echoCancelled: Bool)
    /// A recording standing in for the microphone (debug and tests).
    case file(URL)
    /// Whatever the Mac is playing: the remote participants of a call. See `SystemAudioTap`.
    case systemAudio

    var needsMicrophonePermission: Bool {
        if case .microphone = self { return true }
        return false
    }
}

/// Live, on-device speech recognition using macOS 26's `SpeechAnalyzer`. Audio is streamed
/// straight from the source into the analyzer and never written anywhere.
@MainActor
@Observable
final class SpeechService {
    enum State: Equatable {
        case idle
        case requestingPermission
        case preparing
        /// First run on a Mac downloads Apple's speech model. Can take a minute on slow wifi,
        /// so the prompt says so rather than sitting on "Preparing…".
        case downloadingModel(Double)
        case listening
        case denied
        case unavailable(String)

        var isActive: Bool {
            switch self {
            case .preparing, .listening, .requestingPermission, .downloadingModel: true
            case .idle, .denied, .unavailable: false
            }
        }
    }

    private(set) var state: State = .idle
    var onTranscript: ((TranscriptUpdate) -> Void)?
    var source: AudioSource = .microphone(echoCancelled: false)
    /// When the audio clock behind transcript timestamps started, for lining up channels.
    private(set) var audioStartedAt: Date?

    private var engine: AVAudioEngine?
    private var tap: SystemAudioTap?
    private var outputWatcher: AudioObjectPropertyListenerBlock?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var configObserver: NSObjectProtocol?

    /// Words the recogniser should be biased towards: the script's own vocabulary.
    var contextualVocabulary: [String] = []
    /// Debug: stream this file through the live pipeline instead of the microphone.
    var testAudioFile: URL? {
        get { if case .file(let url) = source { return url } else { return nil } }
        set { source = newValue.map { .file($0) } ?? .microphone(echoCancelled: false) }
    }

    /// Loudest sample heard from system audio, for telling silence from a denied tap.
    var systemAudioPeak: Float { tap?.peakLevel ?? 0 }

    func start() async {
        guard !state.isActive else { return }
        if source.needsMicrophonePermission {
            state = .requestingPermission
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { state = .denied; return }
        }

        guard SpeechTranscriber.isAvailable else {
            state = .unavailable("Speech recognition isn't available on this Mac.")
            return
        }
        state = .preparing
        do {
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
                ?? Locale(identifier: "en_US")
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: [.audioTimeRange]
            )
            if await AssetInventory.status(forModules: [transcriber]) != .installed,
               let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                state = .downloadingModel(0)
                let progress = request.progress
                let watcher = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(250))
                        let fraction = progress.fractionCompleted
                        await MainActor.run {
                            guard let self, case .downloadingModel = self.state else { return }
                            self.state = .downloadingModel(fraction)
                        }
                    }
                }
                defer { watcher.cancel() }
                try await request.downloadAndInstall()
                state = .preparing
            }

            let context = AnalysisContext()
            if !contextualVocabulary.isEmpty {
                context.contextualStrings[.general] = contextualVocabulary
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber], options: nil)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                state = .unavailable("No compatible audio format for speech recognition.")
                return
            }

            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            self.transcriber = transcriber
            self.analyzer = analyzer
            self.inputContinuation = continuation

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        let update = TranscriptUpdate(
                            text: text,
                            isFinal: result.isFinal,
                            start: result.range.start.seconds,
                            end: result.range.end.seconds
                        )
                        await MainActor.run { self?.onTranscript?(update) }
                    }
                } catch {
                    await MainActor.run { self?.fail("Speech recognition stopped: \(error.localizedDescription)") }
                }
            }

            switch source {
            case .systemAudio:
                try startSystemAudio(analyzerFormat: format, continuation: continuation)
            case .microphone, .file:
                try startAudioEngine(analyzerFormat: format, continuation: continuation)
            }
            try await analyzer.start(inputSequence: stream)
            state = .listening
            retriesLeft = 2
        } catch {
            fail("Couldn't start listening: \(error.localizedDescription)")
        }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        tap?.stop()
        tap = nil
        if let outputWatcher { SystemAudioTap.stopWatchingOutputChanges(outputWatcher) }
        outputWatcher = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        inputContinuation?.finish()
        inputContinuation = nil
        let analyzer = self.analyzer
        self.analyzer = nil
        transcriber = nil
        resultsTask?.cancel()
        resultsTask = nil
        audioStartedAt = nil
        Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
        if state != .denied, case .unavailable = state {} else { state = .idle }
    }

    private var retryTask: Task<Void, Never>?
    private var retriesLeft = 2

    /// Recognition stopped on its own. Try again a couple of times before giving up: a
    /// transient failure shouldn't end Voice Follow for the whole presentation.
    private func fail(_ message: String) {
        stop()
        state = .unavailable(message)
        guard retriesLeft > 0 else { return }
        retriesLeft -= 1
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, case .unavailable = self.state else { return }
            await self.start()
        }
    }

    // MARK: - Audio

    /// A converter from the source format into the analyzer's, as a realtime-safe closure.
    nonisolated private static func makeConverter(from sourceFormat: AVAudioFormat, to analyzerFormat: AVAudioFormat) throws
        -> @Sendable (AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat) else {
            throw NSError(domain: "Prompter.Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't convert audio for recognition."])
        }
        let ratio = analyzerFormat.sampleRate / sourceFormat.sampleRate
        return { @Sendable buffer in
            nonisolated(unsafe) let buffer = buffer
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return nil }
            var error: NSError?
            nonisolated(unsafe) var consumed = false
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, out.frameLength > 0 else { return nil }
            return out
        }
    }

    private func startAudioEngine(analyzerFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let engine = AVAudioEngine()
        let source: AVAudioNode
        let sourceFormat: AVAudioFormat
        var player: AVAudioPlayerNode?
        var file: AVAudioFile?

        switch self.source {
        case .file(let url):
            // Same graph as the microphone path, fed from a file, with the speakers muted.
            let f = try AVAudioFile(forReading: url)
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: f.processingFormat)
            engine.mainMixerNode.outputVolume = 0
            source = p
            sourceFormat = f.processingFormat
            player = p
            file = f
        case .microphone(let echoCancelled):
            let input = engine.inputNode
            if echoCancelled {
                // Apple's voice-processing unit subtracts what the Mac is playing, so the
                // remote side of a call isn't transcribed on both channels. Don't let it
                // duck other apps' audio: that would turn the meeting down.
                do {
                    try input.setVoiceProcessingEnabled(true)
                    input.voiceProcessingOtherAudioDuckingConfiguration =
                        AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
                } catch {
                    NSLog("Prompter: echo cancellation unavailable (\(error.localizedDescription)); using the plain microphone")
                }
            }
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                throw NSError(domain: "Prompter.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone is connected."])
            }
            source = input
            sourceFormat = inputFormat
        case .systemAudio:
            preconditionFailure("system audio uses startSystemAudio")
        }

        let convert = try Self.makeConverter(from: sourceFormat, to: analyzerFormat)
        // The tap runs on a realtime audio thread. It must be explicitly @Sendable so it is not
        // inferred to be MainActor-isolated along with the rest of this class.
        source.installTap(onBus: 0, bufferSize: 4096, format: sourceFormat) { @Sendable buffer, _ in
            if let out = convert(buffer) { continuation.yield(AnalyzerInput(buffer: out)) }
        }

        // A microphone being unplugged (or the default input changing) invalidates the tap.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
        audioStartedAt = Date()

        if let player, let file {
            player.scheduleFile(file, at: nil)
            player.play()
        }
    }

    private func startSystemAudio(analyzerFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let tap = SystemAudioTap()
        // The tap's format is only known once it exists, so convert lazily on the first buffer.
        nonisolated(unsafe) var convert: (@Sendable (AVAudioPCMBuffer) -> AVAudioPCMBuffer?)?
        try tap.start { @Sendable buffer in
            if convert == nil {
                convert = try? Self.makeConverter(from: buffer.format, to: analyzerFormat)
            }
            if let out = convert?(buffer) { continuation.yield(AnalyzerInput(buffer: out)) }
        }
        self.tap = tap
        audioStartedAt = Date()
        // Output moved (AirPods on, HDMI in): tap the new device.
        outputWatcher = SystemAudioTap.watchOutputChanges { [weak self] in
            Task { @MainActor in self?.handleConfigurationChange() }
        }
    }

    private func handleConfigurationChange() {
        guard state == .listening else { return }
        stop()
        Task { await start() }
    }
}
