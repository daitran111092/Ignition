import Foundation

/// Bundled clips (by file name) that aren't in the data dir yet. Existing files are never overwritten.
public func assetSeedPlan(bundled: [String], existing: [String]) -> [String] {
    let have = Set(existing)
    return bundled.filter { !have.contains($0) }
}

/// Whether the bundled music should be copied: only when the data dir has no .mp3/.m4a yet.
public func shouldSeedMusic(existing: [String]) -> Bool {
    !existing.contains { name in
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "mp3" || ext == "m4a"
    }
}

/// Copies the app's bundled default assets (`<bundleResources>/DefaultAssets`) into the data dir.
/// Never overwrites; failures are reported through `log` and never thrown.
public func seedDefaultAssets(from bundleResources: URL?, into dataDir: URL, log: (String) -> Void = { _ in }) {
    guard let root = bundleResources?.appendingPathComponent("DefaultAssets", isDirectory: true) else { return }
    let fm = FileManager.default
    func names(_ dir: URL) -> [String] { (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] }
    func copy(_ name: String, from src: URL, to dst: URL) {
        do {
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            try fm.copyItem(at: src.appendingPathComponent(name), to: dst.appendingPathComponent(name))
        } catch { log("[Seed] \(name): \(error)") }
    }

    let music = (src: root.appendingPathComponent("music"), dst: dataDir.appendingPathComponent("music"))
    let bundledMusic = names(music.src).filter { !$0.hasPrefix(".") }
    if !bundledMusic.isEmpty, shouldSeedMusic(existing: names(music.dst)) {
        for n in bundledMusic { copy(n, from: music.src, to: music.dst) }
        let credits = root.appendingPathComponent("CREDITS.md")
        if fm.fileExists(atPath: credits.path), !fm.fileExists(atPath: music.dst.appendingPathComponent("CREDITS.md").path) {
            copy("CREDITS.md", from: root, to: music.dst)
        }
    }

    let voices = (src: root.appendingPathComponent("voices"), dst: dataDir.appendingPathComponent("voices"))
    let clips = assetSeedPlan(bundled: names(voices.src).filter { $0.hasSuffix(".mp3") }, existing: names(voices.dst))
    for n in clips { copy(n, from: voices.src, to: voices.dst) }
}
