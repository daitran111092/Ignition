import Foundation
import Observation
import LiftoffCore

/// Everything the notch / fullscreen views render. The coordinator (Task 9) owns and mutates it;
/// the views only read it and call the action closures.
@MainActor @Observable
final class SequenceViewModel {
    enum Phase: Equatable {
        case greeting, step, liftoff
    }

    var steps: [StepDefinition]
    /// Index into `steps` of the step being shown; nil during the greeting.
    var currentIndex: Int? {
        didSet {
            guard currentIndex != oldValue else { return }
            promptEnded = false
            expand()  // every new step starts expanded
        }
    }
    /// Steps only the user's Done can tick (manual ones and device steps that can never match):
    /// a prominent Done that Space also presses, and no waiting pulse.
    let doneOnlySteps: Set<Int>
    /// Indices of completed (or skipped) steps; rendered as white rail segments.
    var ticked: Set<Int>
    /// The line being spoken: subtitle on the greeting / liftoff cards and, in fullscreen, the step
    /// caption. Empty → a built-in default (the step instruction during steps).
    var caption: String
    /// "Waiting for FiiO K7…" on auto-detected steps; nil hides the pulse.
    var waitingText: String?
    var isExpanded = true
    var phase: Phase {
        didSet { if phase != oldValue { expand() } }
    }
    var voiceMuted = false
    var musicMuted = false
    /// The illustration variant chosen per step (see `LiftoffConfig.illustrationVariants`).
    var illustrationVariants: [StepID: Int] = [:]

    var onDone: () -> Void = {}
    var onSkip: () -> Void = {}
    var onSkipAll: () -> Void = {}
    var onToggleVoice: () -> Void = {}
    var onToggleMusic: () -> Void = {}
    /// "Open Teams" etc. on app steps (Return in fullscreen): launch / bring forward the step's app.
    var onOpenApp: () -> Void = {}
    /// Esc in fullscreen mode: hand the rest of the run over to the notch panel.
    var onEscapeToNotch: () -> Void = {}
    /// The user picked another illustration variant (already applied here); the coordinator saves it.
    var onIllustrationVariantChanged: (StepID, Int) -> Void = { _, _ in }

    /// Seconds the pointer must stay outside before the panel collapses.
    @ObservationIgnored var idleCollapseDelay: Duration = .seconds(4)
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var pointerInside = false
    /// The current step's prompt line has finished.
    @ObservationIgnored private var promptEnded = false

    /// `doneOnlySteps` defaults to the `.manual` steps.
    init(steps: [StepDefinition], doneOnlySteps: Set<Int>? = nil, currentIndex: Int? = nil, ticked: Set<Int> = [],
         caption: String = "", waitingText: String? = nil, phase: Phase = .greeting) {
        self.steps = steps
        self.doneOnlySteps = doneOnlySteps ?? Set(steps.indices.filter { steps[$0].rule == .manual })
        self.currentIndex = currentIndex
        self.ticked = ticked
        self.caption = caption
        self.waitingText = waitingText
        self.phase = phase
    }

    var currentStep: StepDefinition? {
        guard let i = currentIndex, steps.indices.contains(i) else { return nil }
        return steps[i]
    }

    /// Only Done can tick the current step: it shows a prominent Done (and accepts Space) instead
    /// of a waiting pulse. Other waiting steps show a secondary Done next to Skip.
    var isDoneOnlyStep: Bool {
        guard let i = currentIndex, phase == .step else { return false }
        return doneOnlySteps.contains(i)
    }

    /// "Open Teams" / "Open Apple Music" / "Open Agent Factory" while an app step waits; nil otherwise.
    var openAppTitle: String? {
        guard phase == .step, let i = currentIndex, let step = currentStep, !ticked.contains(i) else { return nil }
        return appLaunchTarget(for: step)?.buttonTitle
    }

    func illustrationVariant(for id: StepID) -> Int {
        illustrationVariants[id] ?? 1
    }

    func selectIllustrationVariant(_ variant: Int, for id: StepID) {
        guard illustrationVariant(for: id) != variant else { return }
        illustrationVariants[id] = variant
        onIllustrationVariantChanged(id, variant)
    }

    // MARK: Collapse rules (spec §5.3)

    /// Call when the step's prompt voice line finishes. With the pointer away, Done-only steps
    /// collapse now and waiting steps after `idleCollapseDelay`; with it over the panel, nothing yet.
    func promptLineEnded() {
        guard phase == .step else { return }
        promptEnded = true
        guard !pointerInside else { return }
        if isDoneOnlyStep {
            collapse()
        } else {
            scheduleCollapse()
        }
    }

    /// Hover expands; leaving starts the idle-collapse countdown during steps (on a Done-only step
    /// only once its prompt has been spoken).
    func pointerChanged(inside: Bool) {
        pointerInside = inside
        if inside {
            expand()
        } else if phase == .step, !isDoneOnlyStep || promptEnded {
            scheduleCollapse()
        }
    }

    func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        if !isExpanded { isExpanded = true }
    }

    func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        if isExpanded { isExpanded = false }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        let delay = idleCollapseDelay
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.pointerInside, self.phase == .step else { return }
            self.collapse()
        }
    }
}
