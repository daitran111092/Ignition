import AppKit
import LiftoffCore
import LiftoffSystem

/// Runs the pre-flight: on wake it asks the `WakeGate` whether to start; a run then plays the
/// `RunSession`'s commands strictly in order (a voice line finishes before the next command), feeds
/// system events into the session, and drives the view model and the presenter (notch or fullscreen).
@MainActor
final class Coordinator {
    private(set) var config: LiftoffConfig
    private let observer: SystemObserver
    private let makeAudio: @MainActor (LiftoffConfig) -> AudioDirector
    private let ledgerStore: LedgerStore
    private let configStore: ConfigStore
    private let calendar = Calendar.current
    private var dataDir: URL { configStore.directory }

    private var gate = WakeGate()
    private var run: ActiveRun?
    private var eventPump: Task<Void, Never>?
    /// Presenters fading out; kept alive until their fade completes.
    private var retiring: [ObjectIdentifier: SequencePresenter] = [:]
    /// Tomorrow's greeting is being generated in the background.
    private var pregenerating = false

    /// Whether the Learn wizard is open (set by the app delegate): no wake-triggered run meanwhile.
    var isLearningDevices: () -> Bool = { false }

    var isRunning: Bool { run != nil }

    /// Saves an illustration variant picked on the card (set by the app delegate: goes through
    /// the settings' save path, which then calls `illustrationVariantsChanged`).
    var saveIllustrationVariant: (StepID, Int) -> Void = { _, _ in }

    /// From run start to the greeting line: the dated ElevenLabs greeting gets this long (cache check
    /// included) before the system voice speaks it instead.
    private static let greetingBudget: TimeInterval = 4

    /// `makeAudio` builds a fresh `AudioDirector` per run: it reads volumes and the music file at
    /// init, and its music hand-off is one-way for the life of the instance.
    init(config: LiftoffConfig, observer: SystemObserver, makeAudio: @escaping @MainActor (LiftoffConfig) -> AudioDirector,
         ledgerStore: LedgerStore, configStore: ConfigStore) {
        self.config = config
        self.observer = observer
        self.makeAudio = makeAudio
        self.ledgerStore = ledgerStore
        self.configStore = configStore
    }

    // MARK: Triggers

    /// Wake, screen wake, unlock or app launch. A wake onto the lock screen is ignored: the unlock
    /// notification that follows decides. An unlock is trusted as unlocked even if the session
    /// dictionary hasn't caught up yet.
    func handleWake(_ reason: WakeReason) {
        config = configStore.load()
        let locked = reason != .unlock && sessionIsLocked()
        let decision = gate.decide(now: Date(), calendar: calendar, window: config.window,
                                   ledger: ledgerStore.load(), activeRunDay: run?.day,
                                   isLocked: locked, learningDevices: isLearningDevices())
        log("wake (\(reason)\(locked ? ", locked" : "")) → \(decision)")
        if decision.endActiveRun, let run { endSilently(run) }
        if case .start(let resumeAt) = decision.trigger {
            start(resumeAt: resumeAt)
        } else if run == nil, !locked {
            pregenerateTomorrowsGreeting()
        }
    }

    /// "Start pre-flight now": a fresh run whatever the time or ledger (the run still writes the ledger).
    /// While today's run is on screen it just brings it forward; one left over from an earlier day
    /// is ended silently first.
    func runNow() {
        if let run {
            guard isFromEarlierDay(run.day, now: Date(), calendar: calendar) else {
                run.presenter?.show()
                return
            }
            endSilently(run)
        }
        config = configStore.load()
        start(resumeAt: nil)
    }

    /// The display mode was changed (menu / Settings): a run on screen moves over at once.
    func displayModeChanged(to mode: DisplayMode) {
        config.displayMode = mode
        if let run { switchPresenter(to: mode, in: run) }
    }

    /// The chosen illustration variants changed (picked on the card, or config.json re-read):
    /// a run on screen shows them at once.
    func illustrationVariantsChanged(to variants: [StepID: Int]) {
        config.illustrationVariants = variants
        if let model = run?.model, model.illustrationVariants != variants { model.illustrationVariants = variants }
    }

