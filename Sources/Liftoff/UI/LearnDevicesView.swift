import Observation
import SwiftUI
import LiftoffCore

/// Drives the "Learn my devices" wizard: wraps `LearnSession` and re-checks the system once a
/// second while a device page is showing (only while the wizard is open).
@MainActor @Observable
final class LearnDevicesModel {
    private(set) var session: LearnSession
    private(set) var detected: [DeviceSignature] = []
    @ObservationIgnored var onFinish: ([StepID: [DeviceSignature]]) -> Void = { _ in }
    @ObservationIgnored var onCancel: () -> Void = {}
    @ObservationIgnored private let snapshot: () -> SystemSnapshot
    @ObservationIgnored private var polling: Task<Void, Never>?

    init(learned: [StepID: [DeviceSignature]], snapshot: @escaping () -> SystemSnapshot) {
        session = LearnSession(learned: learned)
        self.snapshot = snapshot
    }

    func begin() {
        session.begin(snapshot())
        detected = []
        startPolling()
    }

    func retry() {
        session.retry(snapshot())
        detected = []
    }

    func next() {
        session.next(snapshot())
        detected = []
        if session.page == .finished { stop() }
    }

    func save() { onFinish(session.learned) }

    func refresh() { detected = session.detect(snapshot()) }

    func stop() {
        polling?.cancel()
        polling = nil
    }

    private func startPolling() {
        stop()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

struct LearnDevicesView: View {
    let model: LearnDevicesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 480, height: 460)
        .onDisappear { model.stop() }
    }

    private var pageNumber: Int? {
        guard case .device(let step) = model.session.page else { return nil }
        return LearnSession.learnableSteps.firstIndex(of: step).map { $0 + 1 }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.15)))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                if let pageNumber {
                    Text("Step \(pageNumber) of \(LearnSession.learnableSteps.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(title).font(.title2.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.session.page {
        case .unplug:
            Text("Unplug the cables and the keyboard, switch off the dock, the mouse and the K7.")
                .font(.body)
            Text("\(Brand.name) notes what is still connected, then watches what appears as you plug in each device. It takes about a minute, and you can run it again any time from the menu bar.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .device:
            Text(instruction).font(.body).fixedSize(horizontal: false, vertical: true)
            detectedList
        case .finished:
            Text("Here is what \(Brand.name) will look for each morning.")
            summary
        }
    }

    private var detectedList: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if model.detected.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Watching for new devices…").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.detected, id: \.self) { device in
                        Label(describe(device), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Text("Detected").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(LearnSession.learnableSteps, id: \.self) { step in
                    let devices = model.session.learned[step] ?? []
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stepName(step)).font(.callout.weight(.semibold))
                        Text(devices.isEmpty ? "Nothing learned: uses the built-in guess" : devices.map(\.name).joined(separator: ", "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("Cancel", action: model.onCancel)
            Spacer()
            switch model.session.page {
            case .unplug:
                Button("Everything is off", action: model.begin).keyboardShortcut(.defaultAction)
            case .device:
                Button("Retry", action: model.retry)
                    .help("Ignore what was detected so far and watch again from now")
                Button(model.detected.isEmpty ? "Skip" : "Next", action: model.next).keyboardShortcut(.defaultAction)
            case .finished:
                Button("Save", action: model.save).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var title: String {
        switch model.session.page {
        case .unplug: "Learn my devices"
        case .device(.cables): "Plug in both cables"
        case .device(.dock): "Switch on the Acasis"
        case .device(.keyboard): "Plug in the keyboard"
        case .device(.mouse): "Switch on the mouse"
        case .device: "Switch on the K7"
        case .finished: "All set"
        }
    }

    private var instruction: String {
        switch model.session.page {
        case .device(.cables): "Connect both Ugreen Type-C cables: one to the monitor, one to the dock. Leave the dock switched off."
        case .device(.dock): "Switch on the Acasis dock and wait a few seconds for its devices to appear."
        case .device(.keyboard): "Plug the Reclusa keyboard into the dock."
        case .device(.mouse): "Switch on the MX Master 4 and wait for it to connect."
        default: "Switch on the FiiO K7."
        }
    }

    private var symbol: String {
        switch model.session.page {
        case .unplug: "powerplug"
        case .device(.cables): "cable.connector"
        case .device(.dock): "externaldrive.connected.to.line.below"
        case .device(.keyboard): "keyboard"
        case .device(.mouse): "computermouse"
        case .device: "hifispeaker"
        case .finished: "checkmark.seal"
        }
    }

    private func stepName(_ step: StepID) -> String {
        switch step {
        case .cables: "Cables (monitor)"
        case .dock: "Acasis dock"
        case .keyboard: "Reclusa keyboard"
        case .mouse: "MX Master 4"
        default: "FiiO K7"
        }
    }

    private func describe(_ device: DeviceSignature) -> String {
        guard let vendor = device.vendorID, let product = device.productID else { return device.name }
        return "\(device.name)  " + String(format: "%04X:%04X", vendor, product)
    }
}
