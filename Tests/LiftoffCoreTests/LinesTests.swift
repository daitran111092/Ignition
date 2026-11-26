import Testing
import Foundation
@testable import LiftoffCore

/// Deterministic generator so the simulated mornings are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private let actionSteps: [StepID] = StepID.allCases.filter { $0 != .liftoff }

@Suite struct LinesTests {
    @Test func catalogLoadsBundledFile() throws {
        let catalog = try VoiceCatalog.bundled()
        for step in actionSteps {
            for kind in [LineKey.Kind.prompt, .confirm, .already] {
                #expect(catalog.lines(for: LineKey(step: step, kind: kind)).count >= 2, "\(step) \(kind)")
            }
        }
        #expect(catalog.lines(for: LineKey(step: nil, kind: .greeting)).count >= 2)
        #expect(catalog.lines(for: LineKey(step: nil, kind: .greetingResume)).count >= 1)
        #expect(catalog.lines(for: LineKey(step: .liftoff, kind: .liftoff)).count >= 2)
    }

    @Test func idsAreUniqueAndFileSafe() throws {
        let ids = try VoiceCatalog.bundled().lines.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil })
    }

    @Test func linesAreShortAndDateOnlyInGreeting() throws {
        for line in try VoiceCatalog.bundled().lines {
            #expect(line.text.split(separator: " ").count <= 18, "\(line.id)")
            if line.text.contains("{date}") { #expect(line.key.kind == .greeting, "\(line.id)") }
        }
    }

    @Test func neverRepeatsYesterday() throws {
        let catalog = try VoiceCatalog.bundled()
        var selector = LineSelector()
        var history = LineHistory()
        var rng = SeededGenerator(state: 42)
        var keys = actionSteps.flatMap { s in [LineKey.Kind.prompt, .confirm, .already].map { LineKey(step: s, kind: $0) } }
        keys += [LineKey(step: nil, kind: .greeting), LineKey(step: .liftoff, kind: .liftoff)]
        var previous: [LineKey: String] = [:]
        for day in 0..<50 {
            let today = String(format: "2027-01-%02d", day + 1)
            for key in keys {
                let line = selector.pick(key, catalog: catalog, history: &history, today: today, random: &rng)
                if let p = previous[key] { #expect(line.id != p, "day \(day) \(key)") }
                previous[key] = line.id
            }
        }
    }

    @Test func sameDayIsStable() throws {
        let catalog = try VoiceCatalog.bundled()
        var selector = LineSelector()
        var history = LineHistory()
        var rng = SeededGenerator(state: 7)
        let key = LineKey(step: .dac, kind: .prompt)
        let first = selector.pick(key, catalog: catalog, history: &history, today: "2026-11-18", random: &rng)
        for _ in 0..<20 {
            #expect(selector.pick(key, catalog: catalog, history: &history, today: "2026-11-18", random: &rng) == first)
        }
        #expect(history.lastUsed["dac.prompt"] == LineHistory.Used(id: first.id, day: "2026-11-18"))
    }

    @Test func greetingKeyUsesNoneInHistory() throws {
        let catalog = try VoiceCatalog.bundled()
        var selector = LineSelector()
        var history = LineHistory()
        var rng = SeededGenerator(state: 1)
        _ = selector.pick(LineKey(step: nil, kind: .greeting), catalog: catalog, history: &history, today: "2026-11-18", random: &rng)
        #expect(history.lastUsed["none.greeting"] != nil)
    }

    @Test func singleCandidateIsReusedOnNewDay() {
        let only = VoiceLine(id: "a", key: LineKey(step: nil, kind: .greetingResume), text: "Welcome back, Commander.")
        let catalog = VoiceCatalog(lines: [only])
        var selector = LineSelector()
        var history = LineHistory()
        var rng = SeededGenerator(state: 3)
        let a = selector.pick(only.key, catalog: catalog, history: &history, today: "2026-11-18", random: &rng)
        let b = selector.pick(only.key, catalog: catalog, history: &history, today: "2026-11-19", random: &rng)
        #expect(a == only && b == only)
    }

    @Test func staleSameDayIdRepicksValidLine() throws {
        let catalog = try VoiceCatalog.bundled()
        let key = LineKey(step: .dac, kind: .prompt)
        var history = LineHistory()
        history.lastUsed["dac.prompt"] = .init(id: "retired-line", day: "2026-11-18")
        var selector = LineSelector()
        var rng = SeededGenerator(state: 5)
        let line = selector.pick(key, catalog: catalog, history: &history, today: "2026-11-18", random: &rng)
        #expect(catalog.lines(for: key).contains(line))
        #expect(history.lastUsed["dac.prompt"]?.id == line.id)
    }

    @Test func emptyCandidatesYieldMissingPlaceholder() {
        var selector = LineSelector()
        var history = LineHistory()
        var rng = SeededGenerator(state: 9)
        let key = LineKey(step: .teams, kind: .prompt)
        let line = selector.pick(key, catalog: VoiceCatalog(lines: []), history: &history, today: "2026-11-18", random: &rng)
        #expect(line.id == "missing" && line.key == key)
        #expect(history.lastUsed.isEmpty)
    }

    @Test func historyStoreRoundTrips() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liftoff-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LineHistoryStore(directory: dir)
        #expect(store.load() == LineHistory())
        var h = LineHistory()
        h.lastUsed["dac.prompt"] = .init(id: "dac-prompt-1", day: "2026-11-18")
        try store.save(h)
        #expect(store.load() == h)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("history.json").path))
    }

    @Test func renderDateSpellsOrdinals() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
        }
        #expect(renderDate(date(2026, 11, 18), calendar: cal) == "Wednesday, November eighteenth")
        #expect(renderDate(date(2026, 11, 1), calendar: cal) == "Sunday, November first")
        #expect(renderDate(date(2026, 11, 22), calendar: cal) == "Sunday, November twenty-second")
        #expect(renderDate(date(2026, 12, 30), calendar: cal) == "Wednesday, December thirtieth")
        #expect(renderDate(date(2026, 12, 31), calendar: cal) == "Thursday, December thirty-first")
    }
}

