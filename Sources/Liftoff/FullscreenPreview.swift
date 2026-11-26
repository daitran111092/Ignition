import AppKit
import SwiftUI
import LiftoffCore

/// Hidden developer flags for the fullscreen stage:
/// `--preview-fullscreen <stepIndex|greeting>` shows it live (Esc hands over to the notch panel at
/// the same step; exits after 20 s); `--render-fullscreen <stepIndex> <out.png> [variant]` writes PNG
/// snapshots showing the step's illustration `variant` (default 1).
@MainActor
enum FullscreenPreview {
    static func run(arguments: [String]) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = NotchPreview.makeModel(stepArgument: arguments.first)
        model.onDone = { print("done") }
        model.onSkip = { print("skip") }
        model.onSkipAll = { print("skip all"); exit(0) }
        model.onToggleVoice = { model.voiceMuted.toggle() }
        model.onToggleMusic = { model.musicMuted.toggle() }
        let fullscreen = FullscreenPresenter(model: model)
        var notch: NotchPanel?
        model.onEscapeToNotch = {
            guard notch == nil else { return }
            print("escape → notch")
            model.expand()
            fullscreen.hide(animated: true)
            let panel = NotchPanel(model: model)
            panel.show()
            notch = panel
        }
        fullscreen.show()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            exit(0)
        }
        app.run()
    }

    /// Writes `<out>-step.png`, `-hover.png` (variant switcher shown, if the step has variants),
    /// `-greeting.png`, `-liftoff.png` at 1512×982 (14-inch MacBook Pro).
    static func render(arguments: [String]) {
        guard (2...3).contains(arguments.count), let index = Int(arguments[0]),
              let variant = arguments.count == 3 ? Int(arguments[2]) : 1 else {
            print("usage: Ignition --render-fullscreen <stepIndex> <out.png> [variant]")
            exit(2)
        }
        let base = URL(fileURLWithPath: arguments[1]).deletingPathExtension().path
        let lastIndex = LiftoffConfig.default.steps.count - 1
        for (suffix, argument, hover) in [("step", String(index), false), ("hover", String(index), true),
                                          ("greeting", "greeting", false), ("liftoff", String(lastIndex), false)] {
            let model = NotchPreview.makeModel(stepArgument: argument, variant: variant)
            let view = FullscreenView(model: model, topInset: 32).frame(width: 1512, height: 982)
                .environment(\.showsVariantSwitcher, hover)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let path = "\(base)-\(suffix).png"
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                print("render failed: \(path)"); exit(1)
            }
            do { try png.write(to: URL(fileURLWithPath: path)) } catch { print("write failed: \(error)"); exit(1) }
            print("wrote \(path)")
        }
        exit(0)
    }
}
