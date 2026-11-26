import SwiftUI
import LiftoffCore

/// Fullscreen "B · cinematic" stage (spec §5.4, mockup `look-v1.html`): full-bleed step gradient
/// with a soft radial highlight, the device large in the centre, a 46 pt title, a subtitle-style
/// caption pill, and the one-node-per-step journey rail along the bottom.
struct FullscreenView: View {
    let model: SequenceViewModel
    /// Height of the menu bar / notch band at the top of the screen, kept clear of text.
    var topInset: CGFloat = 0
    /// Opens the ⋯ menu (the window has to step below menu level first).
    var onMore: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 24)
                stage
                Spacer(minLength: 24)
                JourneyRail(steps: model.steps, ticked: displayedTicks, current: railCurrent)
                    .padding(.bottom, 40)
            }
            .padding(.top, topInset)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Backdrop

    private var backdrop: some View {
        let palette = StepPalette.current(for: model)
        return ZStack {
            palette.cinematicBase
            EllipticalGradient(colors: [palette.cinematicShade.opacity(0.9), .clear],
                               center: UnitPoint(x: 0.1, y: 1), startRadiusFraction: 0, endRadiusFraction: 0.75)
            EllipticalGradient(colors: [palette.cinematicHighlight.opacity(0.55), .clear],
                               center: UnitPoint(x: 0.6, y: 0.38), startRadiusFraction: 0, endRadiusFraction: 0.6)
        }
        .id(StepPalette.key(for: model))
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.6), value: StepPalette.key(for: model))
        .ignoresSafeArea()
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Text(stepCounter)
                .frame(minWidth: 120, alignment: .leading)
            Spacer()
            TimelineView(.everyMinute) { context in
                Text(Self.topline(context.date))
            }
            Spacer()
            HStack {
                Spacer()
                MoreButton(diameter: 30, action: onMore)
            }
            .frame(width: 120)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 28)
        .padding(.top, 16)
    }

    private var stepCounter: String {
        guard model.phase == .step, let i = model.currentIndex else { return "" }
        return "Step \(i + 1) of \(model.steps.count)"
    }

    private static func topline(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        return "\(formatter.string(from: date)) · \(time.string(from: date))"
    }

    // MARK: Stage

    private var stage: some View {
        VStack(spacing: 0) {
            visual
            if model.phase == .greeting {
                Text("\(Brand.name.uppercased()) · \(Brand.slogan)")
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 18)
            }
            Text(title)
                .font(.system(size: 46, weight: .bold))
                .kerning(-1.4)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .padding(.top, 18)
            captionPill
                .padding(.top, 16)
            actions
                .padding(.top, 22)
        }
        .id(StepPalette.key(for: model))
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        .animation(.easeInOut(duration: 0.6), value: StepPalette.key(for: model))
        .padding(.horizontal, 40)
    }

    /// Size of the step illustration on the stage.
    private static let visualSize: CGFloat = 540

    @ViewBuilder
    private var visual: some View {
        switch model.phase {
        case .greeting:
            SymbolOrb(symbol: "sun.horizon.fill", accent: StepPalette.greeting.accent, size: Self.visualSize)
        case .step:
            if let step = model.currentStep {
                StepVisual(step: step, size: Self.visualSize, variant: model.illustrationVariant(for: step.id)) {
                    model.selectIllustrationVariant($0, for: step.id)
                }
            }
        case .liftoff:
            if let step = model.steps.last {
                StepVisual(step: step, size: Self.visualSize, variant: model.illustrationVariant(for: step.id))
            }
        }
    }

    private var title: String {
        switch model.phase {
        case .greeting: "Good morning, Commander."
        case .step: model.currentStep?.title ?? ""
        case .liftoff: "All systems go."
        }
    }

    private var captionPill: some View {
        HStack(alignment: .center, spacing: 12) {
            if model.phase == .step, !model.isDoneOnlyStep, model.waitingText != nil {
                WaitingPulse(size: 8)
            }
            captionText
                .font(.system(size: 16))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.28)))
        .frame(maxWidth: 560)
    }

    private var captionText: Text {
        switch model.phase {
        case .greeting:
            return Text(model.caption.isEmpty ? "\(model.steps.count) steps · about 5 minutes" : model.caption)
        case .liftoff:
            return Text(model.caption.isEmpty ? "Have a great day, Commander." : model.caption)
        case .step:
            // The spoken line while the coordinator has one, else the step's instruction.
            let line = Text(model.caption.isEmpty ? model.currentStep?.instruction ?? "" : model.caption)
            guard !model.isDoneOnlyStep, let waiting = model.waitingText else { return line }
            return line + Text("  " + waiting).foregroundColor(.white.opacity(0.55))
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.phase == .step {
            HStack(spacing: 12) {
                if let openTitle = model.openAppTitle {
                    Button(action: model.onOpenApp) {
                        HStack(spacing: 8) {
                            Text(openTitle)
                            Text("return").font(.system(size: 11, weight: .medium)).opacity(0.45)
                        }
                    }
                    .buttonStyle(PillButtonStyle(prominent: true, height: 34))
                }
                if model.isDoneOnlyStep {
                    Button(action: model.onDone) {
                        HStack(spacing: 8) {
                            Text("Done")
                            Text("space").font(.system(size: 11, weight: .medium)).opacity(0.45)
                        }
                    }
                    .buttonStyle(PillButtonStyle(prominent: true, height: 34))
                } else if model.waitingText != nil {
                    // Auto-detected steps can be confirmed by hand too.
                    Button("Done", action: model.onDone)
                        .buttonStyle(PillButtonStyle(prominent: false, height: 34))
                }
                Button(action: model.onSkip) {
                    HStack(spacing: 8) {
                        Text("Skip")
                        Text("S").font(.system(size: 11, weight: .medium)).opacity(0.5)
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: false, height: 34))
            }
        } else {
            // Keeps the title block at the same height across phases.
            Color.clear.frame(height: 34)
        }
    }

    // MARK: Rail

    private var displayedTicks: Set<Int> {
        model.phase == .liftoff ? Set(model.steps.indices) : model.ticked
    }

    private var railCurrent: Int? {
        model.phase == .step ? model.currentIndex : nil
    }
}

