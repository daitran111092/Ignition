import Testing
@testable import LiftoffCore

@Suite struct DeviceLearningTests {
    let k7 = DeviceSignature(kind: .audioOutput, name: "FiiO K7", vendorID: 0x2972, productID: 0x0047)
    let speakers = DeviceSignature(kind: .audioOutput, name: "MacBook Pro Speakers")
    let stick = DeviceSignature(kind: .usb, name: "USB Flash Drive", vendorID: 0x0781, productID: 0x5581)
    let display = DeviceSignature(kind: .display, name: "LG UltraFine")

    @Test func returnsOnlyAddedDevicesOfRequestedKind() {
        let before = SystemSnapshot(devices: [speakers])
        let after = SystemSnapshot(devices: [speakers, k7, stick])
        #expect(newDevices(before: before, after: after, kind: .audioOutput) == [k7])
        #expect(newDevices(before: before, after: after, kind: .usb) == [stick])
        #expect(newDevices(before: before, after: after, kind: .display).isEmpty)
    }

    @Test func removedDevicesAreIgnored() {
        let before = SystemSnapshot(devices: [speakers, k7, display])
        let after = SystemSnapshot(devices: [speakers])
        #expect(newDevices(before: before, after: after, kind: .audioOutput).isEmpty)
        #expect(newDevices(before: before, after: after, kind: .display).isEmpty)
    }

    @Test func emptyWhenNothingChanged() {
        let snap = SystemSnapshot(devices: [speakers, k7, stick, display])
        #expect(newDevices(before: snap, after: snap, kind: .audioOutput).isEmpty)
        #expect(newDevices(before: snap, after: snap, kind: .usb).isEmpty)
    }

    @Test func multipleNewDevicesAreSortedByName() {
        let dac2 = DeviceSignature(kind: .audioOutput, name: "AirPods Pro")
        let after = SystemSnapshot(devices: [k7, dac2])
        #expect(newDevices(before: SystemSnapshot(), after: after, kind: .audioOutput) == [dac2, k7])
    }

    @Test func learningIsNeededUntilCablesDockOrDacHasADevice() {
        var config = LiftoffConfig.default
        #expect(needsDeviceLearning(config))
        config.learned = [.cables: [], .dock: [], .dac: []]
        #expect(needsDeviceLearning(config))
        config.learned = [.water: [display]]  // not a learnable step
        #expect(needsDeviceLearning(config))
        config.learned = [.keyboard: [DeviceSignature(kind: .hid, name: "Reclusa")],
                          .mouse: [DeviceSignature(kind: .hid, name: "MX Master 4")]]  // hinted steps don't count
        #expect(needsDeviceLearning(config))
        config.learned = [.dock: [stick]]
        #expect(!needsDeviceLearning(config))
    }
}
