import Foundation
import HyperMovieModels

/// Protocol defining video processing operations.
@available(macOS 15, *)
public protocol VideoProcessing: Actor {
    /// Process a video file at the given URL.
    /// - Parameter url: The URL of the video file to process.
    /// - Returns: A processed Video object.
    /// - Throws: VideoError if processing fails.
    func process(url: URL) async throws -> Video
    
    /// Process multiple video files with adaptive concurrency.
    /// - Parameters:
    ///   - urls: The URLs of the video files to process.
    ///   - minConcurrent: Minimum number of concurrent operations.
    ///   - maxConcurrent: Maximum number of concurrent operations.
    /// - Returns: An array of processed Video objects.
    /// - Throws: VideoError if processing fails.
    func processMultiple(urls: [URL], minConcurrent: Int, maxConcurrent: Int) async throws -> [Video]
    
    /// Extract metadata from a video file.
    /// - Parameter video: The video to extract metadata from.
    /// - Throws: VideoError if metadata extraction fails.
    func extractMetadata(for video: Video) async throws
    
    /// Generate a thumbnail for a video.
    /// - Parameters:
    ///   - video: The video to generate a thumbnail for.
    ///   - size: The desired size of the thumbnail.
    /// - Returns: The URL of the generated thumbnail.
    /// - Throws: VideoError if thumbnail generation fails.
    func generateThumbnail(for video: Video, size: CGSize) async throws -> URL
    
    /// Cancel all ongoing processing operations.
    func cancelAllOperations()

    /// Get current processing metrics.
    /// - Returns: ProcessingMetrics containing CPU usage, memory available, and disk I/O pressure.
    func getCurrentMetrics() -> HyperMovieModels.ProcessingMetrics
}

/// Default implementations for VideoProcessing.
@available(macOS 15, *)
public extension VideoProcessing {
    func processMultiple(urls: [URL]) async throws -> [Video] {
        try await processMultiple(urls: urls, minConcurrent: 2, maxConcurrent: 8)
    }
    
    func cancelAllOperations() {
        // Default implementation does nothing
    }
} 