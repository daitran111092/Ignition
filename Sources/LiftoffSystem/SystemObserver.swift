import Foundation
import LiftoffCore

/// Aggregates the USB, HID (keyboard / mouse), audio, display, app, music and wake monitors into two event streams.
///
/// Observing starts on first access of `events` / `wakeEvents`. `events` begins with
/// `.snapshot(currentSnapshot())` followed by `.appActivated(<frontmost app>)`; afterwards every
/// device/app/music change re-emits a snapshot, debounced by 300 ms. `wakeEvents` yields `.launch` once
/// at start and then the reason of every wake / screen wake / unlock. Each stream is meant for a single consumer.
@MainActor
public final class SystemObserver {
    private static let debounce: Duration = .milliseconds(300)

    private lazy var usb = USBMonitor { [weak self] in self?.scheduleSnapshot() }
    private lazy var hid = HIDMonitor { [weak self] in self?.scheduleSnapshot() }
    private lazy var audio = AudioDeviceMonitor { [weak self] in self?.scheduleSnapshot() }
    private lazy var display = DisplayMonitor { [weak self] in self?.scheduleSnapshot() }
    private lazy var apps = AppMonitor(onChange: { [weak self] in self?.scheduleSnapshot() },
                                       onActivate: { [weak self] app in self?.eventContinuation?.yield(.appActivated(app)) })
    private lazy var music = MusicMonitor { [weak self] playing in
        self?.eventContinuation?.yield(.musicStateChanged(playing: playing))
        self?.scheduleSnapshot()
    }
    private lazy var wake = WakeMonitor { [weak self] reason in self?.wakeContinuation?.yield(reason) }

    private var eventStream: AsyncStream<SystemEvent>?
    private var eventContinuation: AsyncStream<SystemEvent>.Continuation?
    private var wakeStream: AsyncStream<WakeReason>?
    private var wakeContinuation: AsyncStream<WakeReason>.Continuation?
    private var pendingSnapshot: Task<Void, Never>?

    public init() {}

    public func currentSnapshot() -> SystemSnapshot {
        SystemSnapshot(devices: Set(usb.currentDevices() + hid.currentDevices() + audio.currentDevices() + display.currentDevices()),
                       runningApps: apps.runningApps(),
                       musicPlaying: music.lastPlaying)
    }

    public var events: AsyncStream<SystemEvent> {
        if let eventStream { return eventStream }
        let (stream, continuation) = AsyncStream<SystemEvent>.makeStream()
        eventStream = stream
        eventContinuation = continuation
        usb.start()
        hid.start()
        audio.start()
        display.start()
        apps.start()
        music.start()
        continuation.yield(.snapshot(currentSnapshot()))
        if let front = apps.frontmostApp() { continuation.yield(.appActivated(front)) }
        return stream
    }

    public var wakeEvents: AsyncStream<WakeReason> {
        if let wakeStream { return wakeStream }
        let (stream, continuation) = AsyncStream<WakeReason>.makeStream()
        wakeStream = stream
        wakeContinuation = continuation
        wake.start()
        continuation.yield(.launch)  // app launch counts as a wake
        return stream
    }

    /// Music's play state straight from Music (AppleScript); nil if not running, on error or denial.
    public func queryMusicPlaying() -> Bool? {
        music.queryPlaying()
    }

    private func scheduleSnapshot() {
        guard eventContinuation != nil else { return }
        pendingSnapshot?.cancel()
        pendingSnapshot = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            self.eventContinuation?.yield(.snapshot(self.currentSnapshot()))
        }
    }
}
