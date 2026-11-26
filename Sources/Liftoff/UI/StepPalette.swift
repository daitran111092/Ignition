import SwiftUI
import LiftoffCore

/// LiftoffCore's colour (SwiftUI on newer SDKs has its own `RGBColor`).
typealias HexRGB = LiftoffCore.RGBColor

/// SwiftUI colours for a step's hex gradient (config order: top/light → bottom/dark).
struct StepPalette {
    let rgb: [HexRGB]

    init(_ step: StepDefinition?) {
        self.init(hexStops: step?.gradient ?? [])
    }

    init(hexStops: [String]) {
        let parsed = hexStops.compactMap { HexRGB(hex: $0) }
        rgb = parsed.isEmpty ? [HexRGB(red: 0.25, green: 0.25, blue: 0.25), HexRGB(red: 0.08, green: 0.08, blue: 0.08)] : parsed
    }

    /// Deep indigo for the greeting card, before any step has a colour.
    static let greeting = StepPalette(hexStops: ["#3d2c78", "#0e0b1f"])

    /// The palette for whatever the model is showing (greeting, current step, or the final step at liftoff).
    @MainActor static func current(for model: SequenceViewModel) -> StepPalette {
        switch model.phase {
        case .greeting: .greeting
        case .step: StepPalette(model.currentStep)
        case .liftoff: StepPalette(model.steps.last)
        }
    }

    /// Changes whenever the background should cross-fade to a new palette.
    @MainActor static func key(for model: SequenceViewModel) -> String {
        switch model.phase {
        case .greeting: "greeting"
        case .step: "step-\(model.currentIndex ?? -1)"
        case .liftoff: "liftoff"
        }
    }

    var stops: [Color] { rgb.map(Self.color) }

    /// The brightest (first) stop — used for glows and accents.
    var accent: Color { stops[0] }

    /// Style B "gradient drop": black for the top 18 % (merging into the notch), then the step's
    /// stops from darkest to brightest so the colour pools at the bottom edge.
    var dropGradient: LinearGradient {
        let tail = Array(stops.reversed())
        var gradientStops: [Gradient.Stop] = [.init(color: .black, location: 0), .init(color: .black, location: 0.18)]
        for (i, color) in tail.enumerated() {
            let t = tail.count == 1 ? 1 : Double(i) / Double(tail.count - 1)
            gradientStops.append(.init(color: color, location: 0.6 + 0.4 * t))
        }
        return LinearGradient(stops: gradientStops, startPoint: .top, endPoint: .bottom)
    }

    /// Diagonal fill for small tiles (compact-mode step icon).
    var tileGradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Fullscreen ("B · cinematic", look-v1)

    private var bright: HexRGB { rgb[0] }
    private var dark: HexRGB { rgb[rgb.count - 1] }
    private static let black = HexRGB(red: 0, green: 0, blue: 0)
    private static let white = HexRGB(red: 1, green: 1, blue: 1)

    /// 150° base wash: deep → rich middle → near-black (for the K7 red this lands on the mockup's
    /// `#5a0f22 → #8e1a2a → #3a0a26`). A three-stop gradient (liftoff) builds on its middle colour
    /// and keeps the bright first stop for the highlight.
    var cinematicBase: LinearGradient {
        let middle = rgb.count > 2 ? rgb[rgb.count / 2] : bright.mixed(with: dark, by: 0.35)
        let start = rgb.count > 2 ? middle.mixed(with: dark, by: 0.6) : bright.mixed(with: dark, by: 0.72)
        return LinearGradient(colors: [start, middle, dark.mixed(with: Self.black, by: 0.2)].map(Self.color),
                              startPoint: UnitPoint(x: 0.21, y: 0), endPoint: UnitPoint(x: 0.79, y: 1))
    }

    /// Soft light pooled behind the illustration (upper right of centre).
    var cinematicHighlight: Color { Self.color(bright.mixed(with: Self.white, by: 0.22)) }

    /// Dark bloom in the lower-left corner.
    var cinematicShade: Color { Self.color(dark.mixed(with: bright, by: 0.3)) }

    private static func color(_ c: HexRGB) -> Color {
        Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }
}
