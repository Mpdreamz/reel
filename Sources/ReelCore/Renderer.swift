import AVFoundation

/// Turns a take into a tape's outputs. In milestone 1 that is an export; overlays are drawn here later.
public enum Renderer {
    public static func render(_ movie: URL, to output: Output) async throws {
        let asset = AVURLAsset(url: movie)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ReelError("cannot export \(movie.path)")
        }
        try FileManager.default.createDirectory(
            at: output.url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: output.url)
        let type: AVFileType = switch output.format {
        case .mp4: .mp4
        case .mov: .mov
        }
        try await session.export(to: output.url, as: type)
    }
}
