import Foundation
import HyperMovieModels
import HyperMovieCore

/// Protocol defining the contract for folder discovery services
@available(macOS 15, *)
public protocol FolderDiscovery: Actor {
    /// Discover videos in a folder
    /// - Parameters:
    ///   - url: The folder URL to scan
    ///   - options: Configuration options for the discovery
    ///   - delegate: Delegate to receive progress updates
    /// - Returns: The result of the discovery operation
    func discoverFolder(
        at url: URL,
        options: FolderDiscoveryOptions,
        delegate: FolderDiscoveryDelegate?
    ) async throws -> DiscoveryResult
    
    /// Discover videos matching smart folder criteria
    /// - Parameters:
    ///   - options: Configuration options for the discovery
    ///   - delegate: Delegate to receive progress updates
    /// - Returns: The result of the discovery operation
    func discoverSmartFolder(
        options: SmartFolderDiscoveryOptions,
        delegate: FolderDiscoveryDelegate?
    ) async throws -> DiscoveryResult
    
    /// Check if thumbnails need to be regenerated for a folder
    /// - Parameter url: The folder URL to check
    /// - Returns: Array of videos that need thumbnail regeneration
    func checkThumbnails(at url: URL) async throws -> [Video]
    
    /// Regenerate thumbnails for specific videos
    /// - Parameters:
    ///   - videos: Array of videos needing thumbnail regeneration
    ///   - delegate: Delegate to receive progress updates
    func regenerateThumbnails(
        for videos: [Video],
        delegate: FolderDiscoveryDelegate?
    ) async throws
    
    /// Cancel the current discovery operation
    func cancelDiscovery()
}

/// Options for configuring folder discovery
@available(macOS 15, *)
public struct FolderDiscoveryOptions {
    /// Whether to recursively scan subfolders
    public let recursive: Bool
    /// Maximum number of concurrent operations
    public let concurrentOperations: Int
    /// Whether this is an update of an existing folder
    public let isUpdate: Bool
    /// Whether to generate thumbnails during discovery
    public let generateThumbnails: Bool
    
    public init(
        recursive: Bool = true,
        concurrentOperations: Int = 8,
        isUpdate: Bool = false,
        generateThumbnails: Bool = true
    ) {
        self.recursive = recursive
        self.concurrentOperations = max(1, min(concurrentOperations, 12))
        self.isUpdate = isUpdate
        self.generateThumbnails = generateThumbnails
    }
}

/// Options for configuring smart folder discovery
@available(macOS 15, *)
public struct SmartFolderDiscoveryOptions {
    /// The criteria for the smart folder
    public let criteria: SmartFolderCriteria
    /// Whether this is an update of an existing smart folder
    public let isUpdate: Bool
    /// Maximum number of concurrent operations
    public let concurrentOperations: Int
    /// Whether to generate thumbnails during discovery
    public let generateThumbnails: Bool
    
    public init(
        criteria: SmartFolderCriteria,
        isUpdate: Bool = false,
        concurrentOperations: Int = 8,
        generateThumbnails: Bool = true
    ) {
        self.criteria = criteria
        self.isUpdate = isUpdate
        self.concurrentOperations = max(1, min(concurrentOperations, 12))
        self.generateThumbnails = generateThumbnails
    }
}

/// Result of a folder discovery operation
@available(macOS 15, *)
public struct DiscoveryResult {
    public let addedVideos: [Video]
    public let updatedVideos: [Video]
    public let removedVideos: [Video]
    public let errors: [Error]
    public let statistics: DiscoveryStatistics
    
    public init(
        addedVideos: [Video],
        updatedVideos: [Video],
        removedVideos: [Video],
        errors: [Error],
        statistics: DiscoveryStatistics
    ) {
        self.addedVideos = addedVideos
        self.updatedVideos = updatedVideos
        self.removedVideos = removedVideos
        self.errors = errors
        self.statistics = statistics
    }
}

/// Statistics from a discovery operation
@available(macOS 15, *)
public struct DiscoveryStatistics {
    public let totalFoldersScanned: Int
    public let totalVideosFound: Int
    public let totalVideosProcessed: Int
    public let skippedFiles: Int
    public let errorFiles: Int
    public let totalProcessingTime: TimeInterval
    public let averageProcessingRate: Double
    
    public init(
        totalFoldersScanned: Int,
        totalVideosFound: Int,
        totalVideosProcessed: Int,
        skippedFiles: Int,
        errorFiles: Int,
        totalProcessingTime: TimeInterval,
        averageProcessingRate: Double
    ) {
        self.totalFoldersScanned = totalFoldersScanned
        self.totalVideosFound = totalVideosFound
        self.totalVideosProcessed = totalVideosProcessed
        self.skippedFiles = skippedFiles
        self.errorFiles = errorFiles
        self.totalProcessingTime = totalProcessingTime
        self.averageProcessingRate = averageProcessingRate
    }
}

/// Protocol for receiving discovery progress updates
@available(macOS 15, *)
public protocol FolderDiscoveryDelegate: AnyObject {
    /// Called when discovery progress is updated
    func discoveryProgressDidUpdate(_ progress: DiscoveryProgress)
    
    /// Called when a significant error occurs during discovery
    func discoveryDidEncounterError(_ error: Error)
    
    /// Called when discovery is cancelled
    func discoveryDidCancel()
    
    /// Called when discovery completes successfully
    func discoveryDidComplete(result: DiscoveryResult)
}

/// Represents the progress of a folder discovery operation
@available(macOS 15, *)
public struct DiscoveryProgress {
    public let totalFolders: Int
    public let processedFolders: Int
    public let currentFolder: String
    public let totalVideos: Int
    public let processedVideos: Int
    public let currentVideo: String
    public let skippedFiles: Int
    public let errorFiles: Int
    public let processingRate: Double
    public let estimatedTimeRemaining: TimeInterval?
    
    public init(
        totalFolders: Int = 0,
        processedFolders: Int = 0,
        currentFolder: String = "",
        totalVideos: Int = 0,
        processedVideos: Int = 0,
        currentVideo: String = "",
        skippedFiles: Int = 0,
        errorFiles: Int = 0,
        processingRate: Double = 0,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.totalFolders = totalFolders
        self.processedFolders = processedFolders
        self.currentFolder = currentFolder
        self.totalVideos = totalVideos
        self.processedVideos = processedVideos
        self.currentVideo = currentVideo
        self.skippedFiles = skippedFiles
        self.errorFiles = errorFiles
        self.processingRate = processingRate
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
} 