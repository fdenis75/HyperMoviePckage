import Foundation
import AVFoundation
import CoreImage
import HyperMovieModels
import HyperMovieCore
import OSLog
import Metal
import VideoToolbox
import AppKit

/// A Metal-accelerated implementation of the MosaicGenerating protocol
@available(macOS 15, *)
public actor MetalMosaicGenerator: HyperMovieCore.MosaicGenerating {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "metal-mosaic-generator")
    private let metalProcessor: MetalImageProcessor
    private let layoutProcessor: LayoutProcessor
    private let signposter = OSSignposter()
    
    private var generationTasks: [UUID: Task<URL, Error>] = [:]
    private var frameCache: [UUID: [CMTime: CGImage]] = [:]
    private var progressHandlers: [UUID: (Double) -> Void] = [:]
    
    // Performance metrics
    private var lastGenerationTime: CFAbsoluteTime = 0
    private var totalGenerationTime: CFAbsoluteTime = 0
    private var generationCount: Int = 0
    
    // MARK: - Initialization
    
    /// Initialize a new Metal-accelerated mosaic generator
    /// - Parameter layoutProcessor: The layout processor to use
    public init(layoutProcessor: LayoutProcessor = LayoutProcessor()) throws {
        self.layoutProcessor = layoutProcessor
        
        do {
            self.metalProcessor = try MetalImageProcessor()
            logger.debug("✅ Metal mosaic generator initialized with Metal processor")
        } catch {
            logger.error("❌ Failed to initialize Metal processor: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - MosaicGenerating
    
    /// Generate a mosaic for a video using Metal acceleration
    /// - Parameters:
    ///   - video: The video to generate a mosaic for
    ///   - config: The configuration for mosaic generation
    /// - Returns: The URL of the generated mosaic image
    public func generate(for video: Video, config: MosaicConfiguration) async throws -> URL {
        logger.debug("🎯 Starting Metal-accelerated mosaic generation for video: \(video.title)")
        
        if let existingTask = generationTasks[video.id] {
            logger.debug("⚡️ Reusing existing task for video: \(video.id)")
            return try await existingTask.value
        }
        
        let task = Task<URL, Error> {
            let startTime = CFAbsoluteTimeGetCurrent()
            defer { trackPerformance(startTime: startTime) }
            
            do {
                logger.debug("📊 Video details - Duration: \(video.duration)s, Size: \(video.fileSize ?? 0) bytes")
                
                // Get video duration and calculate frame count
                let asset = AVURLAsset(url: video.url)
                let duration = try await asset.load(.duration).seconds
                let aspectRatio = try await calculateAspectRatio(from: asset)
                logger.debug("📐 Video aspect ratio: \(aspectRatio)")
                
                let frameCount = await layoutProcessor.calculateThumbnailCount(
                    duration: duration,
                    width: config.width,
                    density: config.density,
                    useAutoLayout: config.layout.useAutoLayout
                )
                logger.debug("🖼️ Calculated frame count: \(frameCount)")
                
                // Calculate layout
                let layout = await layoutProcessor.calculateLayout(
                    originalAspectRatio: aspectRatio,
                    thumbnailCount: frameCount,
                    mosaicWidth: config.width,
                    density: config.density,
                    useCustomLayout: config.layout.useCustomLayout,
                    useAutoLayout: config.layout.useAutoLayout
                )
                logger.debug("📏 Layout calculated - Size: \(layout.mosaicSize.width)x\(layout.mosaicSize.height), Thumbnails: \(layout.thumbCount)")
                
                // Extract frames using VideoToolbox for hardware acceleration
                progressHandlers[video.id]?(0.1)
                let frames = try await extractFramesWithVideoToolbox(
                    from: asset,
                    count: layout.thumbCount,
                    accurate: config.useAccurateTimestamps
                )
                logger.debug("🎞️ Extracted \(frames.count) frames using VideoToolbox")
                
                progressHandlers[video.id]?(0.5)
                
                // Generate mosaic using Metal
                let mosaic = try await metalProcessor.generateMosaic(
                    from: frames,
                    layout: layout,
                    metadata: VideoMetadata(
                        codec: video.metadata.codec,
                        bitrate: video.metadata.bitrate,
                        custom: video.metadata.custom
                    ),
                    config: config
                )
                logger.debug("🖼️ Metal mosaic created - Size: \(mosaic.width)x\(mosaic.height)")
                
                progressHandlers[video.id]?(0.8)
                
                // Save the mosaic to disk
                let mosaicURL = try await saveMosaic(
                    mosaic,
                    for: video,
                    config: config
                )
                logger.debug("💾 Saved mosaic to: \(mosaicURL.path)")
                
                progressHandlers[video.id]?(1.0)
                
                await MainActor.run {
                    video.mosaicURL = mosaicURL
                }
                
                return mosaicURL
            } catch {
                logger.error("❌ Metal mosaic generation failed: \(error.localizedDescription)")
                throw error
            }
        }
        
        generationTasks[video.id] = task
        defer {
            generationTasks[video.id] = nil
            progressHandlers[video.id] = nil
        }
        
        return try await task.value
    }
    
    /// Cancel mosaic generation for a specific video
    /// - Parameter video: The video to cancel mosaic generation for
    public func cancel(for video: Video) {
        logger.debug("❌ Cancelling Metal mosaic generation for: \(video.title)")
        generationTasks[video.id]?.cancel()
        generationTasks[video.id] = nil
        frameCache[video.id] = nil
    }
    
    /// Cancel all ongoing mosaic generation operations
    public func cancelAll() {
        logger.debug("❌ Cancelling all Metal mosaic generation tasks")
        generationTasks.values.forEach { $0.cancel() }
        generationTasks.removeAll()
        frameCache.removeAll()
    }
    
    /// Set a progress handler for a specific video
    /// - Parameters:
    ///   - video: The video to set the progress handler for
    ///   - handler: The progress handler
    public func setProgressHandler(for video: Video, handler: @escaping (Double) -> Void) {
        progressHandlers[video.id] = handler
    }
    
    /// Get performance metrics for the Metal mosaic generator
    /// - Returns: A dictionary of performance metrics
    public func getPerformanceMetrics() -> [String: Any] {
        var metrics: [String: Any] = [
            "averageGenerationTime": generationCount > 0 ? totalGenerationTime / Double(generationCount) : 0,
            "totalGenerationTime": totalGenerationTime,
            "generationCount": generationCount,
            "lastGenerationTime": lastGenerationTime
        ]
        
        // Add Metal processor metrics
        let metalMetrics = metalProcessor.getPerformanceMetrics()
        for (key, value) in metalMetrics {
            metrics["metal_\(key)"] = value
        }
        
        return metrics
    }
    
    // MARK: - Private Methods
    
    /// Extract frames from a video using VideoToolbox for hardware acceleration
    /// - Parameters:
    ///   - asset: The video asset to extract frames from
    ///   - count: The number of frames to extract
    ///   - accurate: Whether to use accurate timestamp extraction
    /// - Returns: Array of tuples containing frame images and their timestamps
    private func extractFramesWithVideoToolbox(
        from asset: AVAsset,
        count: Int,
        accurate: Bool
    ) async throws -> [(image: CGImage, timestamp: String)] {
        let state = signposter.beginInterval("Extract Frames VideoToolbox")
        defer { signposter.endInterval("Extract Frames VideoToolbox", state) }
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.debug("🎬 Starting VideoToolbox frame extraction - Count: \(count)")
        
        let duration = try await asset.load(.duration).seconds
        let times = calculateExtractionTimes(duration: duration, count: count)
        
        // Create a semaphore to limit concurrent operations
        let semaphore = DispatchSemaphore(value: 8)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        if accurate {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        } else {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        }
        
        return try await withThrowingTaskGroup(of: (Int, CGImage, String).self) { group in
            for (index, time) in times.enumerated() {
                group.addTask {
                    // Wait for semaphore
                    semaphore.wait()
                    defer { semaphore.signal() }
                    
                    // Extract the frame
                    let imageRef = try await generator.image(at: time)
                    
                    // Format timestamp
                   // let timestamp = await self.formatTimestamp(seconds: time.seconds)
                    
                    return (index, imageRef.image, await self.formatTimestamp(seconds: imageRef.actualTime.seconds))
                }
            }
            
            // Collect results in order
            var results: [(Int, CGImage, String)] = []
            for try await result in group {
                results.append(result)
            }
            let extractionTime = CFAbsoluteTimeGetCurrent() - startTime
            logger.debug("✅ VideoToolbox extraction complete - Extracted \(results.count) frames in \(extractionTime) seconds")
            return results.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
        }
    }
    
    /// Calculate evenly distributed extraction times for a video
    /// - Parameters:
    ///   - duration: The duration of the video in seconds
    ///   - count: The number of frames to extract
    /// - Returns: Array of CMTime values for frame extraction
    private func calculateExtractionTimes(duration: Double, count: Int) -> [CMTime] {
        let startPoint = duration * 0.05
        let endPoint = duration * 0.95
        let effectiveDuration = endPoint - startPoint
        
        let firstThirdCount = Int(Double(count) * 0.2)
        let middleCount = Int(Double(count) * 0.6)
        let lastThirdCount = count - firstThirdCount - middleCount
        
        let firstThirdEnd = startPoint + effectiveDuration * 0.33
        let lastThirdStart = startPoint + effectiveDuration * 0.67
        
        let firstThirdStep = (firstThirdEnd - startPoint) / Double(firstThirdCount)
        let middleStep = (lastThirdStart - firstThirdEnd) / Double(middleCount)
        let lastThirdStep = (endPoint - lastThirdStart) / Double(lastThirdCount)
        
        let firstThirdTimes = (0..<firstThirdCount).map { index in
            CMTime(seconds: startPoint + Double(index) * firstThirdStep, preferredTimescale: 600)
        }
        
        let middleTimes = (0..<middleCount).map { index in
            CMTime(seconds: firstThirdEnd + Double(index) * middleStep, preferredTimescale: 600)
        }
        
        let lastThirdTimes = (0..<lastThirdCount).map { index in
            CMTime(seconds: lastThirdStart + Double(index) * lastThirdStep, preferredTimescale: 600)
        }
        
        return firstThirdTimes + middleTimes + lastThirdTimes
    }
    
    /// Format a timestamp in seconds to a string
    /// - Parameter seconds: The timestamp in seconds
    /// - Returns: A formatted timestamp string (HH:MM:SS)
    private func formatTimestamp(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    /// Calculate the aspect ratio of a video
    /// - Parameter asset: The video asset
    /// - Returns: The aspect ratio (width / height)
    private func calculateAspectRatio(from asset: AVAsset) async throws -> CGFloat {
        let track = try await asset.loadTracks(withMediaType: .video).first
        let size = try await track?.load(.naturalSize) ?? CGSize(width: 16, height: 9)
        let transform = try await track?.load(.preferredTransform) ?? .identity
        let videoSize = size.applying(transform)
        let ratio = abs(videoSize.width / videoSize.height)
        logger.debug("📐 Calculated aspect ratio: \(ratio) from size: \(videoSize.width)x\(videoSize.height)")
        return ratio
    }
    
    /// Save a mosaic image to disk
    /// - Parameters:
    ///   - mosaic: The mosaic image to save
    ///   - video: The video the mosaic was generated for
    ///   - config: The mosaic configuration
    /// - Returns: The URL of the saved mosaic
    private func saveMosaic(
        _ mosaic: CGImage,
        for video: Video,
        config: MosaicConfiguration
    ) async throws -> URL {
        let state = signposter.beginInterval("Save Mosaic")
        defer { signposter.endInterval("Save Mosaic", state) }
        
        // Determine output directory based on configuration
        let dirSuffix = "_Th\(config.width)_\(config.density.name)_\(config.layout.aspectRatio)"
        
        // Determine base output directory
        let baseOutputDirectory: URL
        if config.output.saveAtRoot {
            // If saveAtRoot is enabled, use the root directory of the video
            baseOutputDirectory = video.url
                .deletingLastPathComponent()
                .appendingPathComponent(dirSuffix, isDirectory: true)
        } else {
            // Otherwise, save in the same directory as the video
            baseOutputDirectory = video.url
                .deletingLastPathComponent()
                .appendingPathComponent(dirSuffix, isDirectory: true)
        }
        
        try FileManager.default.createDirectory(at: baseOutputDirectory,
                                             withIntermediateDirectories: true,
                                             attributes: nil)
        
        // Generate filename based on configuration
        let filename: String
        if config.output.addFullPath {
            // Replace path separators and spaces with underscores
            let fullPath = video.url.deletingPathExtension().path
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            
            // Ensure the filename isn't too long
            let maxLength = 200 - dirSuffix.count
            let truncatedPath = fullPath.count > maxLength 
                ? String(fullPath.suffix(maxLength)) 
                : fullPath
            
            filename = "\(truncatedPath)_\(config.width)_\(config.density.name)_\(config.layout.aspectRatio)"
        } else {
            let originalFilename = video.url.deletingPathExtension().lastPathComponent
            let fileSuffix = "\(config.width)_\(config.density.name)_\(config.layout.aspectRatio)"
            filename = "\(originalFilename)_\(fileSuffix)"
        }
        
        let mosaicURL = baseOutputDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension(config.format.rawValue)
        
        logger.debug("💾 Saving mosaic to: \(mosaicURL.path)")
        
        // Check if file exists and handle overwrite option
        if FileManager.default.fileExists(atPath: mosaicURL.path) {
            if config.output.overwrite {
                logger.debug("🔄 Overwriting existing file at: \(mosaicURL.path)")
                try FileManager.default.removeItem(at: mosaicURL)
            } else {
                logger.error("❌ File already exists at: \(mosaicURL.path)")
                throw MosaicError.fileExists(mosaicURL)
            }
        }
        
        // Convert CGImage to NSImage for saving
        let nsImage = NSImage(cgImage: mosaic, size: .zero)
        let data: Data?
        
        switch config.format {
        case .jpeg:
            data = nsImage.jpegData(compressionQuality: config.compressionQuality)
            logger.debug("📸 Saving as JPEG, quality: \(config.compressionQuality)")
        case .png:
            data = nsImage.pngData()
            logger.debug("📸 Saving as PNG")
        case .heif:
            // HEIF is not directly supported, so we fall back to JPEG
            data = nsImage.jpegData(compressionQuality: config.compressionQuality)
            logger.debug("📸 Saving as JPEG (HEIF fallback), quality: \(config.compressionQuality)")
        }
        
        guard let imageData = data else {
            logger.error("❌ Failed to create image data")
            throw MosaicError.saveFailed(mosaicURL, NSError(domain: "com.hypermovie", code: -1))
        }
        
        try imageData.write(to: mosaicURL)
        logger.debug("✅ Mosaic saved successfully")
        
        return mosaicURL
    }
    
    /// Track performance metrics
    /// - Parameter startTime: The start time of the operation
    private func trackPerformance(startTime: CFAbsoluteTime) {
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        lastGenerationTime = executionTime
        totalGenerationTime += executionTime
        generationCount += 1
    }
}

// MARK: - Extensions

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
