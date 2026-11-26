import AppKit
import Observation
import SwiftUI
import LiftoffCore
import LiftoffSystem

/// The in-memory config that Settings, the menu and the Learn wizard edit; every change is saved.
@MainActor @Observable
final class AppSettings {
    var config: LiftoffConfig {
        didSet {
            guard config != oldValue else { return }
            do { try store.save(config) } catch { FileHandle.standardError.write(Data("[Settings] save failed: \(error)\n".utf8)) }
            onChange(oldValue, config)
        }
    }
    @ObservationIgnored let store: ConfigStore
    @ObservationIgnored var onChange: (_ old: LiftoffConfig, _ new: LiftoffConfig) -> Void = { _, _ in }

    var dataDir: URL { store.directory }

    init(store: ConfigStore) {
        self.store = store
        config = store.load()
    }

    /// Picks up hand edits of config.json (e.g. before showing Settings).
    func reload() {
        config = store.load()
    }
}

/// The user-visible product name and slogan (internal ids, module names and the data dir stay "Liftoff").
enum Brand {
    static let name = "Ignition"
    static let slogan = "Start your day with fire."
}

/// Menu bar item, windows, and the wake → coordinator wiring.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let runNowAtLaunch: Bool
    private let observer = SystemObserver()  // one per process
    private var settings: AppSettings!
    private var coordinator: Coordinator!
    private var statusItem: NSStatusItem!
    private var notchModeItem: NSMenuItem!
    private var fullscreenModeItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var learnWindow: NSWindow?

    init(runNowAtLaunch: Bool) {
        self.runNowAtLaunch = runNowAtLaunch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ConfigStore(directory: ConfigStore.defaultDirectory)
        settings = AppSettings(store: store)
        try? store.save(settings.config)  // writes defaults on first launch (after backing up a corrupt file)
        for folder in ["voices", "illustrations", "music"] {
            try? FileManager.default.createDirectory(at: store.directory.appendingPathComponent(folder, isDirectory: true),
                                                     withIntermediateDirectories: true)
        }

        // First-launch defaults (music + sample voice clips); never overwrites the user's files.
        seedDefaultAssets(from: Bundle.main.resourceURL, into: store.directory) {
            FileHandle.standardError.write(Data(($0 + "\n").utf8))
        }

        let dataDir = store.directory
        coordinator = Coordinator(config: settings.config, observer: observer,
                                  makeAudio: { AudioDirector(config: $0, dataDir: dataDir) },
                                  ledgerStore: LedgerStore(directory: dataDir), configStore: store)
        settings.onChange = { [weak self] old, new in
            if old.displayMode != new.displayMode { self?.coordinator.displayModeChanged(to: new.displayMode) }
            if old.illustrationVariants != new.illustrationVariants {
                self?.coordinator.illustrationVariantsChanged(to: new.illustrationVariants)
            }
        }
        coordinator.saveIllustrationVariant = { [weak self] id, variant in
            self?.settings.config.illustrationVariants[id] = variant
        }
        coordinator.isLearningDevices = { [weak self] in self?.learnWindow != nil }
        buildStatusItem()

        // Until a cable / dock / K7 device is learned the dock step can't tick by itself: ask first
        // (a wake-triggered run waits for the wizard to close).
        if needsDeviceLearning(settings.config), !runNowAtLaunch { showLearnDevices() }
        if runNowAtLaunch { coordinator.runNow() }
        let wakes = observer.wakeEvents  // yields `.launch` now: launch at login counts as a wake
        Task { [weak self] in
            for await reason in wakes { self?.coordinator.handleWake(reason) }
        }
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "airplane.departure", accessibilityDescription: Brand.name)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "\(Brand.name) — \(Brand.slogan)"

        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        let headerText = NSMutableAttributedString(string: Brand.name,
                                                   attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        headerText.append(NSAttributedString(string: "  " + Brand.slogan,
                                             attributes: [.font: NSFont.systemFont(ofSize: 12),
                                                          .foregroundColor: NSColor.secondaryLabelColor]))
        header.attributedTitle = headerText
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item("Start pre-flight now", #selector(startNow)))
        menu.addItem(.separator())

        let modes = NSMenu()
        notchModeItem = item("Notch", #selector(chooseNotch))
        fullscreenModeItem = item("Fullscreen", #selector(chooseFullscreen))
        modes.addItem(notchModeItem)
        modes.addItem(fullscreenModeItem)
        let modeItem = NSMenuItem(title: "Display mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modes
        menu.addItem(modeItem)

        menu.addItem(item("Learn my devices…", #selector(learnDevices)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(Brand.name)", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        notchModeItem.state = settings.config.displayMode == .notch ? .on : .off
        fullscreenModeItem.state = settings.config.displayMode == .fullscreen ? .on : .off
    }

    @objc private func startNow() { coordinator.runNow() }
    @objc private func chooseNotch() { settings.config.displayMode = .notch }
    @objc private func chooseFullscreen() { settings.config.displayMode = .fullscreen }
    @objc private func learnDevices() { showLearnDevices() }
    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Windows

    func showSettings() {
        settings.reload()
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, onLearnDevices: { [weak self] in self?.showLearnDevices() })
            settingsWindow = Self.makeWindow(title: "\(Brand.name) Settings", content: view)
        }
        present(settingsWindow)
    }

    func showLearnDevices() {
        let previous = learnWindow
        learnWindow = nil  // so its closing isn't taken for the wizard being done
        previous?.close()
        let model = LearnDevicesModel(learned: settings.config.learned) { [weak self] in
            self?.observer.currentSnapshot() ?? SystemSnapshot()
        }
        model.onFinish = { [weak self] learned in
            self?.settings.config.learned = learned
            self?.learnWindow?.close()
        }
        model.onCancel = { [weak self] in self?.learnWindow?.close() }
        let window = Self.makeWindow(title: "\(Brand.name) · Learn my devices", content: LearnDevicesView(model: model))
        window.delegate = self
        learnWindow = window
        present(window)
    }

    /// The Learn wizard closed (saved, cancelled or the close button): a wake held back while it
    /// was open gets its turn now.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === learnWindow else { return }
        learnWindow = nil
        Task { [weak self] in self?.coordinator.handleWake(.learnWizardClosed) }
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    static func makeWindow(title: String, content: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }
}
