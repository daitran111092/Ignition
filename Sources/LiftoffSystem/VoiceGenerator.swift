import Foundation
import LiftoffCore

/// Generates the ElevenLabs clips for the voice catalog (shared by `liftoff-voices generate` and
/// Settings → "Regenerate voices").
public enum VoiceGenerator {
    public struct Summary: Sendable {
        public var generated = 0, skipped = 0, failed = 0
    }

    /// Writes `voices/<id>.mp3` for every line without `{date}` (dated lines are generated per day).
    /// Existing clips are kept unless `force`. `progress` gets one line per clip.
    public static func generate(catalog: VoiceCatalog, voicesDir: URL, client: ElevenLabsClient, force: Bool,
                                progress: @Sendable (String) async -> Void) async throws -> Summary {
        try FileManager.default.createDirectory(at: voicesDir, withIntermediateDirectories: true)
        let lines = catalog.lines.filter { !$0.text.contains("{date}") }
        var summary = Summary()
        for (index, line) in lines.enumerated() {
            let target = voicesDir.appendingPathComponent("\(line.id).mp3")
            let prefix = "[\(index + 1)/\(lines.count)] \(line.id)"
            if !force, FileManager.default.fileExists(atPath: target.path) {
                await progress("\(prefix): exists, skipped")
                summary.skipped += 1
                continue
            }
            do {
                let audio = try await client.synthesize(line.text)
                try audio.write(to: target, options: .atomic)
                await progress("\(prefix): ok (\(audio.count / 1024) KB)")
                summary.generated += 1
            } catch {
                await progress("\(prefix): FAILED \(error)")
                summary.failed += 1
            }
        }
        return summary
    }
}