    // MARK: Run lifecycle

    private func start(resumeAt: Int?) {
        let now = Date()
        let catalog: VoiceCatalog
        do {
            catalog = try VoiceCatalog.installed(in: dataDir)
        } catch {
            log("voice catalog unavailable (\(error)); lines will be silent")
            catalog = VoiceCatalog(lines: [])
        }
        let doneOnly = Set(config.steps.indices.filter {
            needsManualConfirm(config.steps[$0], learned: config.learned[config.steps[$0].id] ?? [])
        })
        let model = SequenceViewModel(steps: config.steps, doneOnlySteps: doneOnly, phase: .greeting)
        model.illustrationVariants = config.illustrationVariants
        let run = ActiveRun(session: RunSession(config: config, resumeAt: resumeAt), model: model,
                            audio: makeAudio(config), mode: config.displayMode,
                            day: dayKey(now, calendar: calendar), dateText: renderDate(now, calendar: calendar),
                            catalog: catalog, history: LineHistoryStore(directory: dataDir).load())
        self.run = run
        wire(run)
        log("run starts (resumeAt: \(resumeAt.map(String.init) ?? "fresh"), mode: \(run.mode.rawValue))")

        // No dead air: the card, music and chime start now; only the greeting line itself waits
        // (within `greetingBudget`) for the dated clip, which normally is already cached.
        if resumeAt == nil { run.greeting = Task { await self.prepareDailyGreeting(for: run) } }
        model.ticked = run.session.displayedTicked
        let presenter = makePresenter(run.mode, model: model)
        run.presenter = presenter
        presenter.show()
        enqueue(run.session.start(observer.currentSnapshot()), in: run)
        if let front = NSWorkspace.shared.frontmostApplication {
            let app = RunningApp(bundleID: front.bundleIdentifier, name: front.localizedName ?? "")
            enqueue(run.session.handle(.appActivated(app)), in: run)
        }
        startEventPump()
    }

    private func wire(_ run: ActiveRun) {
        let model = run.model
        model.onDone = { [weak self, weak run] in
            guard let self, let run else { return }
            self.respond(run.session.confirmManual(), in: run)
        }
        model.onSkip = { [weak self, weak run] in
            guard let self, let run else { return }
            self.respond(run.session.skipStep(), in: run)
        }
        model.onSkipAll = { [weak self, weak run] in
            guard let self, let run else { return }
            let commands = run.session.skipAll()  // empty once the run is over
            guard !commands.isEmpty else { return }
            run.queue.removeAll()
            run.audio.stopAll()  // releases a line in progress so the queue reaches the dismissal
            self.enqueue(commands, in: run)
        }
        model.onToggleVoice = { [weak run, weak model] in
            guard let run, let model else { return }
            run.audio.voiceMuted.toggle()
            model.voiceMuted = run.audio.voiceMuted
        }
        model.onToggleMusic = { [weak run, weak model] in
            guard let run, let model else { return }
            run.audio.musicMuted.toggle()
            model.musicMuted = run.audio.musicMuted
        }
        model.onIllustrationVariantChanged = { [weak self] id, variant in
            self?.saveIllustrationVariant(id, variant)
        }
        model.onOpenApp = { [weak run] in
            guard let run, let step = run.model.currentStep, let target = appLaunchTarget(for: step) else { return }
            run.presenter?.stepBack()  // fullscreen: the stage sits behind the app as a backdrop
            AppLauncher.open(target)
        }
        model.onEscapeToNotch = { [weak self, weak run] in
            guard let self, let run else { return }
            self.switchPresenter(to: .notch, in: run)
        }
    }

    /// Done / Skip: cut the prompt still being spoken (voice only, music plays on) so the tick and
    /// confirm line follow at once.
    private func respond(_ commands: [RunCommand], in run: ActiveRun) {
        guard !commands.isEmpty else { return }
        run.audio.cutVoice()
        enqueue(commands, in: run)
    }

