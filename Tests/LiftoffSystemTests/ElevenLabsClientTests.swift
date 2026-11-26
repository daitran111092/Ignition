import Testing
import Foundation
@testable import LiftoffSystem

/// Answers every request without touching the network. The HTTP status is taken from the
/// last path component when it looks like `status-<code>` (the voice id in these tests),
/// so concurrent tests need no shared mutable state.
final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let last = url.lastPathComponent
        let status = last.hasPrefix("status-") ? Int(last.dropFirst("status-".count)) ?? 200 : 200
        let body: Data
        if url.path == "/v1/voices" {
            body = Data(#"{"voices":[{"voice_id":"abc123","name":"Rachel"},{"voice_id":"def456","name":"Zoe"}]}"#.utf8)
        } else if status == 200 {
            body = Data("MP3DATA".utf8)
        } else {
            body = Data(#"{"detail":{"status":"invalid_api_key"}}"#.utf8)
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

struct ElevenLabsClientTests {
    @Test func requestTargetsTextToSpeechEndpoint() throws {
        let client = ElevenLabsClient(apiKey: "sk-test", voiceID: "voice42")
        let request = client.request(for: "Good morning, Commander.")
        #expect(request.url?.absoluteString
                == "https://api.elevenlabs.io/v1/text-to-speech/voice42?output_format=mp3_44100_128")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "audio/mpeg")
    }

    @Test func requestBodyCarriesTextAndModel() throws {
        let client = ElevenLabsClient(apiKey: "sk-test", voiceID: "voice42")
        let request = client.request(for: "Now, power up your FiiO K7.")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["text"] as? String == "Now, power up your FiiO K7.")
        #expect(json["model_id"] as? String == "eleven_multilingual_v2")
    }

    @Test func synthesizeReturnsAudioOnSuccess() async throws {
        let client = ElevenLabsClient(apiKey: "sk-test", voiceID: "status-200", session: StubURLProtocol.session())
        let data = try await client.synthesize("Hello")
        #expect(data == Data("MP3DATA".utf8))
    }

    @Test func synthesizeThrowsOnUnauthorized() async throws {
        let client = ElevenLabsClient(apiKey: "bad-key", voiceID: "status-401", session: StubURLProtocol.session())
        await #expect(throws: ElevenLabsError.self) {
            _ = try await client.synthesize("Hello")
        }
    }

    @Test func listVoicesDecodesAccountVoices() async throws {
        let client = ElevenLabsClient(apiKey: "sk-test", voiceID: "", session: StubURLProtocol.session())
        let voices = try await client.listVoices()
        #expect(voices == [ElevenLabsVoice(voiceID: "abc123", name: "Rachel"),
                           ElevenLabsVoice(voiceID: "def456", name: "Zoe")])
    }
}
