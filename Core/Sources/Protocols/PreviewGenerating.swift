import Foundation
import HyperMovieModels

/// Protocol defining preview generation operations.
@available(macOS 15, *)
public protocol PreviewGenerating: Actor {
    /// The current progress of preview generation (0.0 to 1.0)
    var progress: Double { get }

    /// Generate a preview video for a video.
    /// - Parameters:
    ///   - video: The video to generate a preview for.
    ///   - config: The configuration for preview generation.
    ///   - progressHandler: Optional closure to receive progress updates (0.0 to 1.0)
    /// - Returns: The URL of the generated preview video.
    /// - Throws: PreviewError if generation fails.
    func generate(for video: Video, config: PreviewConfiguration, progressHandler: @escaping (Double) -> Void) async throws -> URL
    
    /// Generate preview videos for multiple videos.
    /// - Parameters:
    ///   - videos: The videos to generate previews for.
    ///   - config: The configuration for preview generation.
    /// - Returns: A dictionary mapping video IDs to preview URLs.
    /// - Throws: PreviewError if generation fails.
    func generateMultiple(for videos: [Video], config: PreviewConfiguration) async throws -> [UUID: URL]
    
    /// Cancel preview generation for a specific video.
    /// - Parameter video: The video to cancel preview generation for.
    func cancel(for video: Video)
    
    /// Cancel all ongoing preview generation tasks.
    func cancelAll()
}

/// Default implementations for PreviewGenerating.
@available(macOS 15, *)
public extension PreviewGenerating {
    func generateMultiple(for videos: [Video], config: PreviewConfiguration) async throws -> [UUID: URL] {
        var results: [UUID: URL] = [:]
        for video in videos {
            let url = try await generate(for: video, config: config, progressHandler: { _ in })
            results[video.id] = url
        }
        return results
    }
    
    func cancel(for video: Video) {
        // Default implementation does nothing
    }
    
    func cancelAll() {
        // Default implementation does nothing
    }
} 