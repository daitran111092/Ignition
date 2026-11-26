import AppKit
import LiftoffCore

/// Launches (or brings forward) the app an app step waits for.
@MainActor
public enum AppLauncher {
    /// The app's bundle: by bundle id first, then by name in ~/Applications, /Applications,
    /// /System/Applications (Safari web apps such as Agent Factory have no bundle id).
    public static func locate(_ target: AppLaunchTarget) -> URL? {
        let workspace = NSWorkspace.shared
        for id in target.bundleIDs {
            if let url = workspace.urlForApplication(withBundleIdentifier: id) { return url }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return target.candidatePaths(home: home).first { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Opens the app activated (it comes to the front). Returns false when it can't be found.
    @discardableResult
    public static func open(_ target: AppLaunchTarget) -> Bool {
        guard let url = locate(target) else {
            log("\(target.displayName): app not found")
            return false
        }
        // macOS 14+ cooperative activation: hand our activation over to the app we open.
        if let id = Bundle(url: url)?.bundleIdentifier {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: id)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { log("\(target.displayName): open failed: \(error.localizedDescription)") }
        }
        return true
    }

    private nonisolated static func log(_ message: String) {
        FileHandle.standardError.write(Data("[AppLauncher] \(message)\n".utf8))
    }
}
