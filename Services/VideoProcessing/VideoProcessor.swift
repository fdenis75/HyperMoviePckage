import Foundation
import AVFoundation
import CoreImage
import OSLog
import AppKit
import HyperMovieModels
import HyperMovieCore
import Darwin
import SwiftData

/// A service that handles video processing operations.
@available(macOS 15, *)
public actor VideoProcessor: VideoProcessing {

    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "video-processing")
    private let signposter = OSSignposter(subsystem: "com.hypermovie", category: "video-processing-performance")
    private let processingQueue = DispatchQueue(label: "com.hypermovie.video-processing", qos: .userInitiated)
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    
    private var processingTasks: [URL: Task<Video, Error>] = [:]
    private var thumbnailCache: [URL: URL] = [:]
    
    private let config: ProcessingConfiguration
    private let thumbnailDirectory: URL
    
    // MARK: - Initialization
    
    public init(config: ProcessingConfiguration = .default) {
        self.config = config
        
        // Setup thumbnail directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.thumbnailDirectory = appSupport.appendingPathComponent("HyperMovie/Thumbnails", isDirectory: true)
        
        // Create thumbnail directory if it doesn't exist
        try? FileManager.default.createDirectory(at: thumbnailDirectory, 
                                               withIntermediateDirectories: true)
    }
    
    // MARK: - VideoProcessing
    
    public func process(url: URL) async throws -> Video {
        let processInterval = signposter.beginInterval("Process Video", "url: \(url.lastPathComponent)")
        defer { signposter.endInterval("Process Video", processInterval) }
        
        if let existingTask = processingTasks[url] {
            return try await existingTask.value
        }
        
        let task = Task {
            logger.info("Processing video at \(url.path)")
            
            // Create video object - it will handle its own metadata and thumbnail generation
            let videoInitInterval = signposter.beginInterval("Video Initialization", "url: \(url.lastPathComponent)")
            let video = try await Video(url: url)
            signposter.endInterval("Video Initialization", videoInitInterval)
            
            logger.info("Completed processing for \(url.path)")
            return video
        }
        
        processingTasks[url] = task
        defer { processingTasks[url] = nil }
        
        return try await task.value
    }
    
    /// Process a video and create folder structure in the database
    /// - Parameters:
    ///   - url: The URL of the video to process
    ///   - modelContext: The SwiftData ModelContext to use for creating LibraryItems
    /// - Returns: The processed Video object and created LibraryItems
    @available(macOS 15, *)
    public func processWithFolderStructure(url: URL, modelContext: ModelContext) async throws -> (video: Video, folders: [HyperMovieModels.LibraryItem]) {
        let structureInterval = signposter.beginInterval("Process With Folder Structure", "url: \(url.lastPathComponent)")
        defer { signposter.endInterval("Process With Folder Structure", structureInterval) }
        
        // Create video with modelContext to create folder structure during initialization
        let video = try await Video(url: url, modelContext: modelContext)
        
        // Get the folders that were created during initialization
        let folders = video.createFolderStructure(in: modelContext)
        return (video, folders)
    }
    
    /// Process multiple videos and create folder structure in the database
    /// - Parameters:
    ///   - urls: The URLs of the videos to process
    ///   - modelContext: The SwiftData ModelContext to use for creating LibraryItems
    ///   - minConcurrent: Minimum number of concurrent operations
    ///   - maxConcurrent: Maximum number of concurrent operations
    ///   - progress: Optional closure for reporting progress
    /// - Returns: Tuple containing processed videos and created LibraryItems
    @available(macOS 15, *)
    public func processMultipleWithFolderStructure(
        urls: [URL],
        modelContext: ModelContext,
        minConcurrent: Int = 2,
        maxConcurrent: Int = 8,
        progress: ((Int, String) async -> Void)? = nil
    ) async throws -> (videos: [Video], folders: [HyperMovieModels.LibraryItem]) {
        let batchInterval = signposter.beginInterval("Process Multiple With Folder Structure", "count: \(urls.count)")
        defer { signposter.endInterval("Process Multiple With Folder Structure", batchInterval) }
        
        // Create a safe progress handler that catches errors
        let safeProgress: ((Int, String) async -> Void)? = progress != nil ? { index, message in
            do {
                self.logger.debug("🔍 DEBUG: Safe progress handler called with index: \(index), message: \(message)")
                if let progressHandler = progress {
                    try await progressHandler(index, message)
                    self.logger.debug("🔍 DEBUG: Safe progress handler completed successfully")
                }
            } catch {
                self.logger.error("❌ ERROR: Progress handler threw an error: \(error.localizedDescription)")
                // Continue execution despite the error
            }
        } : nil
        
        logger.info("🔍 DEBUG: Starting batch processing of \(urls.count) videos with folder structure")
        
        // Process in batches of 100 URLs
        let batchSize = 100
        
        // Store all processed videos directly
        var allVideos: [Video] = []
        var allFolders: [HyperMovieModels.LibraryItem] = []
        var processedCount = 0
        
        // Track memory usage
        var lastMemoryReport = Date()
        let memoryReportInterval: TimeInterval = 10 // Report memory usage every 10 seconds
        
        // Track unique folder paths to avoid duplicate processing
        var processedFolderPaths = Set<String>()
        
        // Split URLs into batches of 100
        for batchStart in stride(from: 0, to: urls.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, urls.count)
            let urlBatch = Array(urls[batchStart..<batchEnd])
            
            // Report memory usage periodically
            if Date().timeIntervalSince(lastMemoryReport) >= memoryReportInterval {
                reportMemoryUsage()
                lastMemoryReport = Date()
            }
            
            logger.info("🔍 DEBUG: Starting batch \(batchStart/batchSize + 1) with \(urlBatch.count) videos")
            let batchProcessInterval = signposter.beginInterval("Process URL Batch", "batch: \(batchStart/batchSize + 1), size: \(urlBatch.count)")
            
            // Create a batch-specific progress handler that maintains the global count
            let batchProgress: ((Int, String) async -> Void)? = safeProgress != nil ? { index, message in
                // Calculate the global index by adding the batch start offset
                let globalIndex = batchStart + index
                self.logger.debug("🔍 DEBUG: Batch progress handler: local index \(index), global index \(globalIndex), message: \(message)")
                
                // Only forward progress if it's within the valid range
                if globalIndex <= urls.count {
                    if let progressHandler = safeProgress {
                        await progressHandler(globalIndex, message)
                    }
                } else {
                    self.logger.warning("⚠️ WARNING: Progress index \(globalIndex) exceeds total count \(urls.count)")
                }
            } : nil
            
            // Group URLs by their parent folder to avoid duplicate folder creation
            var urlsByFolder: [String: [URL]] = [:]
            
            // Group videos by their parent folder
            for url in urlBatch {
                let folderPath = url.deletingLastPathComponent().path
                if var folderUrls = urlsByFolder[folderPath] {
                    folderUrls.append(url)
                    urlsByFolder[folderPath] = folderUrls
                } else {
                    urlsByFolder[folderPath] = [url]
                }
            }
            
            // Process videos folder by folder
            var batchVideos: [Video] = []
            
            for (folderPath, folderUrls) in urlsByFolder {
                // Skip if this folder has already been processed
                if processedFolderPaths.contains(folderPath) {
                    logger.debug("🔍 DEBUG: Skipping already processed folder: \(folderPath)")
                    
                    // Process videos without creating folder structure
                    let folderVideos = try await processMultiple(
                        urls: folderUrls,
                        minConcurrent: minConcurrent,
                        maxConcurrent: maxConcurrent,
                        progress: batchProgress,
                        modelContext: modelContext
                    )
                    
                    batchVideos.append(contentsOf: folderVideos)
                    continue
                }
                
                // Mark this folder as processed
                processedFolderPaths.insert(folderPath)
                
                // Process the first video with folder structure creation
                if let firstUrl = folderUrls.first {
                    logger.debug("🔍 DEBUG: Processing first video with folder structure: \(firstUrl.lastPathComponent)")
                    let result = try await processWithFolderStructure(url: firstUrl, modelContext: modelContext)
                    batchVideos.append(result.video)
                    
                    // Add new folders to the collection
                    for folder in result.folders {
                        if !allFolders.contains(where: { $0.id == folder.id }) {
                            allFolders.append(folder)
                        }
                    }
                    
                    // Process remaining videos without folder structure
                    if folderUrls.count > 1 {
                        let remainingUrls = Array(folderUrls.dropFirst())
                        logger.debug("🔍 DEBUG: Processing \(remainingUrls.count) remaining videos in folder")
                        let remainingVideos = try await processMultiple(
                            urls: remainingUrls,
                            minConcurrent: minConcurrent,
                            maxConcurrent: maxConcurrent,
                            progress: batchProgress
                        )
                        batchVideos.append(contentsOf: remainingVideos)
                    }
                }
            }
            
            // Save the model context after each batch
            logger.info("🔍 DEBUG: Saving model context after batch \(batchStart/batchSize + 1)")
            do {
                try modelContext.save()
                logger.debug("🔍 DEBUG: Model context saved successfully")
            } catch {
                logger.error("❌ ERROR: Failed to save model context: \(error.localizedDescription)")
                throw error
            }
            
            // Add videos from this batch to the overall collection
            logger.info("🔍 DEBUG: Adding \(batchVideos.count) videos to collection")
            allVideos.append(contentsOf: batchVideos)
            processedCount += urlBatch.count
            
            // Report progress for the entire batch
            logger.info("🔍 DEBUG: Reporting batch completion progress: \(processedCount)/\(urls.count)")
            if let progressHandler = safeProgress {
                await progressHandler(processedCount, "Completed batch \(batchStart/batchSize + 1)")
            } else {
                logger.debug("🔍 DEBUG: No progress handler provided for batch completion")
            }
            
            logger.info("Completed batch \(batchStart/batchSize + 1): \(processedCount)/\(urls.count) videos processed")
            signposter.endInterval("Process URL Batch", batchProcessInterval, "completed: \(urlBatch.count)")
            
            // Explicitly clear temporary collections to free memory
            autoreleasepool {
                batchVideos.removeAll(keepingCapacity: false)
                urlsByFolder.removeAll(keepingCapacity: false)
                
                // Clear thumbnail cache periodically to prevent unbounded growth
                if batchStart % (batchSize * 5) == 0 {
                    self.thumbnailCache.removeAll(keepingCapacity: true)
                }
            }
        }
        
        // Final memory report
        reportMemoryUsage()
        
        logger.info("✅ Completed processing all \(allVideos.count) videos with \(allFolders.count) folders")
        return (allVideos, allFolders)
    }
    
    public func extractMetadata(for video: Video) async throws {
        let metadataInterval = signposter.beginInterval("Extract Metadata", "video: \(video.title)")
        defer { signposter.endInterval("Extract Metadata", metadataInterval) }
        
        logger.info("Extracting metadata for \(video.url.path)")
        
        let asset = AVURLAsset(url: video.url)
        
        // Load duration
        let durationInterval = signposter.beginInterval("Load Duration")
        let duration = try await asset.load(.duration).seconds
        signposter.endInterval("Load Duration", durationInterval)
        
        // Load video track properties
        let trackInterval = signposter.beginInterval("Load Video Track")
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let dimensions = try await track.load(.naturalSize)
            let frameRate = try await Float(track.load(.nominalFrameRate))
            
            // Update video properties
            await MainActor.run {
                video.duration = duration
                video.resolution = dimensions
                video.frameRate = Float64(frameRate)
            }
            
            // Load format descriptions
            let formatInterval = signposter.beginInterval("Load Format Descriptions")
            let descriptions = try await track.load(.formatDescriptions)
            if let formatDesc = descriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                await MainActor.run {
                    video.metadata.codec = String(describing: mediaSubType)
                }
            }
            signposter.endInterval("Load Format Descriptions", formatInterval)
        } else {
            throw VideoError.videoTrackNotFound(video.url)
        }
        signposter.endInterval("Load Video Track", trackInterval)
        
        logger.info("Completed metadata extraction for \(video.url.path)")
    }
    
    public func generateThumbnail(for video: Video, size: CGSize) async throws -> URL {
        let thumbnailInterval = signposter.beginInterval("Generate Thumbnail", "video: \(video.title)")
        defer { signposter.endInterval("Generate Thumbnail", thumbnailInterval) }
        
        logger.info("Generating thumbnail for \(video.url.path)")
        
        // Check if thumbnail already exists in persistent storage
        let thumbnailFileName = video.id.uuidString + "_thumb." + config.format.rawValue
        let persistentURL = thumbnailDirectory.appendingPathComponent(thumbnailFileName)
        
        if FileManager.default.fileExists(atPath: persistentURL.path) {
            thumbnailCache[video.url] = persistentURL
            return persistentURL
        }
        
        let asset = AVURLAsset(url: video.url)
        let duration = try await asset.load(.duration)
        let time = CMTime(seconds: duration.seconds * 0.1, preferredTimescale: 600)
        
        let generator = AVAssetImageGenerator(asset: asset)
       // generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = config.useAccurateTimestamps ? .zero : .positiveInfinity
        generator.requestedTimeToleranceAfter = config.useAccurateTimestamps ? .zero : .positiveInfinity
        generator.maximumSize = size
        
        let imageGenInterval = signposter.beginInterval("Generate Image")
        let cgImage = try await generator.image(at: time).image
        let nsImage = NSImage(cgImage: cgImage, size: size)
        signposter.endInterval("Generate Image", imageGenInterval)
        
        let compressionInterval = signposter.beginInterval("Compress Image")
        let data: Data?
        switch config.format {
        case .jpeg:
            data = nsImage.jpegData(compressionQuality: config.compressionQuality)
        case .png:
            data = nsImage.pngData()
        case .heif:
            data = nsImage.jpegData(compressionQuality: config.compressionQuality)
        }
        
        guard let imageData = data else {
            throw VideoError.processingFailed(persistentURL, NSError(domain: "com.hypermovie", code: -1))
        }
        
        try imageData.write(to: persistentURL)
        signposter.endInterval("Compress Image", compressionInterval)
        
        thumbnailCache[video.url] = persistentURL
        
        logger.info("Completed thumbnail generation for \(video.url.path)")
        return persistentURL
    }
    
    public func cancelAllOperations() {
        logger.info("Cancelling all video processing operations")
        processingTasks.values.forEach { $0.cancel() }
        processingTasks.removeAll()
        thumbnailCache.removeAll()
    }
    
    public func getCurrentMetrics() -> ProcessingMetrics {
        let metricsInterval = signposter.beginInterval("Get System Metrics")
        defer { signposter.endInterval("Get System Metrics", metricsInterval) }
        
        // Get host port for statistics
        let host = mach_host_self()
        var hostSize = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var cpuLoadInfo = host_cpu_load_info()
        
        // Get CPU usage
        let _ = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(hostSize)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &hostSize)
            }
        }
        
        let totalTicks = Double(cpuLoadInfo.cpu_ticks.0 + cpuLoadInfo.cpu_ticks.1 + cpuLoadInfo.cpu_ticks.2 + cpuLoadInfo.cpu_ticks.3)
        let idleTicks = Double(cpuLoadInfo.cpu_ticks.3)
        let cpuUsage = 1.0 - (idleTicks / totalTicks)
        
        // Get memory statistics
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let _ = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &size)
            }
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let memoryAvailable = UInt64(stats.free_count) * pageSize
        
        // Get disk I/O pressure (simplified)
        var diskPressure = 0.0
        if let fsStats = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            let totalSize = (fsStats[.systemSize] as? NSNumber)?.uint64Value ?? 0
            let freeSize = (fsStats[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
            diskPressure = 1.0 - (Double(freeSize) / Double(totalSize))
        }
        
        return ProcessingMetrics(
            cpuUsage: cpuUsage,
            memoryAvailable: memoryAvailable,
            diskIOPressure: diskPressure
        )
    }
    
    public func processMultiple(
        urls: [URL],
        minConcurrent: Int = 2,
        maxConcurrent: Int = 8,
        progress: ((Int, String) async -> Void)? = nil,
        modelContext: ModelContext? = nil
    ) async throws -> [Video] {
        let batchInterval = signposter.beginInterval("Process Multiple Videos", "count: \(urls.count)")
        defer { signposter.endInterval("Process Multiple Videos", batchInterval, "completed: true") }
        
        // Create a safe progress handler that catches errors
        let safeProgress: ((Int, String) async -> Void)? = progress != nil ? { index, message in
            do {
                self.logger.debug("🔍 DEBUG: Safe inner progress handler called with index: \(index), message: \(message)")
                if let progressHandler = progress {
                    await progressHandler(index, message)
                    self.logger.debug("🔍 DEBUG: Safe inner progress handler completed successfully")
                }
            } catch {
                self.logger.error("❌ ERROR: Inner progress handler threw an error: \(error.localizedDescription)")
                // Continue execution despite the error
            }
        } : nil
        
        logger.info("🔍 DEBUG: Starting processMultiple with \(urls.count) videos, concurrency: \(maxConcurrent)")
        
        return try await withThrowingTaskGroup(of: (Int, Video).self) { group in
            var videos: [Video] = []
            videos.reserveCapacity(urls.count)
            
            var processedCount = 0
            let batchSize = 10 // Process in batches of 10
            let concurrentTasks = min(max(minConcurrent, maxConcurrent), 16) // Use provided concurrency with bounds
            
            // Create a semaphore with provided concurrency
            logger.debug("🔍 DEBUG: Creating semaphore with value \(concurrentTasks)")
            let semaphore = DispatchSemaphore(value: concurrentTasks)
            
            while processedCount < urls.count {
                // Process next batch
                let start = processedCount
                let end = min(start + batchSize, urls.count)
                let currentBatch = urls[start..<end]
                
                logger.info("🔍 DEBUG: Processing inner batch \(processedCount/batchSize + 1), size: \(currentBatch.count)")
                let batchProcessInterval = signposter.beginInterval("Process Batch", "batch: \(processedCount/batchSize + 1), size: \(currentBatch.count)")
                
                // Add tasks for this batch
                logger.debug("🔍 DEBUG: Adding \(currentBatch.count) tasks to task group")
                for (index, url) in currentBatch.enumerated() {
                    let localIndex = index + 1 // 1-based index for this batch
                    guard processingTasks[url] == nil else {
                        logger.debug("🔍 DEBUG: Skipping URL that's already being processed: \(url.lastPathComponent)")
                        continue
                    }
                    
                    logger.debug("🔍 DEBUG: Adding task for URL: \(url.lastPathComponent), index: \(localIndex)")
                    group.addTask {
                        self.logger.debug("🔍 DEBUG: Task started for URL: \(url.lastPathComponent), waiting on semaphore")
                        semaphore.wait()
                        defer {
                            self.logger.debug("🔍 DEBUG: Signaling semaphore for URL: \(url.lastPathComponent)")
                            semaphore.signal()
                        }
                        
                        do {
                            let videoInterval = self.signposter.beginInterval("Process Single Video", "url: \(url.lastPathComponent)")
                            self.logger.debug("🔍 DEBUG: Processing video: \(url.lastPathComponent)")
                            
                            // Report progress safely
                            if let progressHandler = safeProgress {
                                self.logger.debug("🔍 DEBUG: Reporting progress for URL: \(url.lastPathComponent), index: \(localIndex)")
                                await progressHandler(localIndex, url.lastPathComponent)
                            } else {
                                self.logger.debug("🔍 DEBUG: No progress handler provided for URL: \(url.lastPathComponent)")
                            }
                            
                            // Initialize video without generating thumbnail
                            self.logger.debug("🔍 DEBUG: Creating Video object for URL: \(url.lastPathComponent)")
                            let video = try await Video(url: url, modelContext: modelContext)
                            self.logger.debug("✅ Processed video successfully: \(url.lastPathComponent)")
                            
                            self.signposter.endInterval("Process Single Video", videoInterval, "success: true")
                            return (index, video)
                        } catch {
                            self.logger.error("❌ ERROR: Failed to process video \(url.lastPathComponent): \(error.localizedDescription)")
                            self.signposter.endInterval("Process Single Video", self.signposter.beginInterval("Process Single Video"), "error: true")
                            throw error
                        }
                    }
                }
                
                // Collect results from current batch
                logger.debug("🔍 DEBUG: Collecting results from task group")
                for try await (index, video) in group {
                    logger.debug("🔍 DEBUG: Received result for index: \(index), video: \(video.title)")
                    videos.append(video)
                    
                    // Report progress for each completed video
                    if let progressHandler = safeProgress {
                        let completedCount = videos.count
                        logger.debug("🔍 DEBUG: Reporting completion progress for video: \(video.title), count: \(completedCount)")
                        await progressHandler(completedCount, video.title)
                    }
                }
                
                processedCount = end
                logger.info("🔍 DEBUG: Completed inner batch \(processedCount/batchSize), processed: \(processedCount)/\(urls.count)")
                signposter.endInterval("Process Batch", batchProcessInterval, "completed: \(currentBatch.count)")
                
                // Report batch completion
                if let progressHandler = safeProgress {
                    logger.debug("🔍 DEBUG: Reporting batch completion: \(processedCount)/\(urls.count)")
                    await progressHandler(processedCount, "Completed batch \(processedCount/batchSize)")
                }
            }
            
            logger.info("✅ Completed processing all \(videos.count) videos")
            
            // Sort videos by index to maintain original order
            logger.debug("🔍 DEBUG: Sorting videos by title")
            return videos.sorted { $0.title < $1.title }
        }
    }
    
    // MARK: - Memory Management
    
    /// Reports the current memory usage of the application
    private func reportMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / (1024 * 1024)
            logger.info("📊 MEMORY: Current usage: \(String(format: "%.2f", usedMB)) MB")
        } else {
            logger.error("❌ ERROR: Failed to get memory usage information")
        }
    }
}

// MARK: - Private Extensions

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .png, properties: [:])
    }
    
    func jpegData(compressionQuality: Double = 0.8) -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, 
                                        properties: [.compressionFactor: compressionQuality])
    }
} 
