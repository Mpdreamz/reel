import AVFoundation
import Foundation
@testable import ReelCore
import Testing

/// Answers requests for a session in place of a voicebox server, and keeps what was asked.
final class StubServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var profiles = #"[{"id":"p-1","name":"narrator"},{"id":"p-2","name":"Other","default_engine":"kokoro"}]"#

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var request = request
        // URLSession hands the body over as a stream.
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var body = Data()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&chunk, maxLength: chunk.count)
                if read <= 0 { break }
                body.append(chunk, count: read)
            }
            request.httpBody = body
        }
        Self.requests.append(request)
        let (status, body): (Int, Data) = switch request.url?.path {
        case "/profiles": (200, Data(Self.profiles.utf8))
        case "/generate/stream": (200, Data("RIFF-fake-wav".utf8))
        default: (404, Data())
        }
        client?.urlProtocol(
            self, didReceive: HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct VoiceboxTests {
    private func voicebox(_ profile: String) -> Voicebox {
        var voice = Voicebox(
            server: URL(string: "http://studio.local:17493")!, profile: profile, language: "nl", seed: 7
        )
        voice.session = StubServer.session()
        return voice
    }

    @Test func voicesTextWithTheProfileNamedAndTheSeed() async throws {
        StubServer.requests = []
        let file = try TakeWriterTests().temporaryDirectory().appending(path: "line.wav")
        try await voicebox("narrator").speak("Pick a track", to: file)
        #expect(try Data(contentsOf: file) == Data("RIFF-fake-wav".utf8))
        let generate = try #require(StubServer.requests.last)
        #expect(generate.url?.absoluteString == "http://studio.local:17493/generate/stream")
        #expect(generate.httpMethod == "POST")
        let body = try #require(try JSONSerialization.jsonObject(with: generate.httpBody ?? Data()) as? [String: Any])
        #expect(body["profile_id"] as? String == "p-1")
        #expect(body["text"] as? String == "Pick a track")
        #expect(body["language"] as? String == "nl")
        #expect(body["seed"] as? Int == 7)
        // A profile that names no engine leaves it to voicebox.
        #expect(body["engine"] == nil)
    }

    @Test func voicesWithTheEngineTheProfileNames() async throws {
        StubServer.requests = []
        let file = try TakeWriterTests().temporaryDirectory().appending(path: "line.wav")
        try await voicebox("Other").speak("Pick a track", to: file)
        let generate = try #require(StubServer.requests.last)
        let body = try #require(try JSONSerialization.jsonObject(with: generate.httpBody ?? Data()) as? [String: Any])
        #expect(body["profile_id"] as? String == "p-2")
        #expect(body["engine"] as? String == "kokoro")
    }

    @Test func aProfileCanBeNamedByItsId() async throws {
        #expect(try await voicebox("p-2").profileID() == "p-2")
    }

    @Test func anUnknownProfileListsTheOnesThereAre() async throws {
        do {
            _ = try await voicebox("robot").profileID()
            Issue.record("expected an error")
        } catch {
            #expect("\(error)" == "voicebox has no profile 'robot'; it has narrator, Other")
        }
    }

    @Test func theFingerprintChangesWithWhatChangesTheSound() {
        let base = voicebox("narrator")
        var seeded = base
        seeded.seed = 8
        var other = base
        other.profile = "Other"
        #expect(Set([base.fingerprint, seeded.fingerprint, other.fingerprint]).count == 3)
        #expect(base.fileExtension == "wav")
    }
}

struct SystemVoiceTests {
    @Test func macOSSpeaksALine() async throws {
        let file = try TakeWriterTests().temporaryDirectory().appending(path: "line.caf")
        try await SystemVoice(name: nil, language: "en").speak("Pick a track and press play.", to: file)
        let length = try Narration.length(of: file)
        #expect(length > 0.8 && length < 6, "about two seconds of speech, not \(length)")
    }

    @Test func anUnknownVoiceNameSaysHowToListThem() async throws {
        let file = try TakeWriterTests().temporaryDirectory().appending(path: "line.caf")
        await #expect(throws: ReelError.self) {
            try await SystemVoice(name: "No Such Voice", language: "en").speak("Hi", to: file)
        }
    }
}