    /// System events go to the session of the run on screen (if any). A tick of the current step
    /// shows at once and cuts its prompt line if that is still being spoken (voice only), so the
    /// tick sound and confirm line follow straight away instead of after the prompt.
    private func startEventPump() {
        guard eventPump == nil else { return }
        let events = observer.events
        eventPump = Task { [weak self] in
            for await event in events {
                guard let self, let run = self.run else { continue }
                if case .appActivated(let app) = event { self.appActivated(app, in: run) }
                let commands = run.session.handle(event)
                if let i = RunSession.tickedStep(in: commands), run.model.currentIndex == i {
                    run.model.ticked = run.session.displayedTicked
                    run.model.waitingText = nil
                }
                if run.session.interruptsSpokenPrompt(commands) { run.audio.cutVoice() }
                self.enqueue(commands, in: run)
            }
        }
    }

    /// Fullscreen, app step: another app came to the front (opened by hand, ⌘-Tab): the stage
    /// steps back behind it until the next step. Ignored just after the step appears, so the
    /// activation that comes with an unlock doesn't drop the stage.
    private func appActivated(_ app: RunningApp, in run: ActiveRun) {
        guard run.mode == .fullscreen, run.model.openAppTitle != nil,
              app.bundleID == nil || app.bundleID != Bundle.main.bundleIdentifier,
              Date().timeIntervalSince(run.stepShownAt) > 1 else { return }
        run.presenter?.stepBack()
    }

    // MARK: Command queue

    private func enqueue(_ commands: [RunCommand], in run: ActiveRun) {
        guard self.run === run, !commands.isEmpty else { return }
        run.queue.append(contentsOf: commands)
        guard !run.draining else { return }
        run.draining = true
        Task { await drain(run) }
    }

    private func drain(_ run: ActiveRun) async {
        while self.run === run, !run.queue.isEmpty {
            await execute(run.queue.removeFirst(), in: run)
        }
        run.draining = false
    }

    private func execute(_ command: RunCommand, in run: ActiveRun) async {
        let model = run.model
        switch command {
        case .pauseThenAdvance:
            try? await Task.sleep(for: RunSession.advancePause)
            guard self.run === run else { return }
            run.queue.append(contentsOf: run.session.advance())

        case .perform(.show(let index)):
            let step = model.steps[index]
            model.currentIndex = index
            model.phase = step.rule == .final ? .liftoff : .step
            if step.rule == .final { model.ticked = run.session.displayedTicked }  // the full rail lights up
            model.waitingText = waitingText(for: step, learned: config.learned[step.id] ?? [])
            model.caption = ""
            run.stepShownAt = Date()
            run.presenter?.comeForward()  // the stage returns after an app step put it behind
            // Music only announces changes, so ask it once whether it is already playing.
            if run.session.takeMusicQuery(), observer.queryMusicPlaying() == true {
                run.queue.append(contentsOf: run.session.handle(.musicStateChanged(playing: true)))
            }

        case .perform(.say(let key)):
            let line = pickLine(key, in: run)
            model.caption = line.text.replacingOccurrences(of: "{date}", with: run.dateText)
            if key.kind == .greeting, let greeting = run.greeting, config.voiceEnabled, !run.audio.voiceMuted {
                run.greeting = nil
                let remaining = Self.greetingBudget - Date().timeIntervalSince(run.startedAt)
                run.dailyGreeting = remaining > 0 ? await withTimeout(seconds: remaining) { await greeting.value } : nil
                if run.dailyGreeting == nil { log("no dated greeting clip (none configured, or not ready in time); system voice speaks it") }
                guard self.run === run else { return }
            }
            let voices = dataDir.appendingPathComponent("voices", isDirectory: true)
            run.session.lineStarted(key)
            await run.audio.say(resolveClip(line, voicesDir: voices, dateText: run.dateText, dailyGreeting: run.dailyGreeting))
            run.session.lineEnded()
            if key.kind == .prompt, self.run === run { model.promptLineEnded() }

        case .perform(.startMusic):
            run.audio.startMusic()

        case .perform(.play(let sfx)):
            run.audio.play(sfx)

        case .perform(.ticked):
            model.ticked = run.session.displayedTicked
            model.waitingText = nil

        case .perform(.handOffMusic):
            run.audio.fadeOutMusic()

        case .perform(.persist(let status)):
            do {
                try ledgerStore.save(DayLedger(day: run.day, status: status))
            } catch {
                log("ledger save failed: \(error)")
            }

        case .perform(.finished):
            // The liftoff line has already been spoken (commands run in order): hold, then fold away.
            try? await Task.sleep(for: .seconds(2))
            guard self.run === run else { return }
            run.audio.fadeOutMusic(duration: 1.5)
            if run.mode == .notch {
                model.collapse()
                try? await Task.sleep(for: .milliseconds(700))
            }
            end(run)
            pregenerateTomorrowsGreeting()

        case .perform(.dismissed):
            run.audio.stopAll()
            end(run)
            pregenerateTomorrowsGreeting()
        }
    }

    /// Ends a run without a ledger write (a run left over from an earlier day).
    private func endSilently(_ run: ActiveRun) {
        run.audio.stopAll()
        end(run)
    }

    /// Hides the presenter (fading) and silences the run.
    private func end(_ run: ActiveRun) {
        if let presenter = run.presenter { retire(presenter) }
        run.presenter = nil
        run.queue.removeAll()
        let audio = run.audio
        Task {
            try? await Task.sleep(for: .seconds(1.5))  // let a music fade finish
            audio.stopAll()
        }
        if self.run === run { self.run = nil }
        log("run ended")
    }

    // MARK: Presenters

    private func makePresenter(_ mode: DisplayMode, model: SequenceViewModel) -> SequencePresenter {
        switch mode {
        case .notch: NotchPanel(model: model)
        case .fullscreen: FullscreenPresenter(model: model)
        }
    }

    /// Swaps notch ⇄ fullscreen mid-run. Idempotent per mode, so a second Esc during the 0.4 s
    /// fade does nothing and there is only ever one live presenter.
    private func switchPresenter(to mode: DisplayMode, in run: ActiveRun) {
        guard self.run === run, run.mode != mode else { return }
        run.mode = mode
        guard let old = run.presenter else { return }  // not shown yet: the new mode applies at show
        retire(old)
        run.model.expand()
        let presenter = makePresenter(mode, model: run.model)
        run.presenter = presenter
        presenter.show()
    }

    private func retire(_ presenter: SequencePresenter) {
        presenter.hide(animated: true)
        let id = ObjectIdentifier(presenter)
        retiring[id] = presenter
        Task {
            try? await Task.sleep(for: .seconds(1))
            retiring[id] = nil
        }
    }

    // MARK: Voice

    private func pickLine(_ key: LineKey, in run: ActiveRun) -> VoiceLine {
        var random = SystemRandomNumberGenerator()
        let line = run.selector.pick(key, catalog: run.catalog, history: &run.history, today: run.day, random: &random)
        try? LineHistoryStore(directory: dataDir).save(run.history)
        return line
    }

    /// Today's dated greeting clip, or nil → the system voice speaks it. Normally a cache hit
    /// (generated the day before); otherwise generated now — the greeting line waits for it only
    /// within `greetingBudget`.
    private func prepareDailyGreeting(for run: ActiveRun) async -> URL? {
        guard config.voiceEnabled, let voiceID = config.elevenLabsVoiceID, !voiceID.isEmpty else { return nil }
        let line = pickLine(LineKey(step: nil, kind: .greeting), in: run)
        return await dailyGreeting(line, day: run.day, dateText: run.dateText, voiceID: voiceID, timeout: 4)
    }

