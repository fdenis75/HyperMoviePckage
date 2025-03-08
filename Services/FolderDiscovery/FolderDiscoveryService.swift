import Foundation
import OSLog
import SwiftData
import HyperMovieCore
import AVFoundation
import HyperMovieModels
/// Represents the progress of a folder discovery operation
public struct DiscoveryProgress {
    public let totalFolders: Int
    public let processedFolders: Int
    public let currentFolder: String
    public let totalVideos: Int
    public var processedVideos: Int
    public let currentVideo: String
    public var skippedFiles: Int
    public var errorFiles: Int
    public let processingRate: Double
    public let estimatedTimeRemaining: TimeInterval?
    
    init(
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

/// Options for configuring folder discovery
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
    public let criteria: HyperMovieModels.SmartFolderCriteria
    /// Whether this is an update of an existing smart folder
    public let isUpdate: Bool
    /// Maximum number of concurrent operations
    public let concurrentOperations: Int
    /// Whether to generate thumbnails during discovery
    public let generateThumbnails: Bool
    
    public init(
        criteria: HyperMovieModels.SmartFolderCriteria,
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
    public let addedVideos: [HyperMovieModels.Video]
    public let updatedVideos: [Video]
    public let removedVideos: [Video]
    public let createdFolders: [LibraryItem]
    public let errors: [Error]
    public let statistics: DiscoveryStatistics
    
    public init(
        addedVideos: [Video],
        updatedVideos: [Video] = [],
        removedVideos: [Video] = [],
        createdFolders: [LibraryItem] = [],
        errors: [Error] = [],
        statistics: DiscoveryStatistics
    ) {
        self.addedVideos = addedVideos
        self.updatedVideos = updatedVideos
        self.removedVideos = removedVideos
        self.createdFolders = createdFolders
        self.errors = errors
        self.statistics = statistics
    }
}

/// Statistics from a discovery operation
public struct DiscoveryStatistics {
    public let totalFoldersScanned: Int
    public let totalVideosFound: Int
    public let totalVideosProcessed: Int
    public let skippedFiles: Int
    public let errorFiles: Int
    public let totalProcessingTime: TimeInterval
    public let averageProcessingRate: Double
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

/// Service responsible for discovering and processing video files in folders
@available(macOS 15.0, *)
public actor FolderDiscoveryService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "folder-discovery")
    private let signposter = OSSignposter(subsystem: "com.hypermovie", category: "folder-discovery-performance")
    private let videoFinder: VideoFinderService
    private let videoProcessor: VideoProcessor
    private var modelContext: ModelContext?
    
    private var currentTask: Task<Void, Never>?
    private var isCancelled = false
    private var smartFolderCache: [String: [URL]] = [:]
    
    // MARK: - Initialization
    
    public init(videoFinder: VideoFinderService, videoProcessor: VideoProcessor, modelContext: ModelContext? = nil) {
        self.videoFinder = videoFinder
        self.videoProcessor = videoProcessor
        self.modelContext = modelContext
    }
    
    /// Set the ModelContext to use for database operations
    /// - Parameter modelContext: The SwiftData ModelContext
    public func setModelContext(_ modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    /// Discover videos in a folder
    /// - Parameters:
    ///   - url: The folder URL to scan
    ///   - options: Configuration options for the discovery
    ///   - delegate: Delegate to receive progress updates
    /// - Returns: The result of the discovery operation
    public func discoverFolder(
        at url: URL,
        options: FolderDiscoveryOptions,
        delegate: FolderDiscoveryDelegate?
    ) async throws -> DiscoveryResult {
        let discoveryInterval = signposter.beginInterval("Folder Discovery", "url: \(url.lastPathComponent)")
        defer { signposter.endInterval("Folder Discovery", discoveryInterval) }
        
        // Reset cancellation state
        isCancelled = false
        
        var progress = DiscoveryProgress()
        let startTime = Date()
        
        // First pass: Count total folders and videos
       
       
        
        var foldersToProcess: [URL] = []
        var totalVideoCount = 0
        
       
            
    
        
        
        let videoCountInterval = signposter.beginInterval("Counting Videos")
        totalVideoCount = try await videoFinder.findVideoFiles(in: url, recursive: true).count
        signposter.endInterval("Counting Videos", videoCountInterval)
      
        
        // Update initial progress
        progress = DiscoveryProgress(
            totalFolders: foldersToProcess.count,
            totalVideos: totalVideoCount
        )
        delegate?.discoveryProgressDidUpdate(progress)
        
        // Process each folder
        var addedVideos: [Video] = []
        var updatedVideos: [Video] = []
        var removedVideos: [Video] = []
        var skippedVideos: [Video] = []
        var errors: [Error] = []
        let processedVideos: [Video]
        var createdFolders: [LibraryItem] = []
        
        // Process root folder first
        do {
           
            
            // Find videos in the current folder
            let findVideosInterval = signposter.beginInterval("Find Videos", "folder: \(url.lastPathComponent)")
            let videoURLs = try await videoFinder.findVideoFiles(
                in: url,
                recursive: false,
                progress: { currentFile async in
                    progress = DiscoveryProgress(
                        totalFolders: foldersToProcess.count + 1,
                        processedFolders: 0,
                        currentFolder: url.lastPathComponent,
                        totalVideos: totalVideoCount,
                        processedVideos: progress.processedVideos,
                        currentVideo: currentFile,
                        skippedFiles: progress.skippedFiles,
                        errorFiles: progress.errorFiles,
                        processingRate: Double(progress.processedVideos) / Date().timeIntervalSince(startTime)
                    )
                    await MainActor.run {
                        delegate?.discoveryProgressDidUpdate(progress)
                    }
                }
            )
            signposter.endInterval("Find Videos", findVideosInterval)
            progress.processedVideos = 0
            
            // Filter out videos that already exist in the database if we have a model context
            var filteredVideoURLs = videoURLs
            if let modelContext = modelContext {
                let filterInterval = signposter.beginInterval("Filter Existing Videos", "count: \(videoURLs.count)")
                filteredVideoURLs = await filterExistingVideos(urls: videoURLs, in: modelContext)
                signposter.endInterval("Filter Existing Videos", filterInterval, "filtered: \(videoURLs.count - filteredVideoURLs.count)")
                
                // Update skipped files count
                let skippedCount = videoURLs.count - filteredVideoURLs.count
                progress.skippedFiles += skippedCount
                delegate?.discoveryProgressDidUpdate(progress)
            }
            
            // Process videos with configured concurrency
            let processVideosInterval: OSSignpostIntervalState = signposter.beginInterval("Process Videos", "count: \(filteredVideoURLs.count)")
            
            if let modelContext = modelContext {
                // Use the version that creates folder structure
                let result = try await videoProcessor.processMultipleWithFolderStructure(
                    urls: filteredVideoURLs,
                    modelContext: modelContext,
                    minConcurrent: 2,
                    maxConcurrent: options.concurrentOperations,
                    progress: { [self] processedCount, currentVideo async in
                        progress = DiscoveryProgress(
                            totalFolders: foldersToProcess.count + 1,
                            processedFolders: 0,
                            currentFolder: url.lastPathComponent,
                            totalVideos: totalVideoCount,
                            processedVideos: processedCount,
                            currentVideo: currentVideo,
                            skippedFiles: progress.skippedFiles,
                            errorFiles: progress.errorFiles,
                            processingRate: Double(processedCount) / Date().timeIntervalSince(startTime),
                            estimatedTimeRemaining: estimateTimeRemaining(
                                processed: processedCount,
                                total: totalVideoCount,
                                startTime: startTime
                            )
                        )
                        await MainActor.run {
                            delegate?.discoveryProgressDidUpdate(progress)
                        }
                    }
                )
                processedVideos = result.videos
                createdFolders = result.folders
            } else {
                // Use the standard version without folder structure creation
                processedVideos = try await videoProcessor.processMultiple(
                    urls: filteredVideoURLs,
                    minConcurrent: 2,
                    maxConcurrent: options.concurrentOperations,
                    progress: { [self] processedCount, currentVideo async in
                        progress = DiscoveryProgress(
                            totalFolders: foldersToProcess.count + 1,
                            processedFolders: 0,
                            currentFolder: url.lastPathComponent,
                            totalVideos: totalVideoCount,
                            processedVideos: processedCount,
                            currentVideo: currentVideo,
                            skippedFiles: progress.skippedFiles,
                            errorFiles: progress.errorFiles,
                            processingRate: Double(processedCount) / Date().timeIntervalSince(startTime),
                            estimatedTimeRemaining: estimateTimeRemaining(
                                processed: processedCount,
                                total: totalVideoCount,
                                startTime: startTime
                            )
                        )
                        await MainActor.run {
                            delegate?.discoveryProgressDidUpdate(progress)
                        }
                    }
                )
            }
            signposter.endInterval("Process Videos", processVideosInterval, "processed: \(processedVideos.count)")
            
            progress.processedVideos = 0

         
            addedVideos.append(contentsOf: processedVideos)
  
            
        } catch {
            errors.append(error)
            delegate?.discoveryDidEncounterError(error)
        }
       
      
     //   signposter.endInterval("Folder Discovery", discoveryInterval)

        let statistics = DiscoveryStatistics(
            totalFoldersScanned: progress.processedFolders,
            totalVideosFound: totalVideoCount,
            totalVideosProcessed: progress.processedVideos,
            skippedFiles: progress.skippedFiles,
            errorFiles: progress.errorFiles,
            totalProcessingTime: Date().timeIntervalSince(startTime),
            averageProcessingRate: progress.processingRate
        )

        
        let result = DiscoveryResult(
            addedVideos: addedVideos,
            updatedVideos: updatedVideos,
            removedVideos: removedVideos,
            createdFolders: createdFolders,
            errors: errors,
            statistics: statistics
        )
        
        delegate?.discoveryDidComplete(result: result)
        return result
    }
    
    /// Check if thumbnails need to be regenerated for a folder
    /// - Parameter url: The folder URL to check
    /// - Returns: Array of videos that need thumbnail regeneration
    public func checkThumbnails(at url: URL) async throws -> [Video] {
        let interval = signposter.beginInterval("Check Thumbnails")
        defer { signposter.endInterval("Check Thumbnails", interval) }
        
        let videos = try await videoFinder.findVideoFiles(in: url, recursive: true)
        return try await withThrowingTaskGroup(of: Video?.self) { group in
            for videoURL in videos {
                group.addTask {
                    let video = try await Video(url: videoURL)
                    guard let thumbnailURL = video.thumbnailURL else { return video }
                    return FileManager.default.fileExists(atPath: thumbnailURL.path) ? nil : video
                }
            }
            
            var result: [Video] = []
            for try await video in group {
                if let video = video {
                    result.append(video)
                }
            }
            return result
        }
    }
    
    /// Regenerate thumbnails for specific videos
    /// - Parameters:
    ///   - videos: Array of videos needing thumbnail regeneration
    ///   - delegate: Delegate to receive progress updates
    public func regenerateThumbnails(
        for videos: [Video],
        delegate: FolderDiscoveryDelegate?
    ) async throws {
        let interval = signposter.beginInterval("Regenerate Thumbnails")
        defer { signposter.endInterval("Regenerate Thumbnails", interval) }
        
        var progress = DiscoveryProgress(totalVideos: videos.count)
        delegate?.discoveryProgressDidUpdate(progress)
        
        let startTime = Date()
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, video) in videos.enumerated() {
                if isCancelled {
                    delegate?.discoveryDidCancel()
                    return
                }
                
                group.addTask {
                    try await self.videoProcessor.generateThumbnail(for: video, size: .init(width: 160, height: 90))
                }
                
                progress = DiscoveryProgress(
                    totalVideos: videos.count,
                    processedVideos: index + 1,
                    currentVideo: video.title,
                    processingRate: Double(index + 1) / Date().timeIntervalSince(startTime),
                    estimatedTimeRemaining: estimateTimeRemaining(
                        processed: index + 1,
                        total: videos.count,
                        startTime: startTime
                    )
                )
                delegate?.discoveryProgressDidUpdate(progress)
            }
            
            try await group.waitForAll()
        }
    }
    
