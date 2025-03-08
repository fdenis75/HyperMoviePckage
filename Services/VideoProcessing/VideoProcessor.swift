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
        
        let video = try await process(url: url)
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
        
        let videos = try await processMultiple(
            urls: urls,
            minConcurrent: minConcurrent,
            maxConcurrent: maxConcurrent,
            progress: progress
        )
        
        let folderInterval = signposter.beginInterval("Create Folder Structure", "videos: \(videos.count)")
        var allFolders: [HyperMovieModels.LibraryItem] = []
        for video in videos {
            let folders = video.createFolderStructure(in: modelContext)
            for folder in folders {
                if !allFolders.contains(where: { $0.id == folder.id }) {
                    allFolders.append(folder)
                }
            }
        }
        signposter.endInterval("Create Folder Structure", folderInterval, "folders: \(allFolders.count)")
        
        return (videos, allFolders)
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
        progress: ((Int, String) async -> Void)? = nil
    ) async throws -> [Video] {
        let batchInterval = signposter.beginInterval("Process Multiple Videos", "count: \(urls.count)")
        defer { signposter.endInterval("Process Multiple Videos", batchInterval, "completed: true") }
        
        logger.info("Starting batch processing of \(urls.count) videos with \(maxConcurrent) concurrent tasks")
        
        return try await withThrowingTaskGroup(of: Video.self) { group in
            var videos: [Video] = []
            videos.reserveCapacity(urls.count)
            
            var processedCount = 0
            let batchSize = 10 // Process in batches of 10
            let concurrentTasks = min(max(minConcurrent, maxConcurrent), 16) // Use provided concurrency with bounds
            
            while processedCount < urls.count {
                // Process next batch
                let start = processedCount
                let end = min(start + batchSize, urls.count)
                let currentBatch = urls[start..<end]
                
                let batchProcessInterval = signposter.beginInterval("Process Batch", "batch: \(processedCount/batchSize + 1), size: \(currentBatch.count)")
                
                // Create a semaphore with provided concurrency
                let semaphore = DispatchSemaphore(value: concurrentTasks)
                
                for url in currentBatch {
                    guard processingTasks[url] == nil else { continue }
                    
                    group.addTask {
                        semaphore.wait()
                        defer { semaphore.signal() }
                        
                        do {
                            let videoInterval = self.signposter.beginInterval("Process Single Video", "url: \(url.lastPathComponent)")
                            self.logger.debug("✅ start processing video: \(url.lastPathComponent)")
                            
                            await progress?(processedCount + 1, url.lastPathComponent)
                            // Initialize video without generating thumbnail
                            let video = try await Video(url: url)
                            self.logger.debug("✅ Processed video: \(url.lastPathComponent)")
                            
                            self.signposter.endInterval("Process Single Video", videoInterval, "success: true")
                            return video
                        } catch {
                            self.logger.error("❌ Failed to process video \(url.lastPathComponent): \(error.localizedDescription)")
                            self.signposter.endInterval("Process Single Video", self.signposter.beginInterval("Process Single Video"), "error: true")
                            throw error
                        }
                    }
                }
                
                // Collect results from current batch
                for try await video in group {
                    videos.append(video)
                }
                
                processedCount = end
                signposter.endInterval("Process Batch", batchProcessInterval, "completed: \(currentBatch.count)")
            }
            
            logger.info("✅ Completed processing \(videos.count) videos")
            return videos
        }
    }
    
    // MARK: - Private Methods
    
    private func clearStaleFiles() {
        // Optional: Implement cleanup of old thumbnails
        // This could remove thumbnails for videos that no longer exist
        // or implement a cache size limit
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
