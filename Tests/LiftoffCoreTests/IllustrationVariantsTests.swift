import Testing
import Foundation
@testable import LiftoffCore

@Suite struct IllustrationVariantsTests {
    @Test func fileNames() {
        #expect(IllustrationVariants.fileName(for: .dac, variant: 1) == "dac.png")
        #expect(IllustrationVariants.fileName(for: .dac, variant: 3) == "dac-3.png")
        #expect(IllustrationVariants.fileName(for: .agentFactory, variant: 2) == "agentFactory-2.png")
    }

    @Test func countsContiguousVariants() {
        let listing = ["dac.png", "dac-2.png", "dac-3.png", "dock.png", "dac-5.png", "music-2.png"]
        #expect(IllustrationVariants.count(for: .dac, in: listing) == 3)   // stops at missing dac-4
        #expect(IllustrationVariants.count(for: .dock, in: listing) == 1)
        #expect(IllustrationVariants.count(for: .music, in: listing) == 0) // no music.png
        #expect(IllustrationVariants.count(for: .teams, in: listing) == 0)
    }

    @Test func ignoresLookalikeNames() {
        let listing = ["dac.png", "dac-02.png", "dac-2.jpg", "dac2.png", "Dac-2.png"]
        #expect(IllustrationVariants.count(for: .dac, in: listing) == 1)
    }

    @Test func clampsIntoRange() {
        #expect(IllustrationVariants.clamp(0, count: 3) == 1)
        #expect(IllustrationVariants.clamp(-4, count: 3) == 1)
        #expect(IllustrationVariants.clamp(2, count: 3) == 2)
        #expect(IllustrationVariants.clamp(7, count: 3) == 3)
        #expect(IllustrationVariants.clamp(2, count: 0) == 1)
    }

    @Test func nextAndPreviousWrap() {
        #expect(IllustrationVariants.next(after: 1, count: 3) == 2)
        #expect(IllustrationVariants.next(after: 3, count: 3) == 1)
        #expect(IllustrationVariants.next(after: 9, count: 3) == 1)  // stale selection clamps to 3 first
        #expect(IllustrationVariants.previous(before: 1, count: 3) == 3)
        #expect(IllustrationVariants.previous(before: 3, count: 3) == 2)
        #expect(IllustrationVariants.next(after: 1, count: 1) == 1)
        #expect(IllustrationVariants.previous(before: 1, count: 0) == 1)
    }

    @Test func configPersistsChosenVariantsAsJSONObject() throws {
        var config = LiftoffConfig.default
        #expect(config.illustrationVariants.isEmpty)
        config.illustrationVariants[.dac] = 3
        let data = try JSONEncoder().encode(config)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["illustrationVariants"] as? [String: Int]) == ["dac": 3])
        #expect(try JSONDecoder().decode(LiftoffConfig.self, from: data) == config)
    }

    @Test func missingVariantsKeyDecodesEmpty() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(LiftoffConfig.default)) as? [String: Any])
        json["illustrationVariants"] = nil
        let config = try JSONDecoder().decode(LiftoffConfig.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(config.illustrationVariants.isEmpty)
    }
}
