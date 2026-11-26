import CoreGraphics
import LiftoffCore

/// Sizes of the notch panel for a given screen, phase and expansion (spec §5.3).
struct NotchLayout: Equatable {
    static let expandedWidth: CGFloat = 600
    static let stepHeight: CGFloat = 200
    static let cardHeight: CGFloat = 156   // greeting / liftoff
    static let compactMinWidth: CGFloat = 330
    static let compactMinHeight: CGFloat = 34
    /// Room for icon + step name (left) and ring (right) beside the hardware notch.
    static let compactWing: CGFloat = 112

    let geometry: NotchGeometry
    let isExpanded: Bool
    let expandedHeight: CGFloat

    init(geometry: NotchGeometry, phase: SequenceViewModel.Phase, isExpanded: Bool) {
        self.geometry = geometry
        self.isExpanded = isExpanded
        expandedHeight = phase == .step ? Self.stepHeight : Self.cardHeight
    }

    /// Concave "ears" where the panel meets the top screen edge (only when hugging a notch).
    var ear: CGFloat { geometry.hasNotch ? (isExpanded ? 12 : 8) : 0 }
    var bottomRadius: CGFloat { isExpanded ? 26 : 16 }
    var topRadius: CGFloat { geometry.hasNotch ? 0 : (isExpanded ? 18 : 12) }
    /// Height hidden behind the hardware notch / menu bar band that content must stay below.
    var topInset: CGFloat { geometry.notchSize.height }

    var compactHeight: CGFloat { max(Self.compactMinHeight, geometry.notchSize.height) }

    /// The visible panel, ears included. The window is exactly this size: no transparent margin
    /// that could swallow clicks meant for the app underneath (the window server draws the shadow).
    var size: CGSize {
        if isExpanded {
            return CGSize(width: Self.expandedWidth + 2 * ear, height: expandedHeight)
        }
        let body = geometry.hasNotch
            ? max(Self.compactMinWidth, geometry.notchSize.width + 2 * Self.compactWing)
            : Self.compactMinWidth
        return CGSize(width: body + 2 * ear, height: compactHeight)
    }
}
