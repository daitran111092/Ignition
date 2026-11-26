import Foundation

/// An sRGB colour parsed from a `#rrggbb` / `#rgb` hex string (components 0…1).
public struct RGBColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Accepts `#rrggbb`, `rrggbb`, `#rgb` or `rgb` (case-insensitive, surrounding whitespace ignored).
    public init?(hex: String) {
        var digits = Substring(hex.trimmingCharacters(in: .whitespaces))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = Substring(digits.flatMap { [$0, $0] }) }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }

    /// Linear blend towards `other`: 0 → self, 1 → other (amount clamped to 0…1).
    public func mixed(with other: RGBColor, by amount: Double) -> RGBColor {
        let t = min(max(amount, 0), 1)
        return RGBColor(red: red + (other.red - red) * t,
                        green: green + (other.green - green) * t,
                        blue: blue + (other.blue - blue) * t)
    }
}
