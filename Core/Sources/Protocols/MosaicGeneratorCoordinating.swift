import Foundation
import SwiftData
@preconcurrency import HyperMovieModels

/// Progress information for mosaic generation
@available(macOS 15, *)
public struct MosaicGenerationProgress: Sendable {
    /// The video being processed
    public let video: Video
    
    /// The progress value (0.0 to 1.0)
    public let progress: Double
    
    /// The status of the generation
    public let status: MosaicGenerationStatus
    
    /// The output URL if generation is complete
    public let outputURL: URL?
    
    /// The error if generation failed
    public let error: Error?
    
    /// Creates a new progress information instance
    public init(
        video: Video,
        progress: Double,
        status: MosaicGenerationStatus,
        outputURL: URL? = nil,
        error: Error? = nil
    ) {
        self.video = video
        self.progress = progress
        self.status = status
        self.outputURL = outputURL
        self.error = error
    }
}

/// Status of mosaic generation
@available(macOS 15, *)
public enum MosaicGenerationStatus: Sendable {
    /// Generation is queued
    case queued
    
    /// Generation is in progress
    case inProgress
    
    /// Generation is complete
    case completed
    
    /// Generation failed
    case failed
    
    /// Generation was cancelled
    case cancelled
}

/// Result of mosaic generation
@available(macOS 15, *)
public struct MosaicGenerationResult: Sendable {
    /// The video that was processed
    public let video: Video
    
    /// The output URL of the generated mosaic
    public let outputURL: URL?
    
    /// The error if generation failed
    public let error: Error?
    
    /// Whether generation was successful
    public var isSuccess: Bool {
        outputURL != nil && error == nil
    }
    
    /// Creates a new result instance
    public init(video: Video, outputURL: URL? = nil, error: Error? = nil) {
        self.video = video
        self.outputURL = outputURL
        self.error = error
    }
}

/// Protocol defining the interface for mosaic generation coordination
@available(macOS 15, *)
public protocol MosaicGeneratorCoordinating: Actor {
    /// Generate a mosaic for a single video
    /// - Parameters:
    ///   - video: The video to generate a mosaic for
    ///   - config: The configuration for mosaic generation
    ///   - progressHandler: Handler for progress updates
    /// - Returns: The result of mosaic generation
    func generateMosaic(
        for video: Video,
        config: MosaicConfiguration,
        progressHandler: @escaping (MosaicGenerationProgress) -> Void
    ) async throws -> MosaicGenerationResult
    
    /// Generate mosaics for videos in a folder
    /// - Parameters:
    ///   - folderURL: The URL of the folder containing videos
    ///   - config: The configuration for mosaic generation
    ///   - recursive: Whether to search for videos recursively
    ///   - progressHandler: Handler for progress updates
    /// - Returns: Array of generation results
    func generateMosaicsForFolder(
        at folderURL: URL,
        config: MosaicConfiguration,
        recursive: Bool,
        progressHandler: @escaping (MosaicGenerationProgress) -> Void
    ) async throws -> [MosaicGenerationResult]
    
    /// Generate mosaics for videos in a smart folder
    /// - Parameters:
    ///   - smartFolder: The smart folder containing videos
    ///   - config: The configuration for mosaic generation
    ///   - progressHandler: Handler for progress updates
    /// - Returns: Array of generation results
    func generateMosaicsForSmartFolder(
        _ smartFolder: LibraryItem,
        config: MosaicConfiguration,
        progressHandler: @escaping (MosaicGenerationProgress) -> Void
    ) async throws -> [MosaicGenerationResult]
    
    /// Cancel mosaic generation for a specific video
    /// - Parameter video: The video to cancel mosaic generation for
    func cancelGeneration(for video: Video)
    
    /// Cancel all ongoing mosaic generation operations
    func cancelAllGenerations()
} 
