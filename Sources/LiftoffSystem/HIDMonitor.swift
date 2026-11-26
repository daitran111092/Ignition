import Foundation
import IOKit.hid
import LiftoffCore

/// Lists external keyboards and mice (USB, Bluetooth, Logi Bolt…) and reports connect/disconnect.
///
/// Only matches and reads properties: the manager and its devices are never opened or seized, so no
/// Input Monitoring permission is needed. Built-in input devices (the internal keyboard / trackpad)
/// are skipped. A device exposing several matching interfaces collapses into one signature.
@MainActor
final class HIDMonitor {
    private let relay: MainRelay
    private let manager: IOHIDManager
    private var started = false

    init(onChange: @escaping @MainActor () -> Void) {
        relay = MainRelay(onChange)
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
    }

    func start() {
        guard !started else { return }
        started = true
        // Retained for the process lifetime: the manager is never torn down.
        let context = Unmanaged.passRetained(relay).toOpaque()
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<MainRelay>.fromOpaque(context).takeUnretainedValue().fire()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func currentDevices() -> [DeviceSignature] {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Array(Set(devices.compactMap(Self.signature)))
    }

    private static func signature(of device: IOHIDDevice) -> DeviceSignature? {
        if (property(device, kIOHIDBuiltInKey) as? NSNumber)?.boolValue == true { return nil }
        if let transport = property(device, kIOHIDTransportKey) as? String, ["SPI", "FIFO"].contains(transport) {
            return nil
        }
        guard let name = (property(device, kIOHIDProductKey) as? String)?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty, !name.localizedCaseInsensitiveContains("Apple Internal") else { return nil }
        return DeviceSignature(kind: .hid, name: name,
                               vendorID: (property(device, kIOHIDVendorIDKey) as? NSNumber)?.intValue,
                               productID: (property(device, kIOHIDProductIDKey) as? NSNumber)?.intValue)
    }

    private static func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }
}