    /// Discover videos matching smart folder criteria
    public func discoverSmartFolder(
        options: SmartFolderDiscoveryOptions,
        delegate: FolderDiscoveryDelegate?
    ) async throws -> DiscoveryResult {
        let interval = signposter.beginInterval("Smart Folder Discovery")
        defer { signposter.endInterval("Smart Folder Discovery", interval) }
        
        // Reset cancellation state
        isCancelled = false
        
        var progress = DiscoveryProgress()
        let startTime = Date()
        
        // Check cache for existing results if this is an update
        let cacheKey = options.criteria.cacheKey
        var previousResults: [URL] = []
        if options.isUpdate {
            previousResults = smartFolderCache[cacheKey] ?? []
        }
        
        // Find matching videos
        let matchingURLs = try await videoFinder.findVideos(matching: options.criteria)
        smartFolderCache[cacheKey] = matchingURLs
        
        // Determine which videos are new, updated, or removed
        let newURLs = Set(matchingURLs).subtracting(previousResults)
        let removedURLs = Set(previousResults).subtracting(matchingURLs)
        
        progress = DiscoveryProgress(totalVideos: newURLs.count)
        delegate?.discoveryProgressDidUpdate(progress)
        
        // Process new videos
        var addedVideos: [Video] = []
        var removedVideos: [Video] = []
        var errors: [Error] = []
        
        // Process new videos concurrently
        try await withThrowingTaskGroup(of: Video?.self) { group in
            for url in newURLs {
                if isCancelled {
                    delegate?.discoveryDidCancel()
                    throw DiscoveryError.cancelled
                }
                
                group.addTask {
                    do {
                        let video = try await self.videoProcessor.process(url: url)
                        if options.generateThumbnails {
                            try await self.videoProcessor.generateThumbnail(
                                for: video,
                                size: CGSize(width: 160, height: 90)
                            )
                        }
                        return video
                    } catch {
                        self.logger.error("Failed to process video at \(url.path): \(error)")
                        return nil
                    }
                }
            }
            
            var processedCount = 0
            for try await video in group {
                processedCount += 1
                if let video = video {
                    addedVideos.append(video)
                } else {
                    errors.append(DiscoveryError.processingFailed(NSError(domain: "com.hypermovie", code: -1)))
                }
                
                progress = DiscoveryProgress(
                    totalVideos: newURLs.count,
                    processedVideos: processedCount,
                    currentVideo: video?.title ?? "",
                    errorFiles: errors.count,
                    processingRate: Double(processedCount) / Date().timeIntervalSince(startTime),
                    estimatedTimeRemaining: estimateTimeRemaining(
                        processed: processedCount,
                        total: newURLs.count,
                        startTime: startTime
                    )
                )
                delegate?.discoveryProgressDidUpdate(progress)
            }
        }
        
        // Process removed videos
        try await withThrowingTaskGroup(of: Video?.self) { group in
            for url in removedURLs {
                group.addTask {
                    try await Video(url: url)
                }
            }
            
            for try await video in group {
                if let video = video {
                    removedVideos.append(video)
                }
            }
        }
        
        let statistics = DiscoveryStatistics(
            totalFoldersScanned: 1, // Smart folders don't scan folders directly
            totalVideosFound: matchingURLs.count,
            totalVideosProcessed: addedVideos.count,
            skippedFiles: previousResults.count - removedVideos.count,
            errorFiles: errors.count,
            totalProcessingTime: Date().timeIntervalSince(startTime),
            averageProcessingRate: progress.processingRate
        )
        
        let result = DiscoveryResult(
            addedVideos: addedVideos,
            updatedVideos: [],
            removedVideos: removedVideos,
            createdFolders: [],
            errors: errors,
            statistics: statistics
        )
        
        delegate?.discoveryDidComplete(result: result)
        return result
    }
    
