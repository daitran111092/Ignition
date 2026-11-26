import Foundation

public enum StepID: String, Codable, CaseIterable, Sendable {
    case water, laptopStand, cables, dock, keyboard, mouse, dac, agentFactory, headphones, music, teams, liftoff
}

/// Makes `[StepID: _]` encode as a JSON object keyed by raw value (hand-editable config.json).
extension StepID: CodingKeyRepresentable {}

public enum DeviceKind: String, Codable, Sendable {
    case usb, audioOutput, display
    /// Keyboards and mice (IOHIDManager); built-in ones are excluded.
    case hid
}

public struct DeviceSignature: Codable, Hashable, Sendable {
    public var kind: DeviceKind
    public var name: String
    public var vendorID: Int?
    public var productID: Int?

    public init(kind: DeviceKind, name: String, vendorID: Int? = nil, productID: Int? = nil) {
        self.kind = kind
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
    }

    /// Same kind AND (vendor+product equal when both sides have them, else case-insensitive name equality).
    public func matches(_ other: DeviceSignature) -> Bool {
        guard kind == other.kind else { return false }
        if let v = vendorID, let p = productID, let ov = other.vendorID, let op = other.productID {
            return v == ov && p == op
        }
        return name.caseInsensitiveCompare(other.name) == .orderedSame
    }
}

public struct AppMatch: Codable, Equatable, Sendable {
    public var bundleIDs: [String]
    public var names: [String]

    public init(bundleIDs: [String] = [], names: [String] = []) {
        self.bundleIDs = bundleIDs
        self.names = names
    }
}

public enum DetectionRule: Codable, Equatable, Sendable {
    case manual
    /// `hint` is a case-insensitive name substring used when nothing is learned.
    case devices(DeviceKind, hint: String?)
    case appRunning(AppMatch)
    case appActivated(AppMatch)
    case musicPlaying
    case final
}

public struct StepDefinition: Codable, Equatable, Sendable {
    public var id: StepID
    public var title: String
    public var instruction: String
    public var rule: DetectionRule
    public var gradient: [String]
    public var symbol: String

    public init(id: StepID, title: String, instruction: String, rule: DetectionRule, gradient: [String], symbol: String) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.rule = rule
        self.gradient = gradient
        self.symbol = symbol
    }
}

public struct TriggerWindow: Codable, Equatable, Sendable {
    public var startMinute: Int = 480
    public var endMinute: Int = 630
    /// Calendar weekday numbering (1 = Sunday ... 7 = Saturday).
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    public init(startMinute: Int = 480, endMinute: Int = 630, weekdays: Set<Int> = [2, 3, 4, 5, 6]) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.weekdays = weekdays
    }

    /// Missing keys (hand-edited config.json) keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TriggerWindow()
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute) ?? d.startMinute
        endMinute = try c.decodeIfPresent(Int.self, forKey: .endMinute) ?? d.endMinute
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? d.weekdays
    }
}

public enum DisplayMode: String, Codable, Sendable {
    case notch, fullscreen
}

public struct LiftoffConfig: Codable, Equatable, Sendable {
    public var steps: [StepDefinition]
    public var learned: [StepID: [DeviceSignature]]
    public var window: TriggerWindow
    public var displayMode: DisplayMode = .notch
    public var musicVolume: Double = 0.6
    public var voiceVolume: Double = 1.0
    public var duckLevel: Double = 0.35
    public var voiceEnabled: Bool = true
    /// Plays every voice line through the "small room PA" effect; false keeps the voice dry.
    public var voiceRoomEffect: Bool = true
    public var musicEnabled: Bool = true
    public var elevenLabsVoiceID: String?
    /// The illustration variant chosen per step (1 = `<id>.png`, n = `<id>-n.png`); absent → 1.
    public var illustrationVariants: [StepID: Int] = [:]

    public init(steps: [StepDefinition], learned: [StepID: [DeviceSignature]] = [:], window: TriggerWindow = TriggerWindow()) {
        self.steps = steps
        self.learned = learned
        self.window = window
    }