    /// At idle and after a run ends: generate tomorrow's dated greeting so the morning only checks
    /// the cache. Tomorrow's greeting line is picked (and recorded) now so it matches the clip.
    /// Also deletes dated greetings more than two days old.
    private func pregenerateTomorrowsGreeting() {
        let now = Date()
        deleteStaleGreetings(today: now)
        guard !pregenerating, config.voiceEnabled, let voiceID = config.elevenLabsVoiceID, !voiceID.isEmpty,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let catalog = try? VoiceCatalog.installed(in: dataDir) else { return }
        let day = dayKey(tomorrow, calendar: calendar)
        let historyStore = LineHistoryStore(directory: dataDir)
        var history = historyStore.load()
        var selector = LineSelector()
        var random = SystemRandomNumberGenerator()
        let line = selector.pick(LineKey(step: nil, kind: .greeting), catalog: catalog, history: &history,
                                 today: day, random: &random)
        guard line.text.contains("{date}"),
              !FileManager.default.fileExists(atPath: dailyGreetingURL(dataDir: dataDir, day: day, lineID: line.id).path)
        else { return }
        try? historyStore.save(history)
        pregenerating = true
        let dateText = renderDate(tomorrow, calendar: calendar)
        Task {
            defer { pregenerating = false }
            if await dailyGreeting(line, day: day, dateText: dateText, voiceID: voiceID, timeout: 20) != nil {
                log("daily greeting for \(day) generated")
            }
        }
    }

    /// The cached clip for `line` on `day`, else one generated from ElevenLabs and cached; nil when the
    /// line has no date, there is no key, or generation fails / times out. Never blocks the main
    /// actor: the Keychain read (which may raise a prompt) and the request run detached with timeouts.
    private func dailyGreeting(_ line: VoiceLine, day: String, dateText: String, voiceID: String,
                               timeout: Double) async -> URL? {
        guard line.text.contains("{date}") else { return nil }
        let url = dailyGreetingURL(dataDir: dataDir, day: day, lineID: line.id)
        if FileManager.default.fileExists(atPath: url.path) { return url }

        guard let key = await withTimeout(seconds: 2, { Keychain.elevenLabsKey() }) else {
            log("daily greeting: no API key (or Keychain did not answer in time)")
            return nil
        }
        let client = ElevenLabsClient(apiKey: key, voiceID: voiceID)
        let text = line.text.replacingOccurrences(of: "{date}", with: dateText)
        let audio: Data? = await withTimeout(seconds: timeout) {
            do { return try await client.synthesize(text) } catch { return nil }
        }
        guard let audio else {
            log("daily greeting: generation failed or timed out")
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try audio.write(to: url, options: .atomic)
            return url
        } catch {
            log("daily greeting: write failed: \(error)")
            return nil
        }
    }

    private func deleteStaleGreetings(today: Date) {
        let voices = dataDir.appendingPathComponent("voices", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: voices.path)) ?? []
        for name in staleDailyGreetings(names, today: today, calendar: calendar) {
            try? FileManager.default.removeItem(at: voices.appendingPathComponent(name))
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[Coordinator] \(message)\n".utf8))
    }
}

/// Everything one run owns.
@MainActor
private final class ActiveRun {
    var session: RunSession
    let model: SequenceViewModel
    let audio: AudioDirector
    var presenter: SequencePresenter?
    var mode: DisplayMode
    let day: String
    let dateText: String
    let catalog: VoiceCatalog
    var history: LineHistory
    var selector = LineSelector()
    let startedAt = Date()
    /// When the current step appeared.
    var stepShownAt = Date()
    /// Today's dated greeting being prepared (fresh runs only); awaited at the greeting line.
    var greeting: Task<URL?, Never>?
    var dailyGreeting: URL?
    var queue: [RunCommand] = []
    var draining = false

    init(session: RunSession, model: SequenceViewModel, audio: AudioDirector, mode: DisplayMode,
         day: String, dateText: String, catalog: VoiceCatalog, history: LineHistory) {
        self.session = session
        self.model = model
        self.audio = audio
        self.mode = mode
        self.day = day
        self.dateText = dateText
        self.catalog = catalog
        self.history = history
    }
}
