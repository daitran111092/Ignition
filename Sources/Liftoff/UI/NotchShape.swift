import SwiftUI

/// The panel outline: square top that melts into the screen edge, concave "ears" at the top
/// corners (like the hardware notch), rounded bottom corners. Without a notch `topRadius`
/// rounds the top too, for a card hanging under the menu bar.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var ear: CGFloat
    var topRadius: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, ear) }
        set { bottomRadius = newValue.first; ear = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let body = rect.insetBy(dx: ear, dy: 0)
        let r = min(bottomRadius, body.width / 2, body.height / 2)
        let t = min(topRadius, body.height / 2)
        var p = Path()
        if ear > 0 {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: body.minX, y: rect.minY + ear), control: CGPoint(x: body.minX, y: rect.minY))
        } else {
            p.move(to: CGPoint(x: body.minX, y: body.minY + t))
            if t > 0 { p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + t, y: body.minY), radius: t) }
            p.addLine(to: CGPoint(x: body.maxX - t, y: body.minY))
            if t > 0 { p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + t), radius: t) }
        }
        if ear > 0 {
            // left side down, bottom, right side up, right ear back to the top edge
            p.addLine(to: CGPoint(x: body.minX, y: body.maxY - r))
            p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX + r, y: body.maxY), radius: r)
            p.addLine(to: CGPoint(x: body.maxX - r, y: body.maxY))
            p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX, y: body.maxY - r), radius: r)
            p.addLine(to: CGPoint(x: body.maxX, y: rect.minY + ear))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: body.maxX, y: rect.minY))
        } else {
            p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
            p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
            p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
            p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        }
        p.closeSubpath()
        return p
    }
}
