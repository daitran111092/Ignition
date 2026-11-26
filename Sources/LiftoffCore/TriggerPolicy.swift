import Foundation

public struct DayLedger: Codable, Equatable, Sendable {
    public enum Status: Codable, Equatable, Sendable {
        case inProgress(stepIndex: Int)
        case completed
        case skipped
    }

    /// Local day, `yyyy-MM-dd`.
    public var day: String
    public var status: Status

    public init(day: String, status: Status) {
        self.day = day
        self.status = status
    }
}

public enum TriggerDecision: Equatable, Sendable {
    /// `resumeAt == nil` means a fresh run with the greeting.
    case start(resumeAt: Int?)
    case stayQuiet
}

public func dayKey(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// The window is inclusive at both ends (08:00 and 10:30 start; 07:59 and 10:31 do not).
public func decideTrigger(now: Date, calendar: Calendar, window: TriggerWindow, ledger: DayLedger?) -> TriggerDecision {
    guard window.weekdays.contains(calendar.component(.weekday, from: now)) else { return .stayQuiet }
    let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    guard minute >= window.startMinute, minute <= window.endMinute else { return .stayQuiet }

    guard let ledger, ledger.day == dayKey(now, calendar: calendar) else { return .start(resumeAt: nil) }
    switch ledger.status {
    case .completed, .skipped: return .stayQuiet
    case .inProgress(let stepIndex): return .start(resumeAt: stepIndex)
    }
}

public struct LedgerStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent("ledger.json") }

    /// Returns nil when the file is missing or corrupt.
    public func load() -> DayLedger? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DayLedger.self, from: data)
    }

    public func save(_ ledger: DayLedger) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: fileURL, options: .atomic)
    }
}
