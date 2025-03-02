import Foundation
import AVFoundation
import CoreImage
import OSLog
import AppKit
import HyperMovieModels
import HyperMovieCore
import Darwin

/// A service that handles video processing operations.
@available(macOS 15, *)
public actor VideoProcessor: VideoProcessing {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "video-processing")
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
        if let existingTask = processingTasks[url] {
            return try await existingTask.value
        }
        
        let task = Task {
            logger.info("Processing video at \(url.path)")
            
            // Create video object - it will handle its own metadata and thumbnail generation
            let video = try await Video(url: url)
            
            logger.info("Completed processing for \(url.path)")
            return video
        }
        
        processingTasks[url] = task
        defer { processingTasks[url] = nil }
        
        return try await task.value
    }
    
    public func extractMetadata(for video: Video) async throws {
        logger.info("Extracting metadata for \(video.url.path)")
        
        let asset = AVURLAsset(url: video.url)
        
        // Load duration
        let duration = try await asset.load(.duration).seconds
        
        // Load video track properties
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
            let descriptions = try await track.load(.formatDescriptions)
            if let formatDesc = descriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                await MainActor.run {
                    video.metadata.codec = String(describing: mediaSubType)
                }
            }
        } else {
            throw VideoError.videoTrackNotFound(video.url)
        }
        
        logger.info("Completed metadata extraction for \(video.url.path)")
    }
    
    public func generateThumbnail(for video: Video, size: CGSize) async throws -> URL {
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
        
        let cgImage = try await generator.image(at: time).image
        let nsImage = NSImage(cgImage: cgImage, size: size)
        
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
    
    public func getCurrentMetrics() -> HyperMovieModels.ProcessingMetrics {
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
        
        return HyperMovieModels.ProcessingMetrics(
            cpuUsage: cpuUsage,
            memoryAvailable: memoryAvailable,
            diskIOPressure: diskPressure
        )
    }
    
    public func processMultiple(urls: [URL], minConcurrent: Int = 2, maxConcurrent: Int = 8) async throws -> [Video] {
        logger.info("Starting batch processing of \(urls.count) videos with 8 concurrent tasks")
        
        return try await withThrowingTaskGroup(of: Video.self) { group in
            var videos: [Video] = []
            videos.reserveCapacity(urls.count)
            
            var processedCount = 0
            let batchSize = 10 // Process in batches of 10
            let concurrentTasks = 8 // Fixed at 8 concurrent tasks
            
            while processedCount < urls.count {
                // Process next batch
                let start = processedCount
                let end = min(start + batchSize, urls.count)
                let currentBatch = urls[start..<end]
                
                // Create a semaphore with fixed concurrency
                let semaphore = DispatchSemaphore(value: concurrentTasks)
                
                for url in currentBatch {
                    guard processingTasks[url] == nil else { continue }
                    
                    group.addTask {
                        semaphore.wait()
                        defer { semaphore.signal() }
                        
                        do {
                            self.logger.debug("✅ start processing video: \(url.lastPathComponent)")
                            let video = try await Video(url: url)
                            self.logger.debug("✅ Processed video: \(url.lastPathComponent)")
                            return video
                        } catch {
                            self.logger.error("❌ Failed to process video \(url.lastPathComponent): \(error.localizedDescription)")
                            throw error
                        }
                    }
                }
                
                // Collect results from current batch
                for try await video in group {
                    videos.append(video)
                }
                
                processedCount = end
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
