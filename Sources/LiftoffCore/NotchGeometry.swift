import CoreGraphics

/// Where the notch panel hangs on a screen (AppKit coordinates, origin bottom-left).
///
/// With a hardware notch the panel's top edge is the screen's top edge (it covers the notch)
/// and it is centred on the notch; without one it hangs from just under the menu bar.
public struct NotchGeometry: Equatable, Sendable {
    public var hasNotch: Bool
    /// Hardware notch size; `.zero` without a notch.
    public var notchSize: CGSize
    public var centerX: CGFloat
    /// Y of the panel's top edge.
    public var topY: CGFloat
    public var screenFrame: CGRect

    /// - Parameters: the `NSScreen` values `frame`, `visibleFrame`, `safeAreaInsets.top`,
    ///   `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`.
    public init(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
                auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?) {
        self.screenFrame = screenFrame
        if safeAreaTop > 0, let left = auxiliaryTopLeft, let right = auxiliaryTopRight, right.minX > left.maxX {
            hasNotch = true
            notchSize = CGSize(width: right.minX - left.maxX, height: safeAreaTop)
            centerX = (left.maxX + right.minX) / 2
            topY = screenFrame.maxY
        } else {
            hasNotch = false
            notchSize = .zero
            centerX = screenFrame.midX
            topY = visibleFrame.maxY
        }
    }

    /// Frame for a panel of `size` hanging from `topY`, centred on the notch, kept within the screen horizontally.
    public func panelFrame(size: CGSize) -> CGRect {
        let maxX = max(screenFrame.minX, screenFrame.maxX - size.width)
        let x = min(max(centerX - size.width / 2, screenFrame.minX), maxX)
        return CGRect(x: x, y: topY - size.height, width: size.width, height: size.height)
    }
}
