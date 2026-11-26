import Testing
import CoreGraphics
import Foundation
@testable import LiftoffCore

@Suite struct NotchGeometryTests {
    // 14" MacBook Pro-like main screen: 1512×982, menu bar/notch 38 pt.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)

    @Test func notchedScreenMeasuresNotchFromAuxiliaryAreas() {
        let left = CGRect(x: 0, y: 944, width: 662, height: 38)
        let right = CGRect(x: 847, y: 944, width: 665, height: 38)
        let g = NotchGeometry(screenFrame: screen, visibleFrame: visible, safeAreaTop: 38,
                              auxiliaryTopLeft: left, auxiliaryTopRight: right)
        #expect(g.hasNotch)
        #expect(g.notchSize == CGSize(width: 185, height: 38))
        #expect(g.centerX == 754.5)
        #expect(g.topY == 982)  // over the notch, at the very top of the screen
    }

    @Test func noNotchCentresUnderTheMenuBar() {
        let g = NotchGeometry(screenFrame: screen, visibleFrame: visible, safeAreaTop: 0,
                              auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        #expect(!g.hasNotch)
        #expect(g.notchSize == .zero)
        #expect(g.centerX == 756)
        #expect(g.topY == 944)
    }

    @Test func safeAreaWithoutAuxiliaryAreasIsTreatedAsNoNotch() {
        let g = NotchGeometry(screenFrame: screen, visibleFrame: visible, safeAreaTop: 38,
                              auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        #expect(!g.hasNotch)
    }

    @Test func panelFrameHangsFromTopCentre() {
        let g = NotchGeometry(screenFrame: screen, visibleFrame: visible, safeAreaTop: 0,
                              auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        #expect(g.panelFrame(size: CGSize(width: 600, height: 200)) == CGRect(x: 456, y: 744, width: 600, height: 200))
    }

    @Test func panelFrameStaysOnScreenHorizontally() {
        let small = CGRect(x: 100, y: 0, width: 400, height: 600)
        let g = NotchGeometry(screenFrame: small, visibleFrame: small, safeAreaTop: 0,
                              auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        #expect(g.panelFrame(size: CGSize(width: 600, height: 200)).minX == 100)
    }

    @Test func secondaryScreenOffsetsAreRespected() {
        let s = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let v = CGRect(x: -1920, y: 200, width: 1920, height: 1055)
        let g = NotchGeometry(screenFrame: s, visibleFrame: v, safeAreaTop: 0,
                              auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        #expect(g.panelFrame(size: CGSize(width: 600, height: 200)) == CGRect(x: -1260, y: 1055, width: 600, height: 200))
    }
}