    /// Cancel the current discovery operation
    public func cancelDiscovery() {
        isCancelled = true
        currentTask?.cancel()
    }
    
    // MARK: - Private Methods
    
    /// Filter out videos that already exist in the database
    /// - Parameters:
    ///   - urls: Array of video URLs to check
    ///   - modelContext: The SwiftData ModelContext to use
    /// - Returns: Array of video URLs that don't exist in the database
    @available(macOS 15, *)
    private func filterExistingVideos(urls: [URL], in modelContext: ModelContext) async -> [URL] {
        let interval = signposter.beginInterval("Filter Existing Videos", "count: \(urls.count)")
        defer { signposter.endInterval("Filter Existing Videos", interval) }
        
        return await withTaskGroup(of: (URL, Bool).self) { group in
            for url in urls {
                group.addTask {
                    let fetchInterval = self.signposter.beginInterval("Fetch Video", "url: \(url.lastPathComponent)")
                    var descriptor = FetchDescriptor<Video>(
                        predicate: #Predicate<Video> { video in
                            video.url == url
                        }
                    )
                    descriptor.fetchLimit = 1
                    
                    do {
                        let existingVideos = try modelContext.fetch(descriptor)
                        self.signposter.endInterval("Fetch Video", fetchInterval, "exists: \(!existingVideos.isEmpty)")
                        return (url, existingVideos.isEmpty)
                    } catch {
                        self.logger.error("Error checking if video exists: \(error)")
                        self.signposter.endInterval("Fetch Video", fetchInterval, "error: true")
                        return (url, true) // Assume it doesn't exist if there's an error
                    }
                }
            }
            
            var result: [URL] = []
            for await (url, isNew) in group {
                if isNew {
                    result.append(url)
                }
            }
            return result
        }
    }
    
    /// Estimate the remaining time for a processing operation
    /// - Parameters:
    ///   - processed: Number of items processed so far
    ///   - total: Total number of items to process
    ///   - startTime: When the processing started
    /// - Returns: Estimated time remaining in seconds, or nil if not enough data
    private func estimateTimeRemaining(processed: Int, total: Int, startTime: Date) -> TimeInterval? {
        guard processed > 0, total > processed else { return nil }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let timePerItem = elapsedTime / Double(processed)
        let remainingItems = total - processed
        return timePerItem * Double(remainingItems)
    }
}

