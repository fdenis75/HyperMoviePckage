import Foundation
import AVFoundation
import CoreGraphics
import OSLog
import Vision
import AppKit
import HyperMovieModels

/// A processor for extracting and managing video thumbnails
@available(macOS 15, *)
public final class ThumbnailProcessor {
    private let logger = Logger(subsystem: "com.hypermovie", category: "thumbnail-processor")
    private let config: MosaicConfiguration
    private let signposter = OSSignposter()
    
    /// Initialize a new thumbnail processor
    /// - Parameter config: Configuration for thumbnail processing
    public init(config: MosaicConfiguration) {
        self.config = config
    }
    
    /// Extract thumbnails from video with timestamps
    /// - Parameters:
    ///   - file: Video file URL
    ///   - layout: Layout information for the mosaic
    ///   - asset: Video asset to extract thumbnails from
    ///   - preview: Whether generating preview thumbnails
    ///   - accurate: Whether to use accurate timestamp extraction
    /// - Returns: Array of tuples containing thumbnail images and their timestamps
    public func extractThumbnails(
        from file: URL,
        layout: HyperMovieModels.MosaicLayout,
        asset: AVAsset,
        preview: Bool,
        accurate: Bool
    ) async throws -> [(image: CGImage, timestamp: String)] {
        logger.debug("🎬 Starting thumbnail extraction - File: \(file.lastPathComponent)")
        logger.debug("📐 Layout details - Grid: \(layout.rows)x\(layout.cols), Size: \(layout.thumbnailSize.width)x\(layout.thumbnailSize.height)")
        
        let state = signposter.beginInterval("Extract Thumbnails")
        defer { signposter.endInterval("Extract Thumbnails", state) }
        
        let duration = try await asset.load(.duration).seconds
        let generator = configureGenerator(for: asset, accurate: accurate, preview: preview, layout: layout)
        logger.debug("⚙️ Generator configured - Duration: \(duration)s, Accurate: \(accurate)")
        
        let times = try await calculateExtractionTimes(
            duration: duration,
            count: layout.thumbCount
        )
        logger.debug("⏱️ Calculated \(times.count) extraction times")
        
        var thumbnails: [(Int, CGImage, String)] = []
        var failedCount = 0
        
        for await result in generator.images(for: times) {
            switch result {
            case .success(requestedTime: _, image: let image, actualTime: let actual):
                thumbnails.append((thumbnails.count, image, self.formatTimestamp(seconds: actual.seconds)))
                logger.debug("✅ Extracted frame at \(self.formatTimestamp(seconds: actual.seconds))")
            case .failure(requestedTime: _, error: let error):
                logger.error("❌ Frame extraction failed: \(error.localizedDescription)")
                failedCount += 1
                if let blankImage = createBlankImage(size: layout.thumbnailSize) {
                    thumbnails.append((thumbnails.count, blankImage, "00:00:00"))
                    logger.debug("⚠️ Using blank image for failed frame")
                }
            }
        }
        
        if failedCount > 0 {
            logger.warning("⚠️ Extraction partial failure - Failed: \(failedCount), Success: \(thumbnails.count)")
            if thumbnails.isEmpty {
                logger.error("❌ All extractions failed")
                throw MosaicError.generationFailed(NSError(
                    domain: "com.hypermovie",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to extract any thumbnails"]
                ))
            }
        }
        
        logger.debug("✅ Thumbnail extraction complete - Total: \(thumbnails.count)")
        return thumbnails
            .sorted { $0.0 < $1.0 }
            .map { ($0.1, $0.2) }
    }
    
    /// Extract thumbnails from video with timestamps
    /// - Parameters:
    ///   - file: Video file URL
    ///   - count: Number of thumbnails to extract
    ///   - size: Size of each thumbnail
    ///   - asset: Video asset to extract thumbnails from
    ///   - accurate: Whether to use accurate timestamp extraction
    /// - Returns: Array of tuples containing thumbnail images and their timestamps
    public func extractThumbnailsUI(
        from file: URL,
        count: Int,
        size: CGSize,
        asset: AVAsset,
        accurate: Bool = true
    ) async throws -> [(image: CGImage, timestamp: String)] {
        let duration = try await asset.load(.duration).seconds
        let generator = configureGenerator(for: asset, accurate: accurate, preview: false, layout: .init(rows: 1, cols: 1, thumbnailSize: size, positions: [(x: 0, y: 0)], thumbCount: count, thumbnailSizes: [size], mosaicSize: size))
        
        // Calculate evenly spaced times
        let interval = duration / Double(count + 1)
        let times = (1...count).map { i in
            CMTime(seconds: interval * Double(i), preferredTimescale: 600)
        }
        
        var thumbnails: [(Int, CGImage, String)] = []
        
        for await result in generator.images(for: times) {
            switch result {
            case .success(requestedTime: _, image: let image, actualTime: let actual):
                thumbnails.append((thumbnails.count, image, formatTimestamp(seconds: actual.seconds)))
            case .failure:
                if let blankImage = createBlankImage(size: size) {
                    thumbnails.append((thumbnails.count, blankImage, "00:00:00"))
                }
            }
        }
        
        return thumbnails
            .sorted { $0.0 < $1.0 }
            .map { ($0.1, $0.2) }
    }
    
