import Foundation
import LiftoffCore
import LiftoffSystem

let usage = """
    usage: liftoff-voices generate [--voice <id>] [--force]   generate voices/<id>.mp3 for every non-date line
           liftoff-voices voices                              list the ElevenLabs account's voices
           liftoff-voices set-key                             store the API key (typed without echo) in the Keychain

    The API key comes from the Keychain (service com.daitran.liftoff, account elevenlabs)
    or the ELEVENLABS_API_KEY environment variable.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("liftoff-voices: \(message)\n".utf8))
    exit(1)
}

func requireKey() -> String {
    guard let key = Keychain.elevenLabsKey() else {
        fail("no ElevenLabs API key. Run `liftoff-voices set-key` or set ELEVENLABS_API_KEY.")
    }
    return key
}

func generate(_ args: [String]) async {
    var voiceOverride: String?
    var force = false
    var rest = args[...]
    while let arg = rest.popFirst() {
        switch arg {
        case "--voice":
            guard let id = rest.popFirst() else { fail("--voice needs a voice id") }
            voiceOverride = id
        case "--force":
            force = true
        default:
            fail("unknown option \(arg)\n\(usage)")
        }
    }

    let key = requireKey()
    let dataDir = ConfigStore.defaultDirectory
    let config = ConfigStore(directory: dataDir).load()
    guard let voiceID = voiceOverride ?? config.elevenLabsVoiceID, !voiceID.isEmpty else {
        fail("no voice id. Pass --voice <id> or set elevenLabsVoiceID in \(dataDir.path)/config.json (see `liftoff-voices voices`).")
    }
    let catalog: VoiceCatalog
    do { catalog = try VoiceCatalog.installed(in: dataDir) } catch { fail("cannot load the voice catalog: \(error)") }

    let voicesDir = dataDir.appendingPathComponent("voices", isDirectory: true)
    let client = ElevenLabsClient(apiKey: key, voiceID: voiceID)
    let summary: VoiceGenerator.Summary
    do {
        summary = try await VoiceGenerator.generate(catalog: catalog, voicesDir: voicesDir, client: client, force: force) {
            print($0)
        }
    } catch {
        fail("cannot create \(voicesDir.path): \(error)")
    }
    print("done: \(summary.generated) generated, \(summary.skipped) skipped, \(summary.failed) failed → \(voicesDir.path)")
    if summary.failed > 0 { exit(1) }
}

func listVoices() async {
    let client = ElevenLabsClient(apiKey: requireKey(), voiceID: "")
    do {
        for voice in try await client.listVoices() { print("\(voice.voiceID)  \(voice.name)") }
    } catch {
        fail("could not list voices: \(error)")
    }
}

func setKey() {
    // readpassphrase disables terminal echo so the key never appears on screen.
    var buffer = [CChar](repeating: 0, count: 512)
    guard let entered = readpassphrase("ElevenLabs API key (input hidden): ", &buffer, buffer.count, RPP_REQUIRE_TTY) else {
        fail("could not read the key (a terminal is required)")
    }
    let key = String(cString: entered).trimmingCharacters(in: .whitespacesAndNewlines)
    buffer.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
    guard !key.isEmpty else { fail("no key entered") }
    do { try Keychain.setElevenLabsKey(key) } catch { fail("\(error)") }
    print("Saved to the Keychain.")
}

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "generate": await generate(Array(arguments.dropFirst()))
case "voices": await listVoices()
case "set-key": setKey()
default:
    print(usage)
    exit(arguments.isEmpty || arguments.first == "--help" ? 0 : 1)
}
