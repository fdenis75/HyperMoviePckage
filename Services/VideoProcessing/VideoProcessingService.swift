import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import OSLog
import HyperMovieModels
import AppKit

/// A service that handles video processing operations including preview generation and mosaic creation.
/// This service uses structured concurrency for efficient parallel processing of video frames.
public actor VideoProcessingService {
    // MARK: - Types
    
    /// Represents the type of processing operation
    public enum ProcessingType: String {
        case preview
        case mosaic
        case thumbnail
    }
    
    /// Configuration for mosaic generation
    public struct MosaicConfig {
        public let columns: Int
        public let spacing: CGFloat
        public let quality: Double
        public let includeMetadata: Bool
        public let size: CGSize
        
        public init(columns: Int, spacing: CGFloat, quality: Double, includeMetadata: Bool, size: CGSize) {
            self.columns = columns
            self.spacing = spacing
            self.quality = quality
            self.includeMetadata = includeMetadata
            self.size = size
        }
    }
    
    /// Configuration for preview generation
    public struct PreviewConfig {
        public let duration: TimeInterval
        public let quality: Double
        public let frameRate: Int
        public let size: CGSize
        
        public init(duration: TimeInterval, quality: Double, frameRate: Int, size: CGSize) {
            self.duration = duration
            self.quality = quality
            self.frameRate = frameRate
            self.size = size
        }
    }
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "video-processing")
    private let processingQueue = DispatchQueue(label: "com.hypermovie.video-processing", qos: .userInitiated)
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    
    /// Maximum number of concurrent frame extractions
    private let maxConcurrentOperations = 4
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// Generates a preview video from the source video
    /// - Parameters:
    ///   - video: The source video to process
    ///   - config: Configuration for preview generation
    /// - Returns: URL of the generated preview video
    public func generatePreview(for video: Video, config: PreviewConfig) async throws -> URL {
        logger.info("Starting preview generation for video: \(video.title)")
        
        // Create output URL in temporary directory
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(video.id.uuidString)
            .appendingPathExtension("mp4")
        
        let asset = AVURLAsset(url: video.url)
        let duration = try await asset.load(.duration).seconds
        let frameCount = Int(duration * Double(config.frameRate))
        
        // Extract frames concurrently
        var frames: [CMTime: CGImage] = [:]
        try await withThrowingTaskGroup(of: (CMTime, CGImage).self) { group in
            var pendingTasks = 0
            
            for i in 0..<frameCount {
                if pendingTasks >= maxConcurrentOperations {
                    if let result = try await group.next() {
                        frames[result.0] = result.1
                        pendingTasks -= 1
                    }
                }
                
                let time = CMTime(seconds: Double(i) / Double(config.frameRate), preferredTimescale: 600)
                group.addTask {
                    let image = try await self.extractFrame(from: asset, at: time, size: config.size)
                    return (time, image)
                }
                pendingTasks += 1
            }
            
            // Wait for remaining tasks
            for try await result in group {
                frames[result.0] = result.1
            }
        }
        
        // Create preview video
        try await exportPreviewVideo(frames: frames, to: outputURL, config: config)
        
        logger.info("Completed preview generation: \(outputURL.path)")
        return outputURL
    }
    
    /// Generates a mosaic image from the source video
    /// - Parameters:
    ///   - video: The source video to process
    ///   - config: Configuration for mosaic generation
    /// - Returns: URL of the generated mosaic image
    public func generateMosaic(for video: Video, config: MosaicConfig) async throws -> URL {
        logger.info("Starting mosaic generation for video: \(video.title)")
        
        let asset = AVURLAsset(url: video.url)
        let duration = try await asset.load(.duration).seconds
        
        // Calculate frame extraction points
        let frameCount = config.columns * config.columns
        let timePoints = (0..<frameCount).map { i in
            CMTime(seconds: duration * Double(i) / Double(frameCount), preferredTimescale: 600)
        }
        
        // Extract frames concurrently
        var frames: [CGImage] = []
        var pendingTasks = 0
        
        try await withThrowingTaskGroup(of: CGImage.self) { group in
            for time in timePoints {
                if pendingTasks >= maxConcurrentOperations {
                    if let frame = try await group.next() {
                        frames.append(frame)
                        pendingTasks -= 1
                    }
                }
                
                group.addTask {
                    try await self.extractFrame(from: asset, at: time, size: config.size)
                }
            }
            
            for try await frame in group {
                frames.append(frame)
            }
        }
        
        // Create mosaic image
        let mosaicImage = try await createMosaicImage(
            frames: frames,
            columns: config.columns,
            spacing: config.spacing,
            includeMetadata: config.includeMetadata,
            video: video
        )
        
        // Save mosaic
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(video.id.uuidString + "_mosaic")
            .appendingPathExtension("jpg")
        
        try await saveMosaicImage(mosaicImage, to: outputURL, quality: config.quality)
        
        logger.info("Completed mosaic generation: \(outputURL.path)")
        return outputURL
    }
    
    /// Generates a thumbnail image from the video
    /// - Parameters:
    ///   - video: The source video
    ///   - size: Desired thumbnail size
    /// - Returns: URL of the generated thumbnail
    public func generateThumbnail(for video: Video, size: CGSize) async throws -> URL {
        logger.info("Starting thumbnail generation for video: \(video.title)")
        
        let asset = AVURLAsset(url: video.url)
        let duration = try await asset.load(.duration).seconds
        let time = CMTime(seconds: duration * 0.1, preferredTimescale: 600)
        
        let thumbnail = try await extractFrame(from: asset, at: time, size: size)
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(video.id.uuidString + "_thumb")
            .appendingPathExtension("jpg")
        
        try await saveThumbnailImage(thumbnail, to: outputURL)
        
        logger.info("Completed thumbnail generation: \(outputURL.path)")
        return outputURL
    }
    
    // MARK: - Private Methods
    
    private func extractFrame(from asset: AVURLAsset, at time: CMTime, size: CGSize) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = size
        
        let cgImage = try await generator.image(at: time).image
        
        // Resize if needed
        if cgImage.width != Int(size.width) || cgImage.height != Int(size.height) {
            let ciImage = CIImage(cgImage: cgImage)
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = ciImage
            filter.scale = Float(size.width / CGFloat(cgImage.width))
            filter.aspectRatio = Float(size.height / size.width)
            
            guard let outputImage = filter.outputImage,
                  let resizedImage = context.createCGImage(outputImage, from: outputImage.extent) else {
                throw VideoProcessingError.frameResizingFailed
            }
            
            return resizedImage
        }
        
        return cgImage
    }
    
    private func exportPreviewVideo(frames: [CMTime: CGImage], to outputURL: URL, config: PreviewConfig) async throws {
        let orderedTimes = frames.keys.sorted()
        guard let firstFrame = frames[orderedTimes[0]] else {
            throw VideoProcessingError.previewExportFailed
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: firstFrame.width,
            AVVideoHeightKey: firstFrame.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2000000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: firstFrame.width,
                kCVPixelBufferHeightKey as String: firstFrame.height
            ]
        )
        
        writerInput.expectsMediaDataInRealTime = false
        assetWriter.add(writerInput)
        
        guard assetWriter.startWriting() else {
            throw VideoProcessingError.previewExportFailed
        }
        
        assetWriter.startSession(atSourceTime: .zero)
        
        // Create pixel buffer pool
        guard let pool = adaptor.pixelBufferPool else {
            throw VideoProcessingError.previewExportFailed
        }
        
        // Write frames
        for time in orderedTimes {
            guard let frame = frames[time],
                  let buffer = try? createPixelBuffer(from: frame, using: pool) else {
                continue
            }
            
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            adaptor.append(buffer, withPresentationTime: time)
        }
        
        // Finish writing
        writerInput.markAsFinished()
        try await assetWriter.finishWriting()
    }
    
    private func createPixelBuffer(from image: CGImage, using pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw VideoProcessingError.pixelBufferCreationFailed
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
    
    private func createMosaicImage(frames: [CGImage], columns: Int, spacing: CGFloat, includeMetadata: Bool, video: Video) async throws -> CGImage {
        let frameWidth = CGFloat(frames[0].width)
        let frameHeight = CGFloat(frames[0].height)
        let totalWidth = frameWidth * CGFloat(columns) + spacing * CGFloat(columns - 1)
        let totalHeight = frameHeight * CGFloat(columns) + spacing * CGFloat(columns - 1)
        
        let size = NSSize(width: totalWidth, height: totalHeight)
        let image = NSImage(size: size)
        image.lockFocus()
        
        for (index, frame) in frames.enumerated() {
            let row = index / columns
            let col = index % columns
            let x = CGFloat(col) * (frameWidth + spacing)
            let y = CGFloat(row) * (frameHeight + spacing)
            
            NSImage(cgImage: frame, size: NSSize(width: frameWidth, height: frameHeight))
                .draw(in: NSRect(x: x, y: y, width: frameWidth, height: frameHeight))
        }
        
        if includeMetadata {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white
            ]
            
            let text = "\(video.title)\n\(video.duration.formatted())"
            (text as NSString).draw(at: NSPoint(x: 10, y: 10), withAttributes: attributes)
        }
        
        image.unlockFocus()
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VideoProcessingError.mosaicCreationFailed
        }
        
        return cgImage
    }
    
    private func saveMosaicImage(_ image: CGImage, to url: URL, quality: Double) async throws {
        let data = try NSImage(cgImage: image, size: .zero).tiffRepresentation
        try data?.write(to: url)
    }
    
    private func saveThumbnailImage(_ image: CGImage, to url: URL) async throws {
        let data = try NSImage(cgImage: image, size: .zero).tiffRepresentation
        try data?.write(to: url)
    }
}

// MARK: - Errors

public enum VideoProcessingError: Error {
    case frameExtractionFailed
    case frameResizingFailed
    case previewExportFailed
    case pixelBufferCreationFailed
    case mosaicCreationFailed
    case thumbnailGenerationFailed
} 