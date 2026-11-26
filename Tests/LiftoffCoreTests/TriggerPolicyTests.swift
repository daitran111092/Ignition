import Testing
import Foundation
@testable import LiftoffCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    return c
}()

private func date(_ d: Int, _ h: Int, _ m: Int) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
}

private let window = TriggerWindow()

@Suite struct TriggerPolicyTests {
    @Test func morningNoLedgerStartsFresh() {
        #expect(decideTrigger(now: date(18, 8, 47), calendar: cal, window: window, ledger: nil) == .start(resumeAt: nil))
    }

    @Test func windowBoundariesAreInclusive() {
        #expect(decideTrigger(now: date(18, 7, 59), calendar: cal, window: window, ledger: nil) == .stayQuiet)
        #expect(decideTrigger(now: date(18, 8, 0), calendar: cal, window: window, ledger: nil) == .start(resumeAt: nil))
        #expect(decideTrigger(now: date(18, 10, 30), calendar: cal, window: window, ledger: nil) == .start(resumeAt: nil))
        #expect(decideTrigger(now: date(18, 10, 31), calendar: cal, window: window, ledger: nil) == .stayQuiet)
    }

    @Test func weekendStaysQuiet() {
        #expect(decideTrigger(now: date(21, 9, 0), calendar: cal, window: window, ledger: nil) == .stayQuiet)
    }

    @Test func doneTodayStaysQuiet() {
        let now = date(18, 9, 0)
        for status in [DayLedger.Status.completed, .skipped] {
            let ledger = DayLedger(day: dayKey(now, calendar: cal), status: status)
            #expect(decideTrigger(now: now, calendar: cal, window: window, ledger: ledger) == .stayQuiet)
        }
    }

    @Test func inProgressTodayResumes() {
        let now = date(18, 9, 0)
        let ledger = DayLedger(day: dayKey(now, calendar: cal), status: .inProgress(stepIndex: 4))
        #expect(decideTrigger(now: now, calendar: cal, window: window, ledger: ledger) == .start(resumeAt: 4))
    }

    @Test func yesterdayLedgerIsIgnored() {
        let ledger = DayLedger(day: dayKey(date(17, 9, 0), calendar: cal), status: .inProgress(stepIndex: 4))
        #expect(decideTrigger(now: date(18, 9, 0), calendar: cal, window: window, ledger: ledger) == .start(resumeAt: nil))
    }

    @Test func dayKeyFormat() {
        #expect(dayKey(date(18, 23, 59), calendar: cal) == "2026-11-18")
    }

    @Test func ledgerStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liftoff-ledger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LedgerStore(directory: dir)
        #expect(store.load() == nil)
        let ledger = DayLedger(day: "2026-11-18", status: .inProgress(stepIndex: 3))
        try store.save(ledger)
        #expect(store.load() == ledger)
    }
}
