import Foundation
import HyperMovieModels

/// Protocol defining mosaic generation operations.
@available(macOS 15, *)
public protocol MosaicGenerating: Actor {
    /// Generate a mosaic for a video.
    /// - Parameters:
    ///   - video: The video to generate a mosaic for.
    ///   - config: The configuration for mosaic generation.
    /// - Returns: The URL of the generated mosaic image.
    /// - Throws: MosaicError if generation fails.
    func generate(for video: Video, config: MosaicConfiguration) async throws -> URL
    
    /// Generate mosaics for multiple videos.
    /// - Parameters:
    ///   - videos: The videos to generate mosaics for.
    ///   - config: The configuration for mosaic generation.
    /// - Returns: A dictionary mapping video IDs to mosaic URLs.
    /// - Throws: MosaicError if generation fails.
    func generateMultiple(for videos: [Video], config: MosaicConfiguration) async throws -> [UUID: URL]
    
    /// Update an existing mosaic with new settings.
    /// - Parameters:
    ///   - video: The video to update the mosaic for.
    ///   - config: The new configuration for mosaic generation.
    /// - Returns: The URL of the updated mosaic image.
    /// - Throws: MosaicError if update fails.
    func update(for video: Video, config: MosaicConfiguration) async throws -> URL
    
    /// Cancel mosaic generation for a specific video.
    /// - Parameter video: The video to cancel mosaic generation for.
    func cancel(for video: Video)
    
    /// Cancel all ongoing mosaic generation operations.
    func cancelAll()
}

/// Default implementations for MosaicGenerating.
@available(macOS 15, *)
public extension MosaicGenerating {
    func generateMultiple(for videos: [Video], config: MosaicConfiguration) async throws -> [UUID: URL] {
        var results: [UUID: URL] = [:]
        for video in videos {
            let url = try await generate(for: video, config: config)
            results[video.id] = url
        }
        return results
    }
    
    func update(for video: Video, config: MosaicConfiguration) async throws -> URL {
        // By default, just regenerate the mosaic
        return try await generate(for: video, config: config)
    }
    
    func cancel(for video: Video) {
        // Default implementation does nothing
    }
    
    func cancelAll() {
        // Default implementation does nothing
    }
} 