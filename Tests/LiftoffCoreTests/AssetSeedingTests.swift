import Testing
import Foundation
@testable import LiftoffCore

@Suite struct AssetSeedingTests {
    @Test func plansOnlyMissingClips() {
        #expect(assetSeedPlan(bundled: ["a.mp3", "b.mp3", "c.mp3"], existing: ["b.mp3", "x.mp3"]) == ["a.mp3", "c.mp3"])
        #expect(assetSeedPlan(bundled: ["a.mp3"], existing: ["a.mp3"]).isEmpty)
    }

    @Test func musicSeededOnlyWithoutTracks() {
        #expect(shouldSeedMusic(existing: []))
        #expect(shouldSeedMusic(existing: ["CREDITS.md", ".DS_Store"]))
        #expect(!shouldSeedMusic(existing: ["Mine.M4A"]))
        #expect(!shouldSeedMusic(existing: ["x.mp3"]))
    }

    @Test func seedsWithoutOverwriting() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("seed-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        let res = tmp.appendingPathComponent("res"), data = tmp.appendingPathComponent("data")
        let assets = res.appendingPathComponent("DefaultAssets")
        try fm.createDirectory(at: assets.appendingPathComponent("music"), withIntermediateDirectories: true)
        try fm.createDirectory(at: assets.appendingPathComponent("voices"), withIntermediateDirectories: true)
        try fm.createDirectory(at: data.appendingPathComponent("voices"), withIntermediateDirectories: true)
        try Data("m".utf8).write(to: assets.appendingPathComponent("music/t.mp3"))
        try Data("c".utf8).write(to: assets.appendingPathComponent("CREDITS.md"))
        try Data("new".utf8).write(to: assets.appendingPathComponent("voices/a.mp3"))
        try Data("new".utf8).write(to: assets.appendingPathComponent("voices/b.mp3"))
        try Data("mine".utf8).write(to: data.appendingPathComponent("voices/a.mp3"))

        seedDefaultAssets(from: res, into: data)
        #expect(try String(contentsOf: data.appendingPathComponent("voices/a.mp3"), encoding: .utf8) == "mine")
        #expect(fm.fileExists(atPath: data.appendingPathComponent("voices/b.mp3").path))
        #expect(fm.fileExists(atPath: data.appendingPathComponent("music/t.mp3").path))
        #expect(fm.fileExists(atPath: data.appendingPathComponent("music/CREDITS.md").path))
    }
}