    /// Generate mosaic from extracted frames
    /// - Parameters:
    ///   - frames: Array of frames with timestamps
    ///   - layout: Layout information
    ///   - metadata: Video metadata
    ///   - config: Mosaic configuration
    /// - Returns: Generated mosaic image
    public func generateMosaic(
        from frames: [(image: CGImage, timestamp: String)],
        layout: HyperMovieModels.MosaicLayout,
        metadata: VideoMetadata,
        config: MosaicConfiguration
    ) async throws -> CGImage {
        logger.debug("🎨 Starting mosaic generation - Frames: \(frames.count)")
        logger.debug("📐 Layout size: \(layout.mosaicSize.width)x\(layout.mosaicSize.height), Grid: \(layout.rows)x\(layout.cols)")
        
        let image = NSImage(size: layout.mosaicSize)
        image.lockFocus()
        
        NSColor.black.set()
        NSRect(origin: .zero, size: layout.mosaicSize).fill()
        logger.debug("🎨 Background filled")
        
        for (index, frame) in frames.enumerated() {
            guard index < layout.positions.count else { break }
            
            let position = layout.positions[index]
            let size = layout.thumbnailSizes[index]
            let rect = NSRect(x: CGFloat(position.x), y: CGFloat(position.y), width: size.width, height: size.height)
            
            logger.debug("🖼️ Drawing frame \(index + 1)/\(frames.count) at (\(position.x), \(position.y))")
            
            if config.layout.visual.addShadow, let shadowSettings = config.layout.visual.shadowSettings {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(shadowSettings.opacity)
                shadow.shadowOffset = shadowSettings.offset
                shadow.shadowBlurRadius = shadowSettings.radius
                shadow.set()
                logger.debug("🌑 Applied shadow effect")
            }
            
            if config.layout.visual.addBorder {
                let borderColor = NSColor(white: config.layout.visual.borderColor.withOpacity(0.2), alpha: 1.0)
                borderColor.set()
                rect.frame(withWidth: config.layout.visual.borderWidth)
                logger.debug("📦 Applied border effect")
            }
            
            NSImage(cgImage: frame.image, size: size).draw(in: rect)
            
            if Task.isCancelled {
                logger.warning("❌ Mosaic creation cancelled")
                throw MosaicError.generationFailed(CancellationError())
            }
        }
        
        if config.includeMetadata {
            logger.debug("ℹ️ Adding metadata overlay")
            drawMetadata(
                context: NSGraphicsContext.current!.cgContext,
                metadata: metadata,
                width: Int(layout.mosaicSize.width),
                height: Int(layout.mosaicSize.height)
            )
        }
        
        image.unlockFocus()
        
        var rect = NSRect(origin: .zero, size: layout.mosaicSize)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            logger.error("❌ Failed to create final CGImage")
            throw MosaicError.imageGenerationFailed(NSError(domain: "com.hypermovie", code: -1))
        }
        
        logger.debug("✅ Mosaic generation complete - Size: \(cgImage.width)x\(cgImage.height)")
        return cgImage
    }
    
    // MARK: - Private Methods
    
    private func configureGenerator(
        for asset: AVAsset,
        accurate: Bool,
        preview: Bool,
        layout: HyperMovieModels.MosaicLayout
    ) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        if accurate {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        } else {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        }
        
        if !preview {
            generator.maximumSize = CGSize(
                width: layout.thumbnailSize.width * 2,
                height: layout.thumbnailSize.height * 2
            )
        }
        
        return generator
    }
    
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
    
    private func formatTimestamp(seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func createBlankImage(size: CGSize) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(gray: 0.0, alpha: 0.0))
        context?.fill(CGRect(origin: .zero, size: size))
        return context?.makeImage()
    }
    
    private func drawMetadata(
        context: CGContext,
        metadata: VideoMetadata,
        width: Int,
        height: Int
    ) {
        let metadataHeight = Int(round(Double(height) * 0.1))
        let lineHeight = metadataHeight / 4
        let fontSize = round(Double(lineHeight) / 2)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.shadowBlurRadius = 2
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]
        
        let metadataText = [
            "Codec: \(metadata.codec ?? "Unknown")",
            "Bitrate: \(formatBitrate(metadata.bitrate))",
            metadata.custom.map { "\($0.key): \($0.value)" }.joined(separator: " | ")
        ].joined(separator: "\n")
        
        let rect = NSRect(x: 10, y: 10, width: width - 20, height: metadataHeight)
        metadataText.draw(in: rect, withAttributes: attributes)
    }
    
    private func formatBitrate(_ bitrate: Int64?) -> String {
        guard let bitrate = bitrate else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bitrate) + "/s"
    }
} 