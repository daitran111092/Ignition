import SwiftUI
import LiftoffCore

/// The notch panel's content: style B "gradient drop" card when expanded, a slim strip hugging
/// the hardware notch when compact (spec §5.3, mockup `notch-v2.html`).
struct NotchView: View {
    let model: SequenceViewModel
    let geometry: NotchGeometry
    /// Called after the Done / Skip buttons and ⋯ menu actions fire (the panel gives up key focus).
    var onAction: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph

    var body: some View {
        let layout = NotchLayout(geometry: geometry, phase: model.phase, isExpanded: model.isExpanded)
        let shape = NotchShape(bottomRadius: layout.bottomRadius, ear: layout.ear, topRadius: layout.topRadius)
        ZStack(alignment: .top) {
            background(layout)
            content(layout)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .clipShape(shape)
        .overlay(shape.stroke(gloss, lineWidth: 1))
        .contentShape(shape)
        .onHover { model.pointerChanged(inside: $0) }
        .animation(resizeAnimation, value: model.isExpanded)
        .animation(resizeAnimation, value: model.phase)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Background

    private var palette: StepPalette { .current(for: model) }

    private var backgroundKey: String { StepPalette.key(for: model) }

    /// Always laid out at the expanded height and pinned to the top, so the compact strip
    /// (which only shows the top band) is the same black as the notch.
    private func background(_ layout: NotchLayout) -> some View {
        ZStack {
            Color.black
            ZStack {
                palette.dropGradient
                // Soft bloom of the brightest stop behind the illustration, kept out of the black top band.
                RadialGradient(colors: [palette.accent.opacity(0.7), .clear],
                               center: UnitPoint(x: 0.18, y: 0.9), startRadius: 0, endRadius: 260)
                    .blendMode(.screen)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black, location: 0.75)],
                                         startPoint: .top, endPoint: .bottom))
            }
            .id(backgroundKey)
            .transition(.opacity)
        }
        .frame(width: layout.size.width, height: layout.expandedHeight)
        .animation(.easeInOut(duration: 0.6), value: backgroundKey)
    }

    /// Faint rim light along the bottom edge for a glossy finish.
    private var gloss: LinearGradient {
        LinearGradient(colors: [.white.opacity(0), .white.opacity(model.isExpanded ? 0.22 : 0.08)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ layout: NotchLayout) -> some View {
        if model.isExpanded {
            Group {
                switch model.phase {
                case .greeting: greeting
                case .step: stepCard
                case .liftoff: liftoffCard
                }
            }
            .padding(.horizontal, 26 + layout.ear)
            .padding(.bottom, 18)
            .padding(.top, layout.topInset + (geometry.hasNotch ? 8 : 16))
            .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
            .transition(contentTransition)
        } else {
            compactStrip(layout)
                .frame(width: layout.size.width, height: layout.size.height)
                .transition(.opacity)
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Good morning, Commander.")
                        .font(.system(size: 26, weight: .bold))
                        .kerning(-0.5)
                    Text(model.caption.isEmpty ? defaultGreetingLine : model.caption)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer(minLength: 12)
                moreButton
            }
            Spacer(minLength: 0)
            StepRail(count: model.steps.count, ticked: model.ticked, current: nil)
        }
        .foregroundStyle(.white)
    }

    private var defaultGreetingLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return "\(formatter.string(from: Date())) · \(model.steps.count) steps · about 5 minutes"
    }

    @ViewBuilder
    private var stepCard: some View {
        if let step = model.currentStep, let index = model.currentIndex {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 22) {
                    StepVisual(step: step, size: 112, variant: model.illustrationVariant(for: step.id)) {
                        model.selectIllustrationVariant($0, for: step.id)
                        onAction()  // a click on the card made the panel key: give it back
                    }
                        .morph("icon", in: morph, enabled: !reduceMotion)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center) {
                            Text("Step \(index + 1) of \(model.steps.count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                            Spacer(minLength: 8)
                            moreButton
                        }
                        Text(step.title)
                            .font(.system(size: 22, weight: .bold))
                            .kerning(-0.4)
                            .lineLimit(1)
                            .morph("title", in: morph, enabled: !reduceMotion)
                        Text(step.instruction)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                        actions.padding(.top, 11)
                    }
                }
                .id(index)
                .transition(.opacity)
                Spacer(minLength: 0)
                StepRail(count: model.steps.count, ticked: model.ticked, current: index)
            }
            .foregroundStyle(.white)
            .animation(.easeInOut(duration: 0.6), value: index)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if model.isDoneOnlyStep {
                Button { model.onDone(); onAction() } label: {
                    HStack(spacing: 6) {
                        Text("Done")
                        Text("space").font(.system(size: 10, weight: .medium)).opacity(0.45)
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            } else if let openTitle = model.openAppTitle {
                // App steps: the waiting line becomes the way to get there.
                WaitingPulse(size: 8)
                Button(openTitle) { model.onOpenApp(); onAction() }
                    .buttonStyle(PillButtonStyle(prominent: true))
            } else if let waiting = model.waitingText {
                WaitingPulse(size: 8)
                Text(waiting)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !model.isDoneOnlyStep, model.waitingText != nil {
                // Auto-detected steps can be confirmed by hand too (e.g. the detector misses it).
                Button("Done") { model.onDone(); onAction() }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
            Button("Skip") { model.onSkip(); onAction() }
                .buttonStyle(PillButtonStyle(prominent: false))
        }
        .frame(height: 26)
    }

    private var liftoffCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("All systems go.")
                        .font(.system(size: 26, weight: .bold))
                        .kerning(-0.5)
                    Text(model.caption.isEmpty ? "Have a great day, Commander." : model.caption)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 12)
                if let step = model.steps.last {
                    StepVisual(step: step, size: 76, variant: model.illustrationVariant(for: step.id))
                        .morph("icon", in: morph, enabled: !reduceMotion)
                        .padding(.top, -14)
                }
            }
            Spacer(minLength: 0)
            StepRail(count: model.steps.count, ticked: Set(model.steps.indices), current: nil)
        }
        .foregroundStyle(.white)
    }

    // MARK: Compact

    private func compactStrip(_ layout: NotchLayout) -> some View {
        let step: StepDefinition? = model.phase == .liftoff ? model.steps.last : model.currentStep
        let title = switch model.phase {
        case .greeting: "Good morning"
        case .step: step?.title ?? ""
        case .liftoff: "All systems go"
        }
        let symbol = model.phase == .greeting ? "sun.horizon.fill" : (step?.symbol ?? "circle")
        let progress = model.steps.isEmpty ? 0 : Double(model.ticked.count) / Double(model.steps.count)
        return HStack(spacing: 0) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.tileGradient)
                    .overlay(Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white))
                    .frame(width: 20, height: 20)
                    .morph("icon", in: morph, enabled: !reduceMotion)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .morph("title", in: morph, enabled: !reduceMotion)
            }
            Spacer(minLength: geometry.notchSize.width + 8)
            HStack(spacing: 8) {
                if model.phase == .step, !model.isDoneOnlyStep, model.waitingText != nil {
                    WaitingPulse(size: 6)
                }
                ProgressRing(progress: progress)
                    .frame(width: 18, height: 18)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12 + layout.ear)
    }

    // MARK: Shared bits

    private var moreButton: some View {
        MoreButton { NotchMenu.show(for: model, afterAction: onAction) }
    }

    private var resizeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.42, dampingFraction: 0.8)
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
    }
}

// MARK: - Small pieces

/// One-segment-per-step progress rail: done = white, current = 65 % white, rest = 20 % white.
private struct StepRail: View {
    let count: Int
    let ticked: Set<Int>
    let current: Int?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(ticked.contains(i) ? 1 : (i == current ? 0.65 : 0.2)))
                    .frame(height: 4)
            }
        }
        .animation(.easeOut(duration: 0.4), value: ticked)
        .animation(.easeOut(duration: 0.4), value: current)
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

private extension View {
    /// Matched-geometry morph between the compact and expanded layouts (off under Reduce Motion).
    @ViewBuilder
    func morph(_ id: String, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if enabled {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
