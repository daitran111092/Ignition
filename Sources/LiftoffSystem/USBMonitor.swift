import Foundation
import IOKit
import IOKit.usb
import LiftoffCore

/// Lists non-built-in USB devices and reports plug/unplug via IOKit matching notifications.
@MainActor
final class USBMonitor {
    private let relay: MainRelay
    private var port: IONotificationPortRef?

    init(onChange: @escaping @MainActor () -> Void) {
        relay = MainRelay(onChange)
    }

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        // Retained for the process lifetime: the notification port is never torn down.
        let context = Unmanaged.passRetained(relay).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            USBMonitor.drain(iterator)
            guard let context else { return }
            Unmanaged<MainRelay>.fromOpaque(context).takeUnretainedValue().fire()
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let status = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching(kIOUSBDeviceClassName), callback, context, &iterator)
            // Draining the initial iterator arms the notification.
            if status == KERN_SUCCESS { USBMonitor.drain(iterator) }
        }
    }

    func currentDevices() -> [DeviceSignature] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOUSBDeviceClassName), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [DeviceSignature] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let device = Self.signature(of: service) { devices.append(device) }
        }
        return devices
    }

    private nonisolated static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
    }

    private static func signature(of service: io_service_t) -> DeviceSignature? {
        if (property(service, "Built-In") as? Bool) == true { return nil }
        let name = (property(service, "USB Product Name") as? String)
            ?? (property(service, kUSBProductString) as? String)
            ?? registryName(service)
        guard let name, !name.isEmpty, !name.localizedCaseInsensitiveContains("Apple Internal") else { return nil }
        return DeviceSignature(kind: .usb, name: name,
                               vendorID: (property(service, kUSBVendorID) as? NSNumber)?.intValue,
                               productID: (property(service, kUSBProductID) as? NSNumber)?.intValue)
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func registryName(_ service: io_service_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)  // io_name_t
        guard IORegistryEntryGetName(service, &buffer) == KERN_SUCCESS else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
