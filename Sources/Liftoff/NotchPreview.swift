import AppKit
import SwiftUI
import LiftoffCore

/// Hidden developer flags for eyeballing the notch panel without the full app:
/// `--preview-notch <stepIndex|greeting>` shows the live panel; `--render-notch <stepIndex> <out.png> [variant]`
/// writes PNG snapshots of every state (works without Screen Recording permission), showing the
/// step's illustration `variant` (default 1).
@MainActor
enum NotchPreview {
    /// Shows the panel with a static model; exits on Esc (after clicking the panel) or after 20 s.
    static func run(arguments: [String]) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = makeModel(stepArgument: arguments.first)
        model.onDone = { print("done") }
        model.onSkip = { print("skip") }
        model.onSkipAll = { print("skip all"); exit(0) }
        model.onToggleVoice = { model.voiceMuted.toggle() }
        model.onToggleMusic = { model.musicMuted.toggle() }
        let panel = NotchPanel(model: model)
        panel.orderFrontRegardless()
        Task { @MainActor in
            // Demonstrate the collapse rules: the "prompt line" ends after 3 s.
            try? await Task.sleep(for: .seconds(3))
            model.promptLineEnded()
            try? await Task.sleep(for: .seconds(17))
            exit(0)
        }
        app.run()
    }

    /// Writes `<out>-expanded.png`, `-hover.png` (variant switcher shown, if the step has variants),
    /// `-compact.png`, `-greeting.png`, `-liftoff.png`, `-nonotch.png`.
    static func render(arguments: [String]) {
        guard (2...3).contains(arguments.count), let index = Int(arguments[0]),
              let variant = arguments.count == 3 ? Int(arguments[2]) : 1 else {
            print("usage: Ignition --render-notch <stepIndex> <out.png> [variant]")
            exit(2)
        }
        let base = URL(fileURLWithPath: arguments[1]).deletingPathExtension().path
        let notched = NotchPanel.currentGeometry().hasNotch ? NotchPanel.currentGeometry() : sampleNotchGeometry
        let flat = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
                                 visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1135),
                                 safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil)

        let step = makeModel(stepArgument: String(index), variant: variant)
        let compact = makeModel(stepArgument: String(index), variant: variant)
        compact.isExpanded = false
        let greeting = makeModel(stepArgument: "greeting")
        let liftoff = makeModel(stepArgument: String(LiftoffConfig.default.steps.count - 1))

        for (suffix, model, geometry, hover) in [("expanded", step, notched, false), ("hover", step, notched, true),
                                                 ("compact", compact, notched, false),
                                                 ("greeting", greeting, notched, false), ("liftoff", liftoff, notched, false),
                                                 ("nonotch", step, flat, false)] {
            let path = "\(base)-\(suffix).png"
            let renderer = ImageRenderer(content: Desk(model: model, geometry: geometry)
                .environment(\.showsVariantSwitcher, hover))
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                print("render failed: \(path)"); exit(1)
            }
            do { try png.write(to: URL(fileURLWithPath: path)) } catch { print("write failed: \(error)"); exit(1) }
            print("wrote \(path)")
        }
        exit(0)
    }

    /// A static model at `stepArgument`, showing illustration `variant` for that step.
    static func makeModel(stepArgument: String?, variant: Int = 1) -> SequenceViewModel {
        let model = makeModel(stepArgument: stepArgument)
        if let step = model.currentStep, variant != 1 { model.illustrationVariants[step.id] = variant }
        return model
    }

    static func makeModel(stepArgument: String?) -> SequenceViewModel {
        let steps = LiftoffConfig.default.steps
        guard let arg = stepArgument, arg != "greeting", let index = Int(arg), steps.indices.contains(index) else {
            return SequenceViewModel(steps: steps, phase: .greeting)
        }
        if index == steps.count - 1 {
            return SequenceViewModel(steps: steps, currentIndex: index, ticked: Set(steps.indices), phase: .liftoff)
        }
        let step = steps[index]
        let doneOnly = Set(steps.indices.filter { needsManualConfirm(steps[$0], learned: []) })
        return SequenceViewModel(steps: steps, doneOnlySteps: doneOnly, currentIndex: index, ticked: Set(0..<index),
                                 waitingText: waitingText(for: step, learned: []),
                                 phase: .step)
    }

    /// 14-inch MacBook Pro notch, for rendering on Macs without one.
    private static let sampleNotchGeometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1131), safeAreaTop: 38,
        auxiliaryTopLeft: CGRect(x: 0, y: 1131, width: 791, height: 38),
        auxiliaryTopRight: CGRect(x: 1012, y: 1131, width: 788, height: 38))

    /// A fake desktop strip (wallpaper, menu bar, hardware notch) behind the panel.
    private struct Desk: View {
        let model: SequenceViewModel
        let geometry: NotchGeometry

        var body: some View {
            let menuBar = geometry.hasNotch ? geometry.notchSize.height : 30
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.11, green: 0.14, blue: 0.25), Color(red: 0.17, green: 0.2, blue: 0.35)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.black.opacity(0.25)).frame(height: menuBar)
                HStack {
                    Text("Finder   File   Edit   View").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("Wed 18 Nov  08:47").font(.system(size: 13))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .frame(height: menuBar)
                if geometry.hasNotch {
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                        .fill(.black)
                        .frame(width: geometry.notchSize.width, height: geometry.notchSize.height)
                }
                NotchView(model: model, geometry: geometry)
                    // stands in for the panel's window-server shadow, which ImageRenderer can't draw
                    .shadow(color: .black.opacity(model.isExpanded ? 0.5 : 0), radius: 22, y: 12)
                    .padding(.top, geometry.hasNotch ? 0 : menuBar)
            }
            .frame(width: 900, height: 300)
        }
    }
}