/// One node per step (its symbol) joined by short bars: done = green-tinted, current = larger
/// with a glow in the step's colour, upcoming = dim.
private struct JourneyRail: View {
    let steps: [StepDefinition]
    let ticked: Set<Int>
    let current: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let green = Color(.sRGB, red: 125 / 255, green: 1, blue: 176 / 255)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                if i > 0 {
                    Capsule()
                        .fill(ticked.contains(i - 1) && (ticked.contains(i) || i == current)
                              ? Self.green.opacity(0.8) : .white.opacity(0.2))
                        .frame(width: 14, height: 2)
                }
                node(step, index: i)
            }
        }
        .frame(height: 56)
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(response: 0.45, dampingFraction: 0.75),
                   value: current)
        .animation(.easeOut(duration: 0.4), value: ticked)
    }

    private func node(_ step: StepDefinition, index: Int) -> some View {
        let isCurrent = index == current
        let isDone = ticked.contains(index) && !isCurrent
        let side: CGFloat = isCurrent ? 52 : 40
        let glow = StepPalette(step).cinematicHighlight
        return RoundedRectangle(cornerRadius: isCurrent ? 15 : 12, style: .continuous)
            .fill(isCurrent ? Color.white.opacity(0.22) : (isDone ? Self.green.opacity(0.22) : .white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: isCurrent ? 15 : 12, style: .continuous)
                    .strokeBorder(isCurrent ? Color.white.opacity(0.6) : (isDone ? Self.green.opacity(0.6) : .white.opacity(0.12)),
                                  lineWidth: 1)
            )
            .overlay(
                Image(systemName: step.symbol)
                    .symbolVariant(.fill)
                    .font(.system(size: isCurrent ? 21 : 16, weight: .medium))
                    .foregroundStyle(.white)
            )
            .frame(width: side, height: side)
            .shadow(color: isCurrent ? glow.opacity(0.75) : .clear, radius: 18)
            .opacity(isCurrent || isDone ? 1 : 0.55)
    }
}
