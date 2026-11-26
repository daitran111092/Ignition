import Foundation

public struct VoiceLine: Codable, Equatable, Sendable {
    public var id: String
    public var key: LineKey
    /// May contain `{date}` (greeting only).
    public var text: String

    public init(id: String, key: LineKey, text: String) {
        self.id = id
        self.key = key
        self.text = text
    }
}

public struct VoiceCatalog: Codable, Sendable {
    public var lines: [VoiceLine]

    public init(lines: [VoiceLine]) {
        self.lines = lines
    }

    public func lines(for key: LineKey) -> [VoiceLine] {
        lines.filter { $0.key == key }
    }

    public static func load(from url: URL) throws -> VoiceCatalog {
        try JSONDecoder().decode(VoiceCatalog.self, from: Data(contentsOf: url))
    }

    /// The catalog shipped with the app.
    public static func bundled() throws -> VoiceCatalog {
        guard let url = bundledURL() else { throw CocoaError(.fileNoSuchFile) }
        return try load(from: url)
    }

    /// `<dataDir>/voices.json`, copied from the bundled catalog the first time so lines can be edited
    /// without rebuilding. Falls back to the bundled catalog if the copy can't be read.
    ///
    /// `voices.bundled.json` remembers the bundled catalog the copy was made from. When the app ships
    /// a new catalog, an unedited copy is replaced by it; an edited copy is left alone. A copy made
    /// before that file existed is replaced if it differs from the bundle, after saving it to `voices.json.bak`.
    public static func installed(in dataDir: URL) throws -> VoiceCatalog {
        let copy = dataDir.appendingPathComponent("voices.json")
        if let source = bundledURL(), let shipped = try? Data(contentsOf: source) {
            refreshCopy(copy, pristine: dataDir.appendingPathComponent("voices.bundled.json"),
                        backup: dataDir.appendingPathComponent("voices.json.bak"), shipped: shipped)
        }
        if let catalog = try? load(from: copy) { return catalog }
        return try bundled()
    }

    private static func refreshCopy(_ copy: URL, pristine: URL, backup: URL, shipped: Data) {
        let fm = FileManager.default
        try? fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let current = try? Data(contentsOf: copy)
        let base = try? Data(contentsOf: pristine)
        if base == shipped, current != nil { return }  // up to date (edited or not)
        switch (current, base) {
        case (nil, _):
            break  // first install
        case (let current?, let base?) where current != base:
            try? shipped.write(to: pristine, options: .atomic)  // edited: keep the user's lines
            return
        case (let current?, nil) where current != shipped:
            try? current.write(to: backup, options: .atomic)  // copy from before versioning
        default:
            break
        }
        try? shipped.write(to: copy, options: .atomic)
        try? shipped.write(to: pristine, options: .atomic)
    }

    /// `voices.json` inside the app (`Contents/Resources`, loose or in the SwiftPM resource bundle),
    /// else SwiftPM's `Bundle.module`. The generated `Bundle.module` only looks at the .app root
    /// (where codesign forbids extra files) and the absolute build path, so it is the last resort
    /// (tests, `swift run`, the liftoff-voices CLI).
    public static func bundledURL() -> URL? {
        if let url = Bundle.main.url(forResource: "voices", withExtension: "json") { return url }
        if let url = Bundle.main.url(forResource: "Liftoff_LiftoffCore", withExtension: "bundle"),
           let resource = Bundle(url: url)?.url(forResource: "voices", withExtension: "json") {
            return resource
        }
        return Bundle.module.url(forResource: "voices", withExtension: "json")
    }
}

public struct LineHistory: Codable, Equatable, Sendable {
    public struct Used: Codable, Equatable, Sendable {
        public var id: String
        public var day: String

        public init(id: String, day: String) {
            self.id = id
            self.day = day
        }
    }

    /// Keyed by `"<step or none>.<kind>"`, e.g. `"dac.prompt"`, `"none.greeting"`.
    public var lastUsed: [String: Used] = [:]

    public init() {}

    static func historyKey(_ key: LineKey) -> String {
        "\(key.step?.rawValue ?? "none").\(key.kind.rawValue)"
    }
}

public struct LineHistoryStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent("history.json") }

    /// Returns an empty history when the file is missing or corrupt.
    public func load() -> LineHistory {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? JSONDecoder().decode(LineHistory.self, from: data) else { return LineHistory() }
        return history
    }

    public func save(_ history: LineHistory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }
}

public struct LineSelector: Sendable {
    public init() {}

    /// Same key twice on one day returns the same line. On a new day it picks randomly,
    /// avoiding the previous pick when there are at least two candidates.
    /// An empty candidate set yields a silent placeholder (id "missing") rather than crashing.
    public mutating func pick(
        _ key: LineKey,
        catalog: VoiceCatalog,
        history: inout LineHistory,
        today: String,
        random: inout some RandomNumberGenerator
    ) -> VoiceLine {
        let candidates = catalog.lines(for: key)
        let hk = LineHistory.historyKey(key)
        let last = history.lastUsed[hk]
        if let last, last.day == today, let same = candidates.first(where: { $0.id == last.id }) {
            return same
        }
        let pool = candidates.count >= 2 ? candidates.filter { $0.id != last?.id } : candidates
        guard let chosen = pool.randomElement(using: &random) else {
            return VoiceLine(id: "missing", key: key, text: "")
        }
        history.lastUsed[hk] = LineHistory.Used(id: chosen.id, day: today)
        return chosen
    }
}

private let dayWords = ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth",
    "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth",
    "eighteenth", "nineteenth", "twentieth", "twenty-first", "twenty-second", "twenty-third", "twenty-fourth",
    "twenty-fifth", "twenty-sixth", "twenty-seventh", "twenty-eighth", "twenty-ninth", "thirtieth", "thirty-first"]

/// "Wednesday, November eighteenth": ordinal spelled out so the voice reads it naturally.
public func renderDate(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "EEEE, MMMM"
    let day = calendar.component(.day, from: date)
    return "\(formatter.string(from: date)) \(dayWords[min(max(day, 1), 31)])"
}
