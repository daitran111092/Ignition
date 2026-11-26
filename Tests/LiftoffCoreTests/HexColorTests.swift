import Testing
@testable import LiftoffCore

@Suite struct HexColorTests {
    @Test func parsesSixDigitWithHash() throws {
        let c = try #require(RGBColor(hex: "#ff8000"))
        #expect(c == RGBColor(red: 1, green: 128.0 / 255, blue: 0))
    }

    @Test func parsesWithoutHashAndUppercase() {
        #expect(RGBColor(hex: "B3203A") == RGBColor(hex: "#b3203a"))
    }

    @Test func parsesThreeDigitShorthand() {
        #expect(RGBColor(hex: "#fff") == RGBColor(red: 1, green: 1, blue: 1))
    }

    @Test func trimsWhitespace() {
        #expect(RGBColor(hex: "  #000000 ") == RGBColor(red: 0, green: 0, blue: 0))
    }

    @Test(arguments: ["", "#", "#12", "#12345", "#gggggg", "#1234567", "#+12345"])
    func rejectsMalformed(_ hex: String) {
        #expect(RGBColor(hex: hex) == nil)
    }

    @Test func everyDefaultGradientStopParses() {
        for step in LiftoffConfig.default.steps {
            #expect(step.gradient.compactMap(RGBColor.init(hex:)).count == step.gradient.count, "\(step.id)")
        }
    }

    @Test func mixInterpolatesComponentwise() {
        let black = RGBColor(red: 0, green: 0, blue: 0)
        let white = RGBColor(red: 1, green: 1, blue: 1)
        #expect(black.mixed(with: white, by: 0) == black)
        #expect(black.mixed(with: white, by: 1) == white)
        let quarter = RGBColor(red: 0.2, green: 0.4, blue: 1).mixed(with: black, by: 0.25)
        #expect(abs(quarter.red - 0.15) < 1e-9 && abs(quarter.green - 0.3) < 1e-9 && abs(quarter.blue - 0.75) < 1e-9)
    }

    @Test func mixClampsAmount() {
        let a = RGBColor(red: 0.1, green: 0.2, blue: 0.3)
        let b = RGBColor(red: 0.9, green: 0.8, blue: 0.7)
        #expect(a.mixed(with: b, by: -1) == a)
        #expect(a.mixed(with: b, by: 2) == b)
    }
}
