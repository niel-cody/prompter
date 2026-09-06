import AVFoundation
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

/// Live, on-device speech recognition from the default microphone using macOS 26's
/// `SpeechAnalyzer`. Audio is streamed straight from the input tap into the analyzer and
/// never written anywhere.
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

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var configObserver: NSObjectProtocol?

    /// Words the recogniser should be biased towards: the script's own vocabulary.
    var contextualVocabulary: [String] = []
    /// Debug: stream this file through the live pipeline instead of the microphone.
    var testAudioFile: URL?

    func start() async {
        guard !state.isActive else { return }
        if testAudioFile == nil {
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

            try startAudioEngine(analyzerFormat: format, continuation: continuation)
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
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        inputContinuation?.finish()
        inputContinuation = nil
        let analyzer = self.analyzer
        self.analyzer = nil
        transcriber = nil
        resultsTask?.cancel()
        resultsTask = nil
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

    private func startAudioEngine(analyzerFormat: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let engine = AVAudioEngine()
        let source: AVAudioNode
        let sourceFormat: AVAudioFormat
        var player: AVAudioPlayerNode?
        var file: AVAudioFile?

        if let testAudioFile {
            // Same graph as the microphone path, fed from a file, with the speakers muted.
            let f = try AVAudioFile(forReading: testAudioFile)
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: f.processingFormat)
            engine.mainMixerNode.outputVolume = 0
            source = p
            sourceFormat = f.processingFormat
            player = p
            file = f
        } else {
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                throw NSError(domain: "Prompter.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone is connected."])
            }
            source = input
            sourceFormat = inputFormat
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat) else {
            throw NSError(domain: "Prompter.Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't convert microphone audio."])
        }
        let ratio = analyzerFormat.sampleRate / sourceFormat.sampleRate

        // The tap runs on a realtime audio thread. It must be explicitly @Sendable so it is not
        // inferred to be MainActor-isolated along with the rest of this class.
        source.installTap(onBus: 0, bufferSize: 4096, format: sourceFormat) { @Sendable buffer, _ in
            nonisolated(unsafe) let buffer = buffer
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
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
            guard status != .error, out.frameLength > 0 else { return }
            continuation.yield(AnalyzerInput(buffer: out))
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

        if let player, let file {
            player.scheduleFile(file, at: nil)
            player.play()
        }
    }

    private func handleConfigurationChange() {
        guard state == .listening else { return }
        stop()
        Task { await start() }
    }
}
