import Testing
@testable import LiftoffCore

@Suite struct LearnSessionTests {
    let speakers = DeviceSignature(kind: .audioOutput, name: "MacBook Pro Speakers")
    let monitor = DeviceSignature(kind: .display, name: "LG UltraFine")
    let hub = DeviceSignature(kind: .usb, name: "Acasis Hub", vendorID: 1, productID: 2)
    let ethernet = DeviceSignature(kind: .usb, name: "Acasis Ethernet", vendorID: 1, productID: 3)
    let k7 = DeviceSignature(kind: .audioOutput, name: "FiiO K7", vendorID: 9, productID: 9)
    let reclusa = DeviceSignature(kind: .hid, name: "Reclusa", vendorID: 0x1532, productID: 0x0110)
    let mx = DeviceSignature(kind: .hid, name: "MX Master 4", vendorID: 0x046D, productID: 0xB042)

    @Test func walksCablesDockKeyboardMouseDacStoringWhatAppeared() {
        var s = LearnSession(learned: [:])
        #expect(s.page == .unplug)
        s.begin(SystemSnapshot(devices: [speakers]))
        #expect(s.page == .device(.cables))

        let cablesIn = SystemSnapshot(devices: [speakers, monitor])
        #expect(s.detect(cablesIn) == [monitor])
        s.next(cablesIn)
        #expect(s.page == .device(.dock))

        let dockOn = SystemSnapshot(devices: [speakers, monitor, hub, ethernet])
        #expect(s.detect(dockOn) == [ethernet, hub])
        s.next(dockOn)
        #expect(s.page == .device(.keyboard))

        let keyboardIn = SystemSnapshot(devices: [speakers, monitor, hub, ethernet, reclusa])
        #expect(s.detect(keyboardIn) == [reclusa])
        s.next(keyboardIn)
        #expect(s.page == .device(.mouse))

        let mouseOn = SystemSnapshot(devices: [speakers, monitor, hub, ethernet, reclusa, mx])
        #expect(s.detect(mouseOn) == [mx])
        s.next(mouseOn)
        #expect(s.page == .device(.dac))

        let k7On = SystemSnapshot(devices: [speakers, monitor, hub, ethernet, reclusa, mx, k7])
        #expect(s.detect(k7On) == [k7])  // dock devices are not "new" any more
        s.next(k7On)
        #expect(s.page == .finished)
        #expect(s.learned == [.cables: [monitor], .dock: [ethernet, hub], .keyboard: [reclusa], .mouse: [mx], .dac: [k7]])
    }

    @Test func nothingDetectedKeepsThePreviousSignature() {
        let old = [DeviceSignature(kind: .display, name: "Old Monitor")]
        var s = LearnSession(learned: [.cables: old])
        s.begin(SystemSnapshot())
        s.next(SystemSnapshot())
        #expect(s.learned[.cables] == old)
    }

    @Test func retryRebaselinesSoOnlyLaterChangesCount() {
        var s = LearnSession(learned: [:])
        s.begin(SystemSnapshot())
        let wrong = SystemSnapshot(devices: [monitor])
        #expect(s.detect(wrong) == [monitor])
        s.retry(wrong)
        #expect(s.detect(wrong).isEmpty)
    }

    @Test func pageKindsMatchTheSteps() {
        #expect(LearnSession.Page.device(.cables).kind == .display)
        #expect(LearnSession.Page.device(.dock).kind == .usb)
        #expect(LearnSession.Page.device(.keyboard).kind == .hid)
        #expect(LearnSession.Page.device(.mouse).kind == .hid)
        #expect(LearnSession.Page.device(.dac).kind == .audioOutput)
    }
}