/// Errors that can occur during discovery
public enum DiscoveryError: LocalizedError {
    case cancelled
    case invalidFolder(URL)
    case accessDenied(URL)
    case processingFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Discovery operation was cancelled"
        case .invalidFolder(let url):
            return "Invalid folder at path: \(url.path)"
        case .accessDenied(let url):
            return "Access denied to folder: \(url.path)"
        case .processingFailed(let error):
            return "Failed to process videos: \(error.localizedDescription)"
        }
    }
}

// MARK: - Smart Folder Cache Key Generation
@available(macOS 15, *)
private extension SmartFolderCriteria {
    var cacheKey: String {
        var components: [String] = []
        
        if let nameFilter = nameFilter {
            components.append("name:\(nameFilter)")
        }
        
        if let minSize = minSize {
            components.append("minSize:\(minSize)")
        }
        
        if let maxSize = maxSize {
            components.append("maxSize:\(maxSize)")
        }
        
        return components.joined(separator: "|")
    }
    
    func matches(_ video: Video) -> Bool {
        // Name filter
        if let nameFilter = nameFilter {
            guard nameFilter.contains(where: { filter in
                video.title.contains(filter)
            }) else { return false }
        }
        
        // Size filters
        if let minSize = minSize {
            guard let fileSize = video.fileSize, fileSize >= minSize else { return false }
        }
        
        if let maxSize = maxSize {
            guard let fileSize = video.fileSize, fileSize <= maxSize else { return false }
        }
        
        return true
    }
} 
