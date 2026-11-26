import Foundation

public enum ElevenLabsError: Error, CustomStringConvertible {
    case http(status: Int, body: String)
    case notHTTP

    public var description: String {
        switch self {
        case .http(let status, let body): "ElevenLabs HTTP \(status): \(body)"
        case .notHTTP: "ElevenLabs returned a non-HTTP response"
        }
    }
}

public struct ElevenLabsVoice: Decodable, Equatable, Sendable {
    public var voiceID: String
    public var name: String

    public init(voiceID: String, name: String) {
        self.voiceID = voiceID
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id"
        case name
    }
}

public struct ElevenLabsClient: Sendable {
    public static let baseURL = URL(string: "https://api.elevenlabs.io")!
    public static let modelID = "eleven_multilingual_v2"

    public let apiKey: String
    public let voiceID: String
    private let session: URLSession

    public init(apiKey: String, voiceID: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.session = session
    }

    public func request(for text: String) -> URLRequest {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("v1/text-to-speech/\(voiceID)"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(["text": text, "model_id": Self.modelID])
        return request
    }

    /// MP3 bytes for `text`; throws `ElevenLabsError.http` on any non-2xx status.
    public func synthesize(_ text: String) async throws -> Data {
        try await send(request(for: text))
    }

    /// The voices available to this account (`GET /v1/voices`).
    public func listVoices() async throws -> [ElevenLabsVoice] {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("v1/voices"))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        struct Envelope: Decodable { var voices: [ElevenLabsVoice] }
        return try JSONDecoder().decode(Envelope.self, from: await send(request)).voices
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ElevenLabsError.notHTTP }
        guard (200..<300).contains(http.statusCode) else {
            throw ElevenLabsError.http(status: http.statusCode, body: String(decoding: data.prefix(500), as: UTF8.self))
        }
        return data
    }
}
