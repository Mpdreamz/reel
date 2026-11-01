/// Turns a line of narration into sound.
protocol Synthesizer {
    /// The voice's name, as a reel writes it.
    var name: String { get }

    /// The line spoken, as audio, and how long it runs.
    func speak(_ text: String) async throws -> Clip
}

/// A spoken line.
struct Clip {
    var file: URL
    var seconds: Double
}
