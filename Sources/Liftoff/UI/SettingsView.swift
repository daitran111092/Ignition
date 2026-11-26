import AppKit
import ServiceManagement
import SwiftUI
import LiftoffCore
import LiftoffSystem

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var onLearnDevices: () -> Void = {}

    @State private var apiKey = ""
    @State private var keyStatus = ""
    @State private var generationStatus = ""
    @State private var isGenerating = false
    @State private var confirmRegenerate = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError = ""

    /// Calendar weekday numbers, Monday first.
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Brand.name).font(.title2.weight(.bold))
                        Text(Brand.slogan).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Pre-flight") {
                Picker("Display mode", selection: $settings.config.displayMode) {
                    Text("Notch").tag(DisplayMode.notch)
                    Text("Fullscreen").tag(DisplayMode.fullscreen)
                }
                .pickerStyle(.segmented)
                DatePicker("Starts from", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                LabeledContent("On") {
                    HStack(spacing: 4) {
                        ForEach(Self.weekdayOrder, id: \.self) { day in
                            Toggle(Calendar.current.veryShortWeekdaySymbols[day - 1], isOn: weekdayBinding(day))
                                .toggleStyle(.button)
                        }
                    }
                }
                LabeledContent("Devices") {
                    Button("Learn my devices…", action: onLearnDevices)
                }
            }

            Section("Sound") {
                Toggle("Voice", isOn: $settings.config.voiceEnabled)
                Slider(value: $settings.config.voiceVolume, in: 0...1) { Text("Voice volume") }
                    .disabled(!settings.config.voiceEnabled)
                Toggle("Room speaker effect on voice", isOn: $settings.config.voiceRoomEffect)
                    .disabled(!settings.config.voiceEnabled)
                Toggle("Background music", isOn: $settings.config.musicEnabled)
                Slider(value: $settings.config.musicVolume, in: 0...1) { Text("Music volume") }
                    .disabled(!settings.config.musicEnabled)
                LabeledContent("Assets") {
                    Button("Open assets folder") { NSWorkspace.shared.open(settings.dataDir) }
                }
            }

            Section {
                HStack {
                    SecureField("ElevenLabs API key", text: $apiKey, prompt: Text("Paste a new key"))
                    Button("Save key", action: saveKey).disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                TextField("Voice ID", text: voiceIDBinding, prompt: Text("e.g. 21m00Tcm4TlvDq8ikWAM"))
                LabeledContent("Clips") {
                    HStack {
                        if isGenerating { ProgressView().controlSize(.small) }
                        Button("Regenerate voices") { confirmRegenerate = true }
                            .disabled(isGenerating || (settings.config.elevenLabsVoiceID ?? "").isEmpty)
                    }
                }
                if !generationStatus.isEmpty {
                    Text(generationStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } header: {
                Text("Voice (ElevenLabs)")
            } footer: {
                Text(keyStatus.isEmpty
                     ? "The key is stored in your Keychain. If macOS asks \(Brand.name) for Keychain access, click “Always Allow”. Without a key the system voice reads every line."
                     : keyStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                LabeledContent("Status", value: loginStatusText)
                if !loginError.isEmpty {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 930)
        .confirmationDialog("Regenerate every voice clip?", isPresented: $confirmRegenerate) {
            Button("Regenerate") { regenerate() }
        } message: {
            Text("This sends about 6,000 characters to ElevenLabs (the free tier allows 10,000 a month).")
        }
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    // MARK: Bindings

    private func minuteBinding(_ keyPath: WritableKeyPath<TriggerWindow, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(settings.config.window[keyPath: keyPath] * 60))
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.config.window[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private func weekdayBinding(_ day: Int) -> Binding<Bool> {
        Binding {
            settings.config.window.weekdays.contains(day)
        } set: { on in
            if on { settings.config.window.weekdays.insert(day) } else { settings.config.window.weekdays.remove(day) }
        }
    }

    private var voiceIDBinding: Binding<String> {
        Binding {
            settings.config.elevenLabsVoiceID ?? ""
        } set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            settings.config.elevenLabsVoiceID = trimmed.isEmpty ? nil : trimmed
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            loginStatus == .enabled || loginStatus == .requiresApproval
        } set: { on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = ""
            } catch {
                loginError = error.localizedDescription
            }
            loginStatus = SMAppService.mainApp.status
        }
    }

    private var loginStatusText: String {
        switch loginStatus {
        case .enabled: "On"
        case .requiresApproval: "Waiting for approval in System Settings › General › Login Items"
        case .notRegistered: "Off"
        case .notFound: "Unavailable (run \(Brand.name) from ~/Applications)"
        @unknown default: "Unknown"
        }
    }

    // MARK: Actions

    /// The Keychain write runs off the main actor: it can raise a system prompt.
    private func saveKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        keyStatus = "Saving…"
        Task {
            let result = await Task.detached { Result { try Keychain.setElevenLabsKey(key) } }.value
            switch result {
            case .success:
                apiKey = ""
                keyStatus = "Key saved to the Keychain."
            case .failure(let error):
                keyStatus = "Could not save the key: \(error)"
            }
        }
    }

    /// Same as `liftoff-voices generate --force`, in-process.
    private func regenerate() {
        guard let voiceID = settings.config.elevenLabsVoiceID, !voiceID.isEmpty else { return }
        let dataDir = settings.dataDir
        isGenerating = true
        generationStatus = "Reading the API key…"
        Task {
            defer { isGenerating = false }
            guard let key = await withTimeout(seconds: 10, { Keychain.elevenLabsKey() }) else {
                generationStatus = "No API key: save one above (or click “Always Allow” if macOS asked)."
                return
            }
            do {
                let catalog = try VoiceCatalog.installed(in: dataDir)
                let client = ElevenLabsClient(apiKey: key, voiceID: voiceID)
                let voicesDir = dataDir.appendingPathComponent("voices", isDirectory: true)
                let summary = try await VoiceGenerator.generate(catalog: catalog, voicesDir: voicesDir, client: client,
                                                                force: true) { line in
                    await MainActor.run { generationStatus = line }
                }
                generationStatus = "Done: \(summary.generated) generated, \(summary.failed) failed."
            } catch {
                generationStatus = "Failed: \(error)"
            }
        }
    }
}
