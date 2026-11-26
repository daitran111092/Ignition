import AppKit
import SwiftUI
import LiftoffCore

/// Hidden developer flags that write PNGs of the Settings and Learn windows (no Screen Recording
/// permission needed): `--render-settings <out.png>`, `--render-learn <out.png>` (one file per page).
/// Settings shows the real config (read-only here: nothing is saved).
@MainActor
enum WindowPreview {
    static func renderSettings(arguments: [String]) {
        guard arguments.count == 1 else { usage("--render-settings <out.png>") }
        let store = ConfigStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("liftoff-render-\(UUID().uuidString)"))
        let settings = AppSettings(store: store)
        settings.config = ConfigStore(directory: ConfigStore.defaultDirectory).load()
        write(SettingsView(settings: settings), to: arguments[0])
        try? FileManager.default.removeItem(at: store.directory)
        exit(0)
    }

    static func renderLearn(arguments: [String]) {
        guard arguments.count == 1 else { usage("--render-learn <out.png>") }
        let base = URL(fileURLWithPath: arguments[0]).deletingPathExtension().path
        let monitor = DeviceSignature(kind: .display, name: "LG HDR 4K")
        let hub = DeviceSignature(kind: .usb, name: "USB3.1 Hub", vendorID: 0x2109, productID: 0x0822)
        let ethernet = DeviceSignature(kind: .usb, name: "AX88179A", vendorID: 0x0B95, productID: 0x1790)
        var devices: Set<DeviceSignature> = [DeviceSignature(kind: .audioOutput, name: "MacBook Pro Speakers")]
        let model = LearnDevicesModel(learned: [:]) { SystemSnapshot(devices: devices) }
        write(LearnDevicesView(model: model), to: "\(base)-1-unplug.png")
        model.begin()
        model.stop()
        write(LearnDevicesView(model: model), to: "\(base)-2-cables-waiting.png")
        devices.insert(monitor)
        model.refresh()
        write(LearnDevicesView(model: model), to: "\(base)-3-cables-detected.png")
        model.next()
        devices.formUnion([hub, ethernet])
        model.refresh()
        write(LearnDevicesView(model: model), to: "\(base)-4-dock-detected.png")
        model.next()
        devices.insert(DeviceSignature(kind: .hid, name: "Razer Reclusa X Mini 65%", vendorID: 0x1532, productID: 0x02E3))
        model.refresh()
        write(LearnDevicesView(model: model), to: "\(base)-5-keyboard-detected.png")
        model.next()
        write(LearnDevicesView(model: model), to: "\(base)-6-mouse-waiting.png")
        model.next()  // mouse not found: skipped
        model.next()  // K7 not found: skipped
        write(LearnDevicesView(model: model), to: "\(base)-7-summary.png")
        exit(0)
    }

    /// Lays the view out in an off-screen window and caches its drawing (AppKit controls included,
    /// which `ImageRenderer` can't draw).
    private static func write(_ view: some View, to path: String) {
        let window = AppDelegate.makeWindow(title: "", content: view
            .background(Color(nsColor: .windowBackgroundColor))  // cacheDisplay skips the window's own background
            .environment(\.colorScheme, .dark))
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            print("render failed: \(path)"); exit(1)
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        window.orderOut(nil)
        guard let png = rep.representation(using: .png, properties: [:]) else { print("encode failed: \(path)"); exit(1) }
        do { try png.write(to: URL(fileURLWithPath: path)) } catch { print("write failed: \(error)"); exit(1) }
        print("wrote \(path)")
    }

    private static func usage(_ text: String) -> Never {
        print("usage: Ignition \(text)")
        exit(2)
    }
}
