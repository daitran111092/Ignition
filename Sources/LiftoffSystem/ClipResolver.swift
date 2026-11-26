import Foundation
import LiftoffCore

/// Where a voice line's audio comes from.
public enum ClipSource: Equatable, Sendable {
    /// A pre-generated clip (ElevenLabs) on disk; `fallbackText` is spoken by the system voice
    /// if the file cannot be loaded or played.
    case file(URL, fallbackText: String)
    /// Fallback: speak this text with the system voice.
    case synthesize(String)
}

/// Lines without `{date}` use `voices/<id>.mp3` when it exists. Lines with `{date}` use today's
/// generated greeting when available; otherwise the rendered text is synthesized
/// (a per-id clip would name the wrong day, so it is never used for them).
public func resolveClip(_ line: VoiceLine, voicesDir: URL, dateText: String, dailyGreeting: URL?) -> ClipSource {
    let text = line.text.replacingOccurrences(of: "{date}", with: dateText)
    if line.text.contains("{date}") {
        if let dailyGreeting { return .file(dailyGreeting, fallbackText: text) }
        return .synthesize(text)
    }
    let clip = voicesDir.appendingPathComponent("\(line.id).mp3")
    if FileManager.default.fileExists(atPath: clip.path) { return .file(clip, fallbackText: text) }
    return .synthesize(text)
}

/// `<dataDir>/voices/greeting-<day>-<lineID>.mp3`: the dated greeting for `day`, generated the day
/// before (or at trigger time). The line id makes sure the clip matches the greeting variant picked.
public func dailyGreetingURL(dataDir: URL, day: String, lineID: String) -> URL {
    dataDir.appendingPathComponent("voices", isDirectory: true).appendingPathComponent("greeting-\(day)-\(lineID).mp3")
}

/// Names among `names` that are dated greetings (`greeting-yyyy-MM-dd….mp3`) for a day more than two
/// days before `today`. Per-line clips such as `greeting-1.mp3` never match.
public func staleDailyGreetings(_ names: [String], today: Date, calendar: Calendar) -> [String] {
    guard let cutoffDate = calendar.date(byAdding: .day, value: -2, to: today) else { return [] }
    let cutoff = dayKey(cutoffDate, calendar: calendar)
    return names.filter { name in
        guard name.hasPrefix("greeting-"), name.hasSuffix(".mp3") else { return false }
        let day = String(name.dropFirst("greeting-".count).prefix(10))
        guard day.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return false }
        return day < cutoff
    }
}
