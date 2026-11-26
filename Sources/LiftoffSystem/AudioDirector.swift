import AVFoundation
import Foundation
import LiftoffCore

// MARK: - Fallback voice preference

/// The attributes of an installed system voice that matter for choosing one.
struct VoiceCandidate: Equatable {
    enum Quality: Int, Comparable {
        case standard, enhanced, premium
        static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
    }

    var identifier: String
    var name: String
    var language: String
    var quality: Quality
}

/// Among English voices, names starting Zoe → Ava → Samantha, best quality first within a name;
/// otherwise the best-quality en-US voice; otherwise nil.
func preferredVoice(among voices: [VoiceCandidate]) -> VoiceCandidate? {
    let english = voices.filter { $0.language.hasPrefix("en-") || $0.language == "en" }
    for name in ["Zoe", "Ava", "Samantha"] {
        if let best = english.filter({ $0.name.hasPrefix(name) }).max(by: { $0.quality < $1.quality }) {
            return best
        }
    }
    return voices.filter { $0.language == "en-US" }.max(by: { $0.quality < $1.quality })
}

extension VoiceCandidate {
    init(_ voice: AVSpeechSynthesisVoice) {
        let quality: Quality = switch voice.quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
        self.init(identifier: voice.identifier, name: voice.name, language: voice.language, quality: quality)
    }
}

// MARK: - Audio director

/// Plays background music (looped, ducked under the voice), SFX and voice lines through one `AVAudioEngine`.
///
/// Every voice line — a pre-generated clip, the dated greeting, or the system voice (rendered to PCM
/// with `AVSpeechSynthesizer.write`) — plays on one player node whose output runs through the
/// `RoomEffect` chain (EQ → echo taps → peak limiter) unless `voiceRoomEffect` is off. Music and SFX
/// stay dry. Failures (no output device, unreadable files) are logged and swallowed: the sequence
/// never stalls on audio.
@MainActor
public final class AudioDirector {
    public static let sfxDirectory = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
    static let sfxFiles: [SFX: String] = [.chime: "Glass.aiff", .tick: "Tink.aiff", .liftoff: "Hero.aiff"]
    /// Every voice source is converted to this format before it is scheduled on `voiceNode`. Stereo on
    /// purpose: the converter copies a mono voice to both channels at full level, whereas a mono node
    /// feeding the stereo main mixer would be panned centre at −3 dB per channel.
    static let voiceFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    private let config: LiftoffConfig
    private let engine = AVAudioEngine()
    private let musicNode = AVAudioPlayerNode()
    private var musicFile: AVAudioFile?
    private var sfxNodes: [SFX: (node: AVAudioPlayerNode, file: AVAudioFile)] = [:]

    /// nil when the voice plays dry.
    private let roomEffect: RoomEffect?
    private let voiceNode = AVAudioPlayerNode()
    private let voiceEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let voiceDelays: [AVAudioUnitDelay]
    private let voiceLimiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    /// Last node of the voice chain; carries the voice volume.
    private let voiceMixer = AVAudioMixerNode()

    private let synthesizer = AVSpeechSynthesizer()
    private lazy var systemVoice: AVSpeechSynthesisVoice? = Self.chooseSystemVoice()
    private var voiceContinuation: CheckedContinuation<Void, Never>?
    /// Identifies the current line; bumped whenever a line ends so stale callbacks are ignored.
    private var voiceLine = 0
    /// Bumped when the current line is re-scheduled (engine restart) so the old node's completions are ignored.
    private var voicePass = 0
    /// The current line's audio so far (already in `voiceFormat`), kept for a replay after an engine restart.
    private var voiceBuffers: [AVAudioPCMBuffer] = []
    /// Buffers scheduled in this pass that have not been played back yet.
    private var voicePending = 0
    /// True once all of the line's audio has been scheduled (clip loaded / synthesis ended).
    private var voiceInputComplete = false
    private var voiceExpected: TimeInterval = 0
    private var speechConverter: PCMConverter?
    private var voiceWatchdog: Task<Void, Never>?
    private var voiceTailTask: Task<Void, Never>?
    private var loggedVoicePath = false

    private var musicPlaying = false
    private var musicFadedOut = false
    private var musicLoopGeneration = 0
    private var rampTask: Task<Void, Never>?
    /// Removed in deinit. `nonisolated(unsafe)` because deinit is nonisolated; it is written once in init.
    nonisolated(unsafe) private var configChangeObserver: NSObjectProtocol?

    public var voiceMuted = false {
        didSet { if voiceMuted { stopVoice() } }
    }

    public var musicMuted = false {
        didSet { if musicMuted != oldValue { updateMusicLevel() } }
    }

