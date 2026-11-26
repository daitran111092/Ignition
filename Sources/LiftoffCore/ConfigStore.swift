import Foundation

public struct ConfigStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Liftoff", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { directory.appendingPathComponent("config.json") }

    /// Whether config.json exists (false on first launch).
    public var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// Returns the default config when the file is missing or corrupt. A corrupt file is first
    /// copied to `config.json.bak` so hand edits aren't lost when defaults are saved over it.
    public func load() -> LiftoffConfig {
        guard let data = try? Data(contentsOf: fileURL) else { return .default }
        do {
            return try JSONDecoder().decode(LiftoffConfig.self, from: data)
        } catch {
            try? data.write(to: directory.appendingPathComponent("config.json.bak"), options: .atomic)
            return .default
        }
    }

    public func save(_ config: LiftoffConfig) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }
}
