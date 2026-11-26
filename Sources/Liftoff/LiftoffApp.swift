import AppKit
import LiftoffCore
import LiftoffSystem

@main
struct LiftoffApp {
    @MainActor
    static func main() {
        // Launch Services may pass a legacy `-psn_…` process serial number; it is not a flag.
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
        // Hidden developer flags.
        switch args.first {
        case nil:
            runApp(runNow: false)
        case "--run-now":
            runApp(runNow: true)
        case "--probe":
            runProbe()
        case "--say-test":
            runSayTest()
        case "--preview-notch":
            NotchPreview.run(arguments: Array(args.dropFirst()))
        case "--render-notch":
            NotchPreview.render(arguments: Array(args.dropFirst()))
        case "--preview-fullscreen":
            FullscreenPreview.run(arguments: Array(args.dropFirst()))
        case "--render-fullscreen":
            FullscreenPreview.render(arguments: Array(args.dropFirst()))
        case "--render-settings":
            WindowPreview.renderSettings(arguments: Array(args.dropFirst()))
        case "--render-learn":
            WindowPreview.renderLearn(arguments: Array(args.dropFirst()))
        default:
            print("Ignition: unknown arguments \(args.joined(separator: " "))")
        }
    }

    /// The menu bar app. `--run-now` also starts a fresh pre-flight immediately (outside the window too).
    @MainActor
    private static func runApp(runNow: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(runNowAtLaunch: runNow)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    /// Prints every `SystemEvent` and wake event to stdout until killed.
    @MainActor
    private static func runProbe() {
        setvbuf(stdout, nil, _IOLBF, 0)  // line-buffered even when redirected to a file
        let observer = SystemObserver()
        // Keyboards and mice on their own line, so names for the keyboard / mouse hints are easy to check.
        let hid = observer.currentSnapshot().devices.filter { $0.kind == .hid }
            .sorted { $0.name < $1.name }
            .map { d in d.name + (d.vendorID.map { " [\($0):\(d.productID ?? 0)]" } ?? "") }
        print("hid: \(hid)")
        Task {
            for await event in observer.events { print("event: \(describe(event))") }
        }
        Task {
            for await _ in observer.wakeEvents { print("wake") }
        }
        RunLoop.main.run()
    }

    /// Audio smoke test: chime, a pre-generated clip (first in `voices/`), a missing clip (falls back
    /// to the system voice), two system-voice lines (music ducks if `music/` has a track), tick, liftoff.
    @MainActor
    private static func runSayTest() {
        setvbuf(stdout, nil, _IOLBF, 0)
        let dataDir = ConfigStore.defaultDirectory
        let director = AudioDirector(config: ConfigStore(directory: dataDir).load(), dataDir: dataDir)
        print("system voice: \(director.systemVoiceName ?? "none")")
        print("voice path: \(director.voicePath)")
        let voicesDir = dataDir.appendingPathComponent("voices", isDirectory: true)
        let firstClip = ((try? FileManager.default.contentsOfDirectory(atPath: voicesDir.path)) ?? [])
            .filter { $0.hasSuffix(".mp3") }.sorted().first.map { voicesDir.appendingPathComponent($0) }
        Task { @MainActor in
            director.startMusic()
            director.play(.chime)
            try? await Task.sleep(for: .seconds(1.5))
            let today = renderDate(Date(), calendar: .current)
            var lines: [(String, ClipSource)] = []
            if let firstClip {
                lines.append(("clip \(firstClip.lastPathComponent)", .file(firstClip, fallbackText: "Clip failed.")))
            }
            lines.append(("missing clip → fallback", .file(voicesDir.appendingPathComponent("no-such-clip.mp3"),
                                                         fallbackText: "This clip is missing, so the system voice speaks.")))
            for line in ["Good morning, Commander. Today is \(today).", "Dock is online. Now, power up your FiiO K7."] {
                lines.append(("synthesized", .synthesize(line)))
            }
            for (label, source) in lines {
                let start = Date()
                await director.say(source)
                print(String(format: "said in %.1fs: %@", Date().timeIntervalSince(start), label))
            }
            director.play(.tick)
            try? await Task.sleep(for: .seconds(1))
            director.play(.liftoff)
            director.fadeOutMusic(duration: 2)
            try? await Task.sleep(for: .seconds(2.5))
            director.stopAll()
            print("say-test done")
            exit(0)
        }
        RunLoop.main.run()
    }

    private static func describe(_ event: SystemEvent) -> String {
        switch event {
        case .snapshot(let snapshot):
            let devices = snapshot.devices
                .sorted { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) }
                .map { d in "\(d.kind.rawValue):\(d.name)" + (d.vendorID.map { " [\($0):\(d.productID ?? 0)]" } ?? "") }
            let music = snapshot.musicPlaying.map(String.init) ?? "nil"
            return "snapshot devices=\(devices) apps=\(snapshot.runningApps.count) musicPlaying=\(music)"
        case .appActivated(let app):
            return "appActivated(\(app.bundleID ?? "nil"), \"\(app.name)\")"
        case .musicStateChanged(let playing):
            return "musicStateChanged(playing: \(playing))"
        }
    }
}
