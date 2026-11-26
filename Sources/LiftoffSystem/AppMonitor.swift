import AppKit
import LiftoffCore

/// Reports app launches/terminations (as changes) and activations; lists running apps.
@MainActor
final class AppMonitor {
    private let onChange: @MainActor () -> Void
    private let onActivate: @MainActor (RunningApp) -> Void
    private var tokens: [NSObjectProtocol] = []

    init(onChange: @escaping @MainActor () -> Void, onActivate: @escaping @MainActor (RunningApp) -> Void) {
        self.onChange = onChange
        self.onActivate = onActivate
    }

    func start() {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange() }
            })
        }
        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let runningApp = app.map(Self.runningApp)
            MainActor.assumeIsolated {
                if let runningApp { self?.onActivate(runningApp) }
            }
        })
    }

    func runningApps() -> Set<RunningApp> {
        Set(NSWorkspace.shared.runningApplications.map(Self.runningApp))
    }

    func frontmostApp() -> RunningApp? {
        NSWorkspace.shared.frontmostApplication.map(Self.runningApp)
    }

    private nonisolated static func runningApp(_ app: NSRunningApplication) -> RunningApp {
        RunningApp(bundleID: app.bundleIdentifier,
                   name: app.localizedName ?? app.executableURL?.lastPathComponent ?? "")
    }
}
