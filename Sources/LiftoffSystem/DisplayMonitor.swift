import AppKit
import CoreGraphics
import LiftoffCore

/// Lists external (non-built-in) displays and reports display reconfigurations.
@MainActor
final class DisplayMonitor {
    private let relay: MainRelay
    private var started = false

    init(onChange: @escaping @MainActor () -> Void) {
        relay = MainRelay(onChange)
    }

    func start() {
        guard !started else { return }
        started = true
        // Retained for the process lifetime: the callback is never unregistered.
        let context = Unmanaged.passRetained(relay).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard !flags.contains(.beginConfigurationFlag), let context else { return }
            Unmanaged<MainRelay>.fromOpaque(context).takeUnretainedValue().fire()
        }, context)
    }

    func currentDevices() -> [DeviceSignature] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let screenNames = Dictionary(NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return (number.uint32Value, screen.localizedName)
        }, uniquingKeysWith: { first, _ in first })
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.map { id in
            let vendor = Int(CGDisplayVendorNumber(id))
            let model = Int(CGDisplayModelNumber(id))
            return DeviceSignature(kind: .display, name: screenNames[id] ?? "Display \(vendor)-\(model)",
                                   vendorID: vendor, productID: model)
        }
    }
}
