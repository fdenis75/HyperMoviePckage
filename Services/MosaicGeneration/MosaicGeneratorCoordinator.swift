import Foundation
import OSLog
@preconcurrency import HyperMovieModels
import HyperMovieCore
import SwiftData
/*
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
}*/

/// Coordinator for mosaic generation operations
@available(macOS 15, *)
public actor MosaicGeneratorCoordinator: MosaicGeneratorCoordinating {
  
  
    
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "mosaic-coordinator")
    private let mosaicGenerator: any MosaicGenerating
    private let concurrencyLimit: Int
    private var activeTasks: [UUID: Task<MosaicGenerationResult, Error>] = [:]
    private var progressHandlers: [UUID: (MosaicGenerationProgress) -> Void] = [:]
    private let modelContext: ModelContext
    
    // MARK: - Initialization
    
    /// Creates a new mosaic generator coordinator
    /// - Parameters:
    ///   - mosaicGenerator: The mosaic generator to use
    ///   - modelContext: The SwiftData model context
    ///   - concurrencyLimit: Maximum number of concurrent generation tasks
    public init(mosaicGenerator: any MosaicGenerating, modelContext: ModelContext, concurrencyLimit: Int = 4) {
        self.mosaicGenerator = mosaicGenerator
        self.modelContext = modelContext
        self.concurrencyLimit = concurrencyLimit
        logger.debug("🎬 MosaicGeneratorCoordinator initialized with concurrency limit: \(concurrencyLimit)")
    }
    
    // MARK: - Public Methods
    
    /// Generate a mosaic for a single video
    /// - Parameters:
    ///   - video: The video to generate a mosaic for
    ///   - config: The configuration for mosaic generation
    ///   - progressHandler: Handler for progress updates
    /// - Returns: The result of mosaic generation
    public func generateMosaic(for video: HyperMovieModels.Video, config: HyperMovieModels.MosaicConfiguration, progressHandler: @escaping (HyperMovieCore.MosaicGenerationProgress) -> Void) async throws -> HyperMovieCore.MosaicGenerationResult {

        logger.debug("🎯 Starting mosaic generation for video: \(video.title)")
        
        // Store progress handler
        progressHandlers[video.id] = progressHandler
        
        // Report initial progress
        progressHandler(MosaicGenerationProgress(
            video: video,
            progress: 0.0,
            status: .queued
        ))
        
        // Create and start task
        let task = Task<MosaicGenerationResult, Error> {
            do {
                // Report in-progress status
                progressHandler(MosaicGenerationProgress(
                    video: video,
                    progress: 0.1,
                    status: .inProgress
                ))
                
                // Generate mosaic
                let outputURL = try await mosaicGenerator.generate(for: video, config: config)
                
                // Report completion
                let result = MosaicGenerationResult(video: video, outputURL: outputURL)
                progressHandler(MosaicGenerationProgress(
                    video: video,
                    progress: 1.0,
                    status: .completed,
                    outputURL: outputURL
                ))
                
                logger.debug("✅ Mosaic generation completed for video: \(video.title)")
                return result
            } catch {
                // Report failure
                logger.error("❌ Mosaic generation failed for video: \(video.title) - \(error.localizedDescription)")
                progressHandler(MosaicGenerationProgress(
                    video: video,
                    progress: 0.0,
                    status: .failed,
                    error: error
                ))
                throw error
            }
        }
        
        // Store task
        activeTasks[video.id] = task
        
        // Wait for task to complete
        let result = try await task.value
        
        // Clean up
        activeTasks[video.id] = nil
        progressHandlers[video.id] = nil
        
        return result
    }
    
    /// Generate mosaics for videos in a folder
    /// - Parameters:
    ///   - folderURL: The URL of the folder containing videos
    ///   - config: The configuration for mosaic generation
    ///   - recursive: Whether to search for videos recursively
    ///   - progressHandler: Handler for progress updates
    /// - Returns: Array of generation results
  public func  generateMosaicsForFolder (at folderURL: URL, config: HyperMovieModels.MosaicConfiguration, recursive: Bool, progressHandler: @escaping (HyperMovieCore.MosaicGenerationProgress) -> Void) async throws -> [HyperMovieCore.MosaicGenerationResult] {
        
        logger.debug("🗂️ Starting mosaic generation for folder: \(folderURL.path), recursive: \(recursive)")
        
        // Find videos in folder
        let videos = try await findVideosInFolder(folderURL, recursive: recursive)
        logger.debug("🔍 Found \(videos.count) videos in folder")
        
        if videos.isEmpty {
            logger.warning("⚠️ No videos found in folder: \(folderURL.path)")
            return []
        }
        
        // If saveAtRoot is enabled, ensure all videos use the same root directory
        var folderConfig = config
        if config.output.saveAtRoot {
            logger.debug("📁 Using root directory for all mosaics: \(folderURL.path)")
            // We don't need to modify the config here as the MosaicGenerator will handle this
            // based on the saveAtRoot flag in the OutputOptions
        }
        
        // Generate mosaics for videos
        return try await generateMosaicsForVideos(videos, config: folderConfig, progressHandler: progressHandler)
    }
    
    /// Generate mosaics for videos in a smart folder
    /// - Parameters:
    ///   - smartFolder: The smart folder containing videos
    ///   - config: The configuration for mosaic generation
    ///   - progressHandler: Handler for progress updates
    /// - Returns: Array of generation results
    public func generateMosaicsForSmartFolder(_ smartFolder: HyperMovieModels.LibraryItem, config: HyperMovieModels.MosaicConfiguration, progressHandler: @escaping (HyperMovieCore.MosaicGenerationProgress) -> Void) async throws -> [HyperMovieCore.MosaicGenerationResult] {
        
        guard smartFolder.type == .smartFolder else {
            logger.error("❌ Item is not a smart folder: \(smartFolder.name)")
            throw LibraryError.operationNotSupported("Item is not a smart folder")
        }
        
        logger.debug("📁 Starting mosaic generation for smart folder: \(smartFolder.name)")
        
        // Get videos from smart folder using a fetch descriptor
        let descriptor = FetchDescriptor<Video>()
        let allVideos = try modelContext.fetch(descriptor)
        
        // Filter videos based on smart folder criteria
        let videos = allVideos.filter { video in
            smartFolder.smartFolderCriteria?.matches(video) ?? false
        }
        
        if videos.isEmpty {
            logger.warning("⚠️ No videos found in smart folder: \(smartFolder.name)")
            return []
        }
        
        logger.debug("🔍 Found \(videos.count) videos in smart folder")
        
        // If saveAtRoot is enabled for smart folders, we could create a dedicated folder for this smart folder
        var smartFolderConfig = config
        if config.output.saveAtRoot {
            logger.debug("📁 Using smart folder as root directory for all mosaics: \(smartFolder.name)")
            // The MosaicGenerator will handle this based on the saveAtRoot flag
        }
        
        // Generate mosaics for videos
        return try await generateMosaicsForVideos(videos, config: smartFolderConfig, progressHandler: progressHandler)
    }
    
    /// Cancel mosaic generation for a specific video
    /// - Parameter video: The video to cancel mosaic generation for
    public func cancelGeneration(for video: Video) {
        logger.debug("❌ Cancelling mosaic generation for video: \(video.title)")
        
        // Cancel task
        activeTasks[video.id]?.cancel()
        activeTasks[video.id] = nil
        
        // Report cancellation
        progressHandlers[video.id]?(MosaicGenerationProgress(
            video: video,
            progress: 0.0,
            status: .cancelled
        ))
        
        progressHandlers[video.id] = nil
        
        // Cancel in generator - use Task to handle actor isolation
        Task {
            await mosaicGenerator.cancel(for: video)
        }
    }
    
    /// Cancel all ongoing mosaic generation operations
    public func cancelAllGenerations() {
        logger.debug("❌ Cancelling all mosaic generation tasks")
        
        // Cancel all tasks
        for (_, task) in activeTasks {
            task.cancel()
        }
        
        // Clear state
        activeTasks.removeAll()
        progressHandlers.removeAll()
        
        // Cancel in generator - use Task to handle actor isolation
        Task {
            await mosaicGenerator.cancelAll()
        }
    }
    
    // MARK: - Private Methods
    
    /// Find videos in a folder from the database
    /// - Parameters:
    ///   - folderURL: The URL of the folder to search
    ///   - recursive: Whether to search for videos recursively
    /// - Returns: Array of videos found in the folder
    private func findVideosInFolder(_ folderURL: URL, recursive: Bool) async throws -> [Video] {
        logger.debug("🔍 Finding videos in folder: \(folderURL.path), recursive: \(recursive)")
        
        // Fetch all videos from the database
        let descriptor = FetchDescriptor<Video>()
        let allVideos = try modelContext.fetch(descriptor)
        
        // Filter videos based on folder path
        let folderPath = folderURL.path
        let videos = allVideos.filter { video in
            let videoFolderPath = video.url.deletingLastPathComponent().path
            
            if recursive {
                // For recursive search, check if video path starts with folder path
                return videoFolderPath.hasPrefix(folderPath)
            } else {
                // For non-recursive search, check if video is directly in the folder
                return videoFolderPath == folderPath
            }
        }
        
        logger.debug("✅ Found \(videos.count) videos in folder: \(folderURL.path)")
        return videos
    }
    
    /// Generate mosaics for multiple videos
    /// - Parameters:
    ///   - videos: The videos to generate mosaics for
    ///   - config: The configuration for mosaic generation
    ///   - progressHandler: Handler for progress updates
    /// - Returns: Array of generation results
    private func generateMosaicsForVideos(
        _ videos: [Video],
        config: MosaicConfiguration,
        progressHandler: @escaping (MosaicGenerationProgress) -> Void
    ) async throws -> [MosaicGenerationResult] {
        logger.debug("🎬 Starting mosaic generation for \(videos.count) videos")
        
        var results: [MosaicGenerationResult] = []
        var pendingVideos = videos
        
        // Process videos in batches to respect concurrency limit
        while !pendingVideos.isEmpty {
            let batch = Array(pendingVideos.prefix(concurrencyLimit))
            pendingVideos.removeFirst(min(concurrencyLimit, pendingVideos.count))
            
            // Create tasks for batch
            let tasks = batch.map { video in
                Task {
                    do {
                        return try await generateMosaic(for: video, config: config, progressHandler: progressHandler)
                    } catch {
                        return MosaicGenerationResult(video: video, error: error)
                    }
                }
            }
            
            // Wait for all tasks to complete
            for task in tasks {
                let result = await task.value
                results.append(result)
            }
        }
        
        // Log results
        let successCount = results.filter { $0.isSuccess }.count
        logger.debug("✅ Mosaic generation completed for \(successCount)/\(videos.count) videos")
        
        return results
    }
} 
