import Testing
import Foundation
import LiftoffCore
@testable import LiftoffSystem

struct ClipResolverTests {
    private func makeVoicesDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("liftoff-clips-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let dateText = "Wednesday, November eighteenth"
    private let plain = VoiceLine(id: "dac-prompt-1", key: LineKey(step: .dac, kind: .prompt),
                                  text: "Now, power up your FiiO K7.")
    private let greeting = VoiceLine(id: "greeting-1", key: LineKey(step: nil, kind: .greeting),
                                     text: "Good morning, Commander. Today is {date}.")

    @Test func existingClipResolvesToFile() throws {
        let dir = try makeVoicesDir()
        let clip = dir.appendingPathComponent("dac-prompt-1.mp3")
        try Data([0x49, 0x44, 0x33]).write(to: clip)
        let source = resolveClip(plain, voicesDir: dir, dateText: dateText, dailyGreeting: nil)
        #expect(source == .file(clip, fallbackText: "Now, power up your FiiO K7."))
    }

    @Test func missingClipFallsBackToSynthesis() throws {
        let dir = try makeVoicesDir()
        let source = resolveClip(plain, voicesDir: dir, dateText: dateText, dailyGreeting: nil)
        #expect(source == .synthesize("Now, power up your FiiO K7."))
    }

    @Test func dateLineUsesDailyGreetingWhenPresent() throws {
        let dir = try makeVoicesDir()
        let daily = dir.appendingPathComponent("greeting-2026-11-18.mp3")
        let source = resolveClip(greeting, voicesDir: dir, dateText: dateText, dailyGreeting: daily)
        #expect(source == .file(daily, fallbackText: "Good morning, Commander. Today is Wednesday, November eighteenth."))
    }

    @Test func fileClipCarriesRenderedTextForFallback() throws {
        let dir = try makeVoicesDir()
        let daily = dir.appendingPathComponent("greeting-2026-11-18.mp3")
        let source = resolveClip(greeting, voicesDir: dir, dateText: dateText, dailyGreeting: daily)
        guard case .file(let url, let fallbackText) = source else {
            Issue.record("expected .file, got \(source)")
            return
        }
        #expect(url == daily)
        #expect(fallbackText == "Good morning, Commander. Today is Wednesday, November eighteenth.")
        #expect(!fallbackText.contains("{date}"))
    }

    @Test func dateLineWithoutDailyGreetingSynthesizesRenderedDate() throws {
        let dir = try makeVoicesDir()
        // Even a stale per-id clip must not be used for a date line: it would say the wrong day.
        try Data([0x49]).write(to: dir.appendingPathComponent("greeting-1.mp3"))
        let source = resolveClip(greeting, voicesDir: dir, dateText: dateText, dailyGreeting: nil)
        #expect(source == .synthesize("Good morning, Commander. Today is Wednesday, November eighteenth."))
        if case .synthesize(let text) = source { #expect(!text.contains("{date}")) }
    }

    @Test func dailyGreetingURLIsDatedFileInVoicesDir() {
        let dataDir = URL(fileURLWithPath: "/tmp/liftoff-data", isDirectory: true)
        let url = dailyGreetingURL(dataDir: dataDir, day: "2026-11-18", lineID: "greeting-2")
        // The line id keeps a clip pre-generated for one greeting variant from playing under another's caption.
        #expect(url.path == "/tmp/liftoff-data/voices/greeting-2026-11-18-greeting-2.mp3")
    }

    @Test func dailyGreetingsOlderThanTwoDaysAreStale() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))!
        let names = [
            "greeting-2026-11-15-greeting-1.mp3",  // 3 days old
            "greeting-2026-11-15.mp3",             // 3 days old, earlier naming
            "greeting-2026-10-30-greeting-3.mp3",
            "greeting-2026-11-16-greeting-2.mp3",  // 2 days old: kept
            "greeting-2026-11-18-greeting-1.mp3",
            "greeting-2026-11-19-greeting-2.mp3",  // tomorrow's, pre-generated
            "greeting-1.mp3", "greeting-resume-2.mp3", "dac-prompt-1.mp3",  // per-line clips: never touched
        ]
        #expect(staleDailyGreetings(names, today: today, calendar: cal).sorted() == [
            "greeting-2026-10-30-greeting-3.mp3", "greeting-2026-11-15-greeting-1.mp3", "greeting-2026-11-15.mp3",
        ])
    }
}