    /// The name of the system voice used for synthesized lines (nil if none is installed).
    public var systemVoiceName: String? { systemVoice?.name }

    /// Human-readable description of the voice signal path.
    public var voicePath: String {
        roomEffect.map { "AVAudioEngine + room effect (\($0.summary))" } ?? "AVAudioEngine, dry (voiceRoomEffect off)"
    }

    public init(config: LiftoffConfig, dataDir: URL) {
        self.config = config
        let effect: RoomEffect? = config.voiceRoomEffect ? .smallRoom : nil
        roomEffect = effect
        voiceDelays = (effect?.taps ?? []).map { _ in AVAudioUnitDelay() }

        if config.musicEnabled, let url = Self.musicFile(in: dataDir) {
            do {
                let file = try AVAudioFile(forReading: url)
                musicFile = file
                engine.attach(musicNode)
                engine.connect(musicNode, to: engine.mainMixerNode, format: file.processingFormat)
            } catch {
                log("music file unreadable (\(url.lastPathComponent)): \(error)")
            }
        }
        for (sfx, name) in Self.sfxFiles {
            do {
                let file = try AVAudioFile(forReading: Self.sfxDirectory.appendingPathComponent(name))
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
                sfxNodes[sfx] = (node, file)
            } catch {
                log("sfx \(name) unreadable: \(error)")
            }
        }
        configureVoiceEffect()
        connectVoiceChain()
        // Switching the output device (e.g. the K7 powering on) stops the engine; restart it.
        configChangeObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineConfigurationChanged() }
        }
    }

    deinit {
        if let configChangeObserver { NotificationCenter.default.removeObserver(configChangeObserver) }
    }

    private func configureVoiceEffect() {
        voiceMixer.outputVolume = Float(config.voiceVolume)
        guard let effect = roomEffect else { return }
        let highPass = voiceEQ.bands[0], lowPass = voiceEQ.bands[1]
        highPass.filterType = .highPass
        highPass.frequency = effect.highPassHz
        highPass.bypass = false
        lowPass.filterType = .lowPass
        lowPass.frequency = effect.lowPassHz
        lowPass.bypass = false
        voiceEQ.globalGain = effect.makeupGainDB
        for (delay, (tap, mix)) in zip(voiceDelays, zip(effect.taps, effect.delayMixes)) {
            delay.delayTime = tap.delay
            delay.feedback = 0
            delay.wetDryMix = mix
        }
    }

    /// (Re)builds voice node → [EQ → delays → limiter] → voice mixer → main mixer.
    private func connectVoiceChain() {
        let chain: [AVAudioNode] = roomEffect == nil
            ? [voiceNode, voiceMixer]
            : [voiceNode, voiceEQ] + voiceDelays + [voiceLimiter, voiceMixer]
        for node in chain where node.engine == nil { engine.attach(node) }
        for node in chain { engine.disconnectNodeOutput(node) }
        for (from, to) in zip(chain, chain.dropFirst()) { engine.connect(from, to: to, format: Self.voiceFormat) }
        engine.connect(voiceMixer, to: engine.mainMixerNode, format: Self.voiceFormat)
    }

    private func engineConfigurationChanged() {
        // The engine has stopped; completions from the stopped voice node belong to the old pass.
        voicePass += 1
        voiceNode.stop()
        connectVoiceChain()
        if musicPlaying, let file = musicFile {
            musicLoopGeneration += 1
            musicNode.stop()
            if startEngine() {
                primeMusicLoop(file)
                musicNode.play()
            } else {
                musicPlaying = false
            }
        }
        // A line in progress replays from its start on the new device (unless only its tail was left).
        guard voiceContinuation != nil, voiceTailTask == nil else { return }
        guard startEngine() else { finishVoice(); return }
        log("output changed; replaying the current voice line")
        voicePending = 0
        for buffer in voiceBuffers { schedule(buffer) }
        voiceNode.play()
        startVoiceWatchdog()
        checkLineDone()
    }

    /// First `.mp3`/`.m4a` (by name) in `<dataDir>/music/`.
    static func musicFile(in dataDir: URL) -> URL? {
        let dir = dataDir.appendingPathComponent("music", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names
            .filter { ["mp3", "m4a"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .first
            .map { dir.appendingPathComponent($0) }
    }

    static func chooseSystemVoice() -> AVSpeechSynthesisVoice? {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        if let pick = preferredVoice(among: installed.map(VoiceCandidate.init)),
           let voice = AVSpeechSynthesisVoice(identifier: pick.identifier) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: Music

    private var musicTarget: Float {
        if musicMuted || musicFadedOut { return 0 }
        let base = Float(config.musicVolume)
        return voiceContinuation != nil ? base * Float(config.duckLevel) : base
    }

    /// Starts the looped music (no-op without a music file, when already playing, or after `fadeOutMusic`).
    public func startMusic() {
        guard let file = musicFile, !musicPlaying, !musicFadedOut, startEngine() else { return }
        musicPlaying = true
        musicLoopGeneration += 1
        musicNode.volume = 0
        primeMusicLoop(file)
        musicNode.play()
        rampMusic(to: musicTarget, over: 1.0)
    }

    /// Re-targets the music level after a duck/unduck or mute change. Never interrupts the final fade-out.
    private func updateMusicLevel() {
        guard !musicFadedOut else { return }
        rampMusic(to: musicTarget, over: 0.3)
    }

    /// Queues the track twice so one copy is always scheduled ahead of the one playing; each
    /// consumed copy queues another, so the loop point is gapless.
    private func primeMusicLoop(_ file: AVAudioFile) {
        scheduleMusicLoop(file, generation: musicLoopGeneration)
        scheduleMusicLoop(file, generation: musicLoopGeneration)
    }

    private func scheduleMusicLoop(_ file: AVAudioFile, generation: Int) {
        musicNode.scheduleFile(file, at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.musicPlaying, self.musicLoopGeneration == generation else { return }
                self.scheduleMusicLoop(file, generation: generation)
            }
        }
    }

    /// Fades music out and keeps it off for the rest of the run. Idempotent.
    public func fadeOutMusic(duration: TimeInterval = 3) {
        guard !musicFadedOut else { return }
        musicFadedOut = true
        guard musicPlaying else { return }
        rampMusic(to: 0, over: duration) { [weak self] in self?.stopMusicNode() }
    }

    private func stopMusicNode() {
        musicPlaying = false
        musicLoopGeneration += 1
        musicNode.stop()
    }

    /// Linear volume ramp in ~30 steps; a new ramp cancels the previous one.
    private func rampMusic(to target: Float, over duration: TimeInterval, then completion: (() -> Void)? = nil) {
        rampTask?.cancel()
        guard musicPlaying else { completion?(); return }
        let start = musicNode.volume
        let steps = max(1, Int(duration * 30))
        rampTask = Task { [weak self] in
            for i in 1...steps {
                try? await Task.sleep(for: .seconds(duration / Double(steps)))
                guard !Task.isCancelled, let self else { return }
                self.musicNode.volume = start + (target - start) * Float(i) / Float(steps)
            }
            completion?()
        }
    }

    // MARK: SFX

    public func play(_ sfx: SFX) {
        guard let (node, file) = sfxNodes[sfx], startEngine() else { return }
        node.stop()
        node.scheduleFile(file, at: nil)
        node.play()
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            log("audio engine failed to start: \(error)")
            return false
        }
    }

    // MARK: Voice

    /// Speaks a line and returns when its audio (plus the effect's short tail) has played
    /// (immediately when voice is muted or disabled). Music ducks to `duckLevel × musicVolume` meanwhile.
    public func say(_ source: ClipSource) async {
        guard !voiceMuted, config.voiceEnabled else { return }
        stopVoice()  // a new line pre-empts any line still playing

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            voiceContinuation = continuation
            updateMusicLevel()
            guard startEngine() else { finishVoice(); return }
            if !loggedVoicePath {
                loggedVoicePath = true
                log("voice path: \(voicePath)")
            }
            switch source {
            case .file(let url, let fallbackText):
                do {
                    let buffer = try Self.loadClip(url)
                    voiceExpected = Double(buffer.frameLength) / Self.voiceFormat.sampleRate
                    voiceInputComplete = true
                    enqueue(buffer)
                } catch {
                    // Never silent: an unreadable clip falls back to the system voice.
                    log("voice clip \(url.lastPathComponent) failed (\(error)); using system voice")
                    speak(fallbackText)
                }
            case .synthesize(let text):
                speak(text)
            }
            voiceNode.play()
            startVoiceWatchdog()
        }
    }

    /// Cuts the line being spoken (its `say` returns now); music and SFX play on.
    public func cutVoice() {
        stopVoice()
    }

    /// Reads a whole clip and converts it to `voiceFormat`.
    private static func loadClip(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0,
              let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw CocoaError(.fileReadCorruptFile) }
        try file.read(into: raw)
        guard let converter = PCMConverter(from: file.processingFormat, to: voiceFormat),
              let buffer = converter.convert(raw, final: true), buffer.frameLength > 0
        else { throw CocoaError(.fileReadCorruptFile) }
        return buffer
    }

    /// Renders a system-voice utterance to PCM; its buffers are scheduled on the voice node as they arrive.
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = systemVoice
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.05
        voiceExpected = Double(text.count) * 0.12
        voiceInputComplete = false
        speechConverter = nil
        synthesizer.stopSpeaking(at: .immediate)  // never queue behind a leftover utterance
        let line = voiceLine
        synthesizer.write(utterance) { [weak self] buffer in
            // Main queue (FIFO) keeps the chunks in order.
            let chunk = UncheckedSendable(value: buffer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receiveSpeech(chunk.value, line: line) }
            }
        }
    }

    private func receiveSpeech(_ buffer: AVAudioBuffer, line: Int) {
        guard line == voiceLine, voiceContinuation != nil, !voiceInputComplete else { return }
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
            // An empty buffer marks the end of the utterance.
            if let tail = speechConverter?.convert(nil, final: true), tail.frameLength > 0 { enqueue(tail) }
            voiceInputComplete = true
            checkLineDone()
            return
        }
        if speechConverter?.inputFormat != pcm.format {
            speechConverter = PCMConverter(from: pcm.format, to: Self.voiceFormat)
        }
        if let converted = speechConverter?.convert(pcm, final: false), converted.frameLength > 0 {
            enqueue(converted)
        }
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer) {
        voiceBuffers.append(buffer)
        schedule(buffer)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        voicePending += 1
        let line = voiceLine, pass = voicePass
        voiceNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.bufferPlayed(line: line, pass: pass) }
        }
    }

    private func bufferPlayed(line: Int, pass: Int) {
        guard line == voiceLine, pass == voicePass, voiceContinuation != nil else { return }
        voicePending -= 1
        checkLineDone()
    }

    /// Once everything has played, waits out the short effect tail and resumes `say`.
    private func checkLineDone() {
        guard voiceContinuation != nil, voiceInputComplete, voicePending == 0, voiceTailTask == nil else { return }
        let line = voiceLine
        let tail = roomEffect?.sayTail ?? 0
        voiceTailTask = Task { [weak self] in
            if tail > 0 { try? await Task.sleep(for: .seconds(tail)) }
            guard !Task.isCancelled else { return }
            self?.voiceFinished(line)
        }
    }

    /// Safety net: never let the sequence hang on a callback that doesn't come.
    private func startVoiceWatchdog() {
        voiceWatchdog?.cancel()
        let line = voiceLine
        let limit = voiceExpected + (roomEffect?.sayTail ?? 0) + 3
        voiceWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled else { return }
            self?.voiceFinished(line)
        }
    }

    private func voiceFinished(_ line: Int) {
        guard line == voiceLine, voiceContinuation != nil else { return }
        finishVoice()
    }

    /// Stops any line in progress and resumes its waiting `say`.
    private func stopVoice() {
        voiceLine += 1
        voiceNode.stop()
        synthesizer.stopSpeaking(at: .immediate)
        finishVoice()
    }

    private func finishVoice() {
        voiceLine += 1
        voiceWatchdog?.cancel()
        voiceWatchdog = nil
        voiceTailTask?.cancel()
        voiceTailTask = nil
        voiceBuffers = []
        voicePending = 0
        voiceInputComplete = false
        speechConverter = nil
        let continuation = voiceContinuation
        voiceContinuation = nil
        updateMusicLevel()
        continuation?.resume()
    }

    /// Silences everything immediately; any pending `say` returns.
    public func stopAll() {
        stopVoice()
        rampTask?.cancel()
        if musicPlaying { stopMusicNode() }
        for (node, _) in sfxNodes.values { node.stop() }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[AudioDirector] \(message)\n".utf8))
    }
}

// MARK: - PCM conversion

/// Hands a non-Sendable audio buffer from the synthesizer's callback thread to the main queue.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

/// Converts PCM buffers (any rate/channels/sample type) to one output format. Feed a stream chunk by
/// chunk with `final: false`, then `convert(nil, final: true)` to flush the resampler.
final class PCMConverter {
    let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
        inputFormat = input
        outputFormat = output
        self.converter = converter
    }

    func convert(_ input: AVAudioPCMBuffer?, final: Bool) -> AVAudioPCMBuffer? {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input?.frameLength ?? 0) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        let pending = UncheckedSendable(value: input)
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if !supplied, let buffer = pending.value {
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            inputStatus.pointee = final ? .endOfStream : .noDataNow
            return nil
        }
        if status == .error {
            FileHandle.standardError.write(Data("[AudioDirector] voice conversion failed: \(error.map { "\($0)" } ?? "?")\n".utf8))
            return nil
        }
        return output
    }
}
