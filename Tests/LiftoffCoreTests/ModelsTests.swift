import Testing
import Foundation
@testable import LiftoffCore

@Suite struct ModelsTests {
    @Test func defaultConfigHasTwelveStepsInOrder() {
        #expect(LiftoffConfig.default.steps.map(\.id) == StepID.allCases)
        #expect(StepID.allCases == [.water, .laptopStand, .cables, .dock, .keyboard, .mouse, .dac,
                                    .agentFactory, .headphones, .music, .teams, .liftoff])
    }

    @Test func defaultGradientsMatchSpec() {
        let steps = Dictionary(uniqueKeysWithValues: LiftoffConfig.default.steps.map { ($0.id, $0) })
        #expect(steps[.dac]?.gradient == ["#b3203a", "#4a0a22"])
        #expect(steps[.liftoff]?.gradient == ["#ffb35c", "#d4466a", "#3a1a5c"])
    }

    @Test func defaultRules() {
        let steps = Dictionary(uniqueKeysWithValues: LiftoffConfig.default.steps.map { ($0.id, $0.rule) })
        #expect(steps[.water] == .manual)
        #expect(steps[.headphones] == .manual)
        #expect(steps[.laptopStand] == .manual)
        #expect(steps[.dac] == .devices(.audioOutput, hint: "FiiO"))
        #expect(steps[.keyboard] == .devices(.hid, hint: "Reclusa"))
        #expect(steps[.mouse] == .devices(.hid, hint: "MX Master"))
        guard case .appActivated(let teams)? = steps[.teams] else {
            Issue.record("teams rule should be appActivated"); return
        }
        #expect(teams.bundleIDs.contains("com.microsoft.teams2"))
        #expect(steps[.agentFactory] == .appRunning(AppMatch(bundleIDs: ["dev.agentfactory.desktop"], names: ["Agent Factory"])))
        #expect(steps[.music] == .musicPlaying)
        #expect(steps[.liftoff] == .final)
    }

    @Test func signatureMatchesByVendorProductElseName() {
        let a = DeviceSignature(kind: .usb, name: "Hub A", vendorID: 1, productID: 2)
        let b = DeviceSignature(kind: .usb, name: "Hub B", vendorID: 1, productID: 2)
        #expect(a.matches(b))
        let c = DeviceSignature(kind: .audioOutput, name: "FiiO K7", vendorID: nil, productID: nil)
        let d = DeviceSignature(kind: .audioOutput, name: "fiio k7", vendorID: nil, productID: nil)
        #expect(c.matches(d))
        let e = DeviceSignature(kind: .usb, name: "FiiO K7", vendorID: nil, productID: nil)
        #expect(!c.matches(e))
    }

    @Test func configRoundTripsThroughStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liftoff-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        var config = LiftoffConfig.default
        config.musicVolume = 0.4
        config.learned[.dock] = [DeviceSignature(kind: .usb, name: "Dock", vendorID: 5, productID: 6)]
        try store.save(config)
        #expect(store.load() == config)

        try Data("not json".utf8).write(to: dir.appendingPathComponent("config.json"))
        #expect(store.load() == LiftoffConfig.default)
    }

    @Test func learnedEncodesAsJSONObjectKeyedByStepName() throws {
        var config = LiftoffConfig.default
        config.learned[.dac] = [DeviceSignature(kind: .audioOutput, name: "FiiO K7")]
        let data = try JSONEncoder().encode(config)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let learned = try #require(json["learned"] as? [String: Any])
        #expect(learned["dac"] != nil)
        #expect(try JSONDecoder().decode(LiftoffConfig.self, from: data) == config)
    }
}

@Suite struct ConfigResilienceTests {
    @Test func missingKeysFallBackToDefaults() throws {
        let json = #"{"displayMode": "fullscreen", "window": {"startMinute": 450}}"#
        let config = try JSONDecoder().decode(LiftoffConfig.self, from: Data(json.utf8))
        #expect(config.displayMode == .fullscreen)
        #expect(config.window.startMinute == 450)
        #expect(config.window.endMinute == 630)
        #expect(config.window.weekdays == [2, 3, 4, 5, 6])
        #expect(config.steps == LiftoffConfig.default.steps)
        #expect(config.learned.isEmpty)
        #expect(config.musicVolume == 0.6)
        #expect(config.voiceEnabled)
        #expect(config.voiceRoomEffect)
        #expect(config.elevenLabsVoiceID == nil)
    }

    @Test func undecodableFileIsBackedUpBeforeDefaultsAreUsed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liftoff-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bad = Data(#"{"displayMode": "sideways"}"#.utf8)
        try bad.write(to: dir.appendingPathComponent("config.json"))
        #expect(ConfigStore(directory: dir).load() == .default)
        #expect(try Data(contentsOf: dir.appendingPathComponent("config.json.bak")) == bad)
    }

    @Test func missingFileMakesNoBackup() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liftoff-test-\(UUID().uuidString)")
        #expect(ConfigStore(directory: dir).load() == .default)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json.bak").path))
    }
}