@Suite struct InstalledCatalogTests {
    @Test func copiesTheBundledCatalogOnceThenReadsTheCopy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liftoff-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try VoiceCatalog.installed(in: dir)
        #expect(first.lines.count == (try VoiceCatalog.bundled()).lines.count)

        let edited = VoiceCatalog(lines: [VoiceLine(id: "x", key: LineKey(step: nil, kind: .greeting), text: "Hi")])
        try JSONEncoder().encode(edited).write(to: dir.appendingPathComponent("voices.json"))
        #expect(try VoiceCatalog.installed(in: dir).lines == edited.lines)
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liftoff-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let oldShipped = VoiceCatalog(lines: [VoiceLine(id: "old", key: LineKey(step: nil, kind: .greeting), text: "Old")])

    @Test func anUneditedCopyIsUpgradedWhenTheBundleChanges() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try JSONEncoder().encode(oldShipped)
        try old.write(to: dir.appendingPathComponent("voices.json"))
        try old.write(to: dir.appendingPathComponent("voices.bundled.json"))
        #expect(try VoiceCatalog.installed(in: dir).lines == VoiceCatalog.bundled().lines)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("voices.json.bak").path))
    }

    @Test func anEditedCopyIsKeptWhenTheBundleChanges() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try JSONEncoder().encode(oldShipped).write(to: dir.appendingPathComponent("voices.bundled.json"))
        let edited = VoiceCatalog(lines: [VoiceLine(id: "mine", key: LineKey(step: nil, kind: .greeting), text: "Mine")])
        try JSONEncoder().encode(edited).write(to: dir.appendingPathComponent("voices.json"))
        #expect(try VoiceCatalog.installed(in: dir).lines == edited.lines)
        #expect(try VoiceCatalog.installed(in: dir).lines == edited.lines)  // and stays kept
    }

    @Test func aCopyFromBeforeVersioningIsBackedUpAndReplaced() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try JSONEncoder().encode(oldShipped)
        try old.write(to: dir.appendingPathComponent("voices.json"))
        #expect(try VoiceCatalog.installed(in: dir).lines == VoiceCatalog.bundled().lines)
        #expect(try Data(contentsOf: dir.appendingPathComponent("voices.json.bak")) == old)
    }
}
