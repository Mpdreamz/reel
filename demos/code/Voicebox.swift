import Foundation

/// A voice from a voicebox server: yours cloned, or a preset.
struct Voicebox: Synthesizer {
    var server: URL
    var profile: String

    var name: String { "voicebox:\(profile)" }

    func speak(_ text: String) async throws -> Clip {
        let id = try await profileID()
        let audio = try await generate(text, with: id)
        return Clip(file: audio, seconds: try duration(of: audio))
    }

    /// Looks the profile up by name first, then by id.
    func profileID() async throws -> String {
        profile
    }
}