    /// Missing keys (hand-edited config.json) keep their defaults; a present but invalid value
    /// still fails, so `ConfigStore` can back the file up instead of silently dropping it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LiftoffConfig.default
        // A saved step list from an older layout (e.g. the original nine steps) is replaced by the
        // current defaults; a hand-edited list with exactly the current ids is kept as-is.
        let savedSteps = try c.decodeIfPresent([StepDefinition].self, forKey: .steps)
        steps = savedSteps.flatMap { $0.map(\.id) == d.steps.map(\.id) ? $0 : nil } ?? d.steps
        learned = try c.decodeIfPresent([StepID: [DeviceSignature]].self, forKey: .learned) ?? d.learned
        window = try c.decodeIfPresent(TriggerWindow.self, forKey: .window) ?? d.window
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? d.displayMode
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? d.musicVolume
        voiceVolume = try c.decodeIfPresent(Double.self, forKey: .voiceVolume) ?? d.voiceVolume
        duckLevel = try c.decodeIfPresent(Double.self, forKey: .duckLevel) ?? d.duckLevel
        voiceEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceEnabled) ?? d.voiceEnabled
        voiceRoomEffect = try c.decodeIfPresent(Bool.self, forKey: .voiceRoomEffect) ?? d.voiceRoomEffect
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? d.musicEnabled
        elevenLabsVoiceID = try c.decodeIfPresent(String.self, forKey: .elevenLabsVoiceID)
        illustrationVariants = try c.decodeIfPresent([StepID: Int].self, forKey: .illustrationVariants) ?? d.illustrationVariants
    }

    public static let `default` = LiftoffConfig(steps: [
        StepDefinition(id: .water, title: "Pour some water",
                       instruction: "Fill your glass and tap Done.",
                       rule: .manual, gradient: ["#2aa7d8", "#0b3c63"], symbol: "drop"),
        StepDefinition(id: .laptopStand, title: "Laptop on the stand",
                       instruction: "Unfold the aluminum stand, set the laptop on it and tap Done.",
                       rule: .manual, gradient: ["#8e9aab", "#2b313b"], symbol: "laptopcomputer"),
        StepDefinition(id: .cables, title: "Check the cables",
                       instruction: "Make sure the monitor and power cables are plugged in.",
                       rule: .devices(.display, hint: nil), gradient: ["#0f5c55", "#0a2f3a"], symbol: "cable.connector"),
        StepDefinition(id: .dock, title: "Connect the dock",
                       instruction: "Plug the USB dock into the Mac.",
                       rule: .devices(.usb, hint: nil), gradient: ["#5b6577", "#232a38"], symbol: "externaldrive.connected.to.line.below"),
        StepDefinition(id: .keyboard, title: "Plug in the Reclusa",
                       instruction: "Plug the Reclusa keyboard into the dock.",
                       rule: .devices(.hid, hint: "Reclusa"), gradient: ["#2fbf8f", "#0b2a22"], symbol: "keyboard"),
        StepDefinition(id: .mouse, title: "Wake the MX Master",
                       instruction: "Switch the MX Master 4 on.",
                       rule: .devices(.hid, hint: "MX Master"), gradient: ["#e6257e", "#1b1446"], symbol: "computermouse"),
        StepDefinition(id: .dac, title: "Power up the K7",
                       instruction: "Turn the FiiO K7 on. I'll spot it automatically.",
                       rule: .devices(.audioOutput, hint: "FiiO"), gradient: ["#b3203a", "#4a0a22"], symbol: "hifispeaker"),
        StepDefinition(id: .agentFactory, title: "Open Agent Factory",
                       instruction: "Launch Agent Factory.",
                       rule: .appRunning(AppMatch(bundleIDs: ["dev.agentfactory.desktop"], names: ["Agent Factory"])),
                       gradient: ["#5c3bd6", "#1d1450"], symbol: "cpu"),
        StepDefinition(id: .headphones, title: "Headphones on",
                       instruction: "Put your headphones on and tap Done.",
                       rule: .manual, gradient: ["#3b3530", "#0e0c0b"], symbol: "headphones"),
        StepDefinition(id: .music, title: "Start the music",
                       instruction: "Press play in Apple Music.",
                       rule: .musicPlaying, gradient: ["#ff3b5c", "#7a0f3a"], symbol: "music.note"),
        StepDefinition(id: .teams, title: "Open Teams",
                       instruction: "Bring Microsoft Teams to the front.",
                       rule: .appActivated(AppMatch(bundleIDs: ["com.microsoft.teams2"], names: ["Microsoft Teams"])),
                       gradient: ["#5059c9", "#1f2259"], symbol: "person.2"),
        StepDefinition(id: .liftoff, title: "Liftoff",
                       instruction: "All systems go, Commander.",
                       rule: .final, gradient: ["#ffb35c", "#d4466a", "#3a1a5c"], symbol: "airplane.departure"),
    ])
}
