import Foundation
import AVFoundation
import CoreImage
import HyperMovieModels
import HyperMovieCore
import OSLog
import AppKit
import Vision

/// A service that handles mosaic generation operations.
@available(macOS 15, *)
public actor MosaicGenerator: HyperMovieCore.MosaicGenerating {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "mosaic-generation")
    private let context: CIContext = CIContext(options: nil)
    private let layoutProcessor: LayoutProcessor
    private let thumbnailProcessor: ThumbnailProcessor
    
    private var generationTasks: [UUID: Task<URL, Error>] = [:]
    private var frameCache: [UUID: [CMTime: CGImage]] = [:]
    private var progressHandlers: [UUID: (Double) -> Void] = [:]
    
    // MARK: - Initialization
    
    public init(layoutProcessor: LayoutProcessor = LayoutProcessor()) {
        self.layoutProcessor = layoutProcessor
        self.thumbnailProcessor = ThumbnailProcessor(config: .default)
        logger.debug("🎬 MosaicGenerator initialized")
    }
    
    // MARK: - MosaicGenerating
    
    public func generate(for video: Video, config: MosaicConfiguration) async throws -> URL {
        logger.debug("🎯 Starting mosaic generation for video: \(video.title)")
        
        if let existingTask = generationTasks[video.id] {
            logger.debug("⚡️ Reusing existing task for video: \(video.id)")
            return try await existingTask.value
        }
        let task = Task<URL, Error> {
            func generateMosaic() async throws -> URL {
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
                
                // Extract frames
                progressHandlers[video.id]?(0.1)
                let frames = try await thumbnailProcessor.extractThumbnails(
                    from: video.url,
                    layout: layout,
                    asset: asset,
                    preview: false,
                    accurate: config.useAccurateTimestamps
                )
                logger.debug("🎞️ Extracted \(frames.count) frames")
                
                progressHandlers[video.id]?(0.5)
                
                // Create mosaic
                let mosaic = try await thumbnailProcessor.generateMosaic(
                    from: frames,
                    layout: layout,
                    metadata: VideoMetadata(
                        codec: video.metadata.codec,
                        bitrate: video.metadata.bitrate,
                        custom: video.metadata.custom
                    ),
                    config: config
                )
                logger.debug("🖼️ Mosaic created - Size: \(mosaic.width)x\(mosaic.height)")
                
                progressHandlers[video.id]?(0.8)
                
                // Save mosaic
                let dirSuffix = "_Th\(config.width)_\(config.density.name)_\(config.layout.aspectRatio)"
                let outputDirectory = video.url
                    .deletingLastPathComponent()
                    .appendingPathComponent(dirSuffix, isDirectory: true)
                
                try FileManager.default.createDirectory(at: outputDirectory,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
                
                let originalFilename = video.url.deletingPathExtension().lastPathComponent
                let fileSuffix = "\(config.width)_\(config.density.name)_\(config.layout.aspectRatio)"
                let filename = "\(originalFilename)_\(fileSuffix)"
                
                let mosaicURL = outputDirectory
                    .appendingPathComponent(filename)
                    .appendingPathExtension(config.format.rawValue)
                
                logger.debug("💾 Saving mosaic to: \(mosaicURL.path)")
                
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
                    data = nsImage.jpegData(compressionQuality: config.compressionQuality)
                    logger.debug("📸 Saving as JPEG (HEIF fallback), quality: \(config.compressionQuality)")
                }
                
                guard let imageData = data else {
                    logger.error("❌ Failed to create image data")
                    throw MosaicError.saveFailed(mosaicURL, NSError(domain: "com.hypermovie", code: -1))
                }
                
                try imageData.write(to: mosaicURL)
                
                await MainActor.run {
                    video.mosaicURL = mosaicURL
                }
                
                progressHandlers[video.id]?(1.0)
                logger.debug("✅ Mosaic generation completed successfully")
                
                return mosaicURL
            }
            
            return try await generateMosaic()
        }
        
        generationTasks[video.id] = task
        defer { 
            generationTasks[video.id] = nil
            progressHandlers[video.id] = nil
        }
        
        return try await task.value
    }
    
    public func cancel(for video: Video) {
        logger.debug("❌ Cancelling mosaic generation for: \(video.title)")
        generationTasks[video.id]?.cancel()
        generationTasks[video.id] = nil
        frameCache[video.id] = nil
    }
    
    public func cancelAll() {
        logger.debug("❌ Cancelling all mosaic generation tasks")
        generationTasks.values.forEach { $0.cancel() }
        generationTasks.removeAll()
        frameCache.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func calculateAspectRatio(from asset: AVURLAsset) async throws -> CGFloat {
        let track = try await asset.loadTracks(withMediaType: .video).first
        let size = try await track?.load(.naturalSize) ?? CGSize(width: 16, height: 9)
        let transform = try await track?.load(.preferredTransform) ?? .identity
        let videoSize = size.applying(transform)
        let ratio = abs(videoSize.width / videoSize.height)
        logger.debug("📐 Calculated aspect ratio: \(ratio) from size: \(videoSize.width)x\(videoSize.height)")
        return ratio
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

// MARK: - Errors

public enum MosaicError: Error {
    case generationFailed(Error)
    case imageGenerationFailed(Error)
    case saveFailed(URL, Error)
    case fileExists(URL)
} 
