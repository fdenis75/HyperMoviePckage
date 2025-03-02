import Foundation
import AVFoundation
import SwiftData
import CoreGraphics
import os
import HyperMovieModels
import AppKit
/// A model representing video metadata.
@available(macOS 14, *)
public struct VideoMetadata: Codable, Hashable {
    public var codec: String?
    public var bitrate: Int64?
    public var custom: [String: String] = [:]

    public init(codec: String? = nil, bitrate: Int64? = nil, custom: [String: String] = [:]) {
        self.codec = codec
        self.bitrate = bitrate
        self.custom = custom
    }
}

/// A model representing a video file in the HyperMovie application.
@Model
@available(macOS 14, *)
public final class Video {
    
    // MARK: - Properties
    @Transient public var logger = Logger(subsystem: "com.hypermovie", category: "video")
    
    public var id: UUID
    public var url: URL
    public var title: String
    public var duration: TimeInterval = 0
    public var thumbnailURL: URL?
    public var mosaicURL: URL?
    public var previewURL: URL?
    
    // Store resolution as separate width/height
    public var width: Double?
    public var height: Double?
    
    // Store metadata as individual properties
    public var codec: String?
    public var bitrate: Int64?
    public var customMetadata: [String: String] = [:]
    
    public var processingStatus: [String: Bool]
    public var dateAdded: Date
    public var dateModified: Date
    public var fileSize: Int64?
    public var frameRate: Float64?
    
    // MARK: - Computed Properties
    
    public var resolution: CGSize? {
        get {
            if let width = width, let height = height {
                return CGSize(width: width, height: height)
            }
            return nil
        }
        set {
            width = Double(newValue?.width ?? 0)
            height = Double(newValue?.height ?? 0)
        }
    }
    
    public var metadata: VideoMetadata {
        get {
            VideoMetadata(
                codec: codec,
                bitrate: bitrate,
                custom: customMetadata
            )
        }
        set {
            codec = newValue.codec
            bitrate = newValue.bitrate
            customMetadata = newValue.custom
        }
    }
    
    public init(id: UUID = UUID(), url: URL, title: String? = nil) async throws {
        logger.debug("🎬 Initializing Video object with id: \(id), url: \(url.path)")
        
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.dateAdded = Date()
        self.dateModified = Date()
        self.processingStatus = [:]
        
        logger.debug("📝 Basic properties initialized - title: \(self.title)")
        
        // Setup thumbnail directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let thumbnailDirectory = appSupport.appendingPathComponent("HyperMovie/Thumbnails", isDirectory: true)
        
        logger.debug("📁 Creating thumbnail directory at: \(thumbnailDirectory.path)")
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        
        // Generate thumbnail filename
        let thumbnailFileName = id.uuidString + "_thumb.heic"
        self.thumbnailURL = thumbnailDirectory.appendingPathComponent(thumbnailFileName)
        logger.debug("🖼️ Thumbnail will be saved to: \(thumbnailFileName)")
        
        // Load metadata and generate thumbnail, but don't fail if they fail
        do {
            try await loadMetadata()
            logger.debug("✅ Metadata loaded successfully")
        } catch {
            logger.error("❌ Failed to load metadata: \(error.localizedDescription)")
            // Set default values for metadata
            self.duration = 0
            self.width = nil
            self.height = nil
            self.codec = nil
            self.bitrate = nil
            self.frameRate = nil
        }
        
        do {
            try await generateThumbnail()
            logger.debug("✅ Thumbnail generated successfully")
        } catch {
            logger.error("❌ Failed to generate thumbnail: \(error.localizedDescription)")
            // Thumbnail URL will remain nil
        }
        
        // Update file size even if other operations fail
        await updateFileSize()
    }
    
    // MARK: - Computed Properties (Nonisolated)
    nonisolated public var isFullyProcessed: Bool {
        let files = [thumbnailURL, mosaicURL, previewURL]
        return files.allSatisfy { $0 != nil && FileManager.default.fileExists(atPath: $0!.path) }
    }
    
    nonisolated public var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00:00"
    }

    // MARK: - Main Loading Function
    public func loadMetadata() async throws {
        let asset = AVURLAsset(url: url)

        do {
            // Load duration asynchronously
            let durationSeconds = try await asset.load(.duration).seconds
            await updateDuration(durationSeconds)

            // Use new `loadMediaTrack(from:)` function
            if let (size, frameRate, bitrate, codec) = try await loadMediaTrack(from: asset) {
                await processVideoTrackData(size: size, frameRate: frameRate, bitrate: bitrate, codec: codec)
            }
        } catch {
            logger.error("Error loading metadata: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Methods
    private func loadMediaTrack(from asset: AVURLAsset) async throws -> (CGSize, Float64, Int64, String?)? {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { return nil }

        // Load properties asynchronously
        async let size = track.load(.naturalSize)
        async let frameRate = track.load(.nominalFrameRate)
        async let bitrate = track.load(.estimatedDataRate)
        async let descriptions = track.load(.formatDescriptions)

        let (resolvedSize, resolvedFrameRate, resolvedBitrate, resolvedDescriptions) =
            await (try size, try frameRate, try bitrate, try descriptions)

        // Extract codec information
        let codec: String? = resolvedDescriptions.first.map {
            let mediaType = CMFormatDescriptionGetMediaType($0)
            let mediaSubType = CMFormatDescriptionGetMediaSubType($0)
            return "\(mediaType.toString())/\(mediaSubType.toString())"
        }

        // Only return Sendable types
        return (resolvedSize, Float64(resolvedFrameRate),Int64(resolvedBitrate), codec)
    }
    private func processVideoTrackData(size: CGSize, frameRate: Float64, bitrate: Int64, codec: String?) async {
        await MainActor.run {
            self.resolution = size
            self.frameRate = frameRate

            var newMetadata = self.metadata
            newMetadata.bitrate = bitrate
            newMetadata.codec = codec
            self.metadata = newMetadata

            self.metadata.custom["resolution"] = "\(Int(size.width))x\(Int(size.height))"
            self.metadata.custom["framerate"] = "\(frameRate)"
        }
    
    }
    


    // MARK: - Thread-safe Updates
    private func updateDuration(_ duration: TimeInterval) async {
        await MainActor.run { self.duration = duration }
    }

    private func updateFileSize() async {
        let url = self.url
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            await MainActor.run { self.fileSize = attributes[.size] as? Int64 }
        }
    }

    // MARK: - Thumbnail Generation
    
    public func generateThumbnails(density: DensityConfig) async throws -> [VideoThumbnail] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        
        let frameCount = calculateThumbnailCount(duration: duration, density: density)
        let interval = duration / Double(frameCount)
        
        var thumbnails: [VideoThumbnail] = []
        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            
            let cgImage = try await generator.image(at: time).image
            let thumbnail = VideoThumbnail(
                id: UUID(),
                image: NSImage(cgImage: cgImage, size: .zero),
                time: time,
                videoURL: url
            )
            thumbnails.append(thumbnail)
        }
        
        return thumbnails
    }
    
    private func calculateThumbnailCount(duration: Double, density: DensityConfig) -> Int {
        if duration < 5 { return 4 }
        
        let base = 320.0 / 200.0 // base on thumbnail width
        let k = 10.0
        let rawCount = base + k * log(duration)
        let totalCount = Int(rawCount / density.factor)
        
        return min(totalCount, 100)
    }
    
    public struct VideoThumbnail: Identifiable, Equatable {
        public let id: UUID
        public let imageData: Data
        public let timeInSeconds: Double
        public let videoURL: URL
        
        public init(id: UUID = UUID(), image: NSImage, time: CMTime, videoURL: URL) {
            self.id = id
            self.imageData = image.tiffRepresentation ?? Data()
            self.timeInSeconds = time.seconds
            self.videoURL = videoURL
        }
        
        public var image: NSImage {
            NSImage(data: imageData) ?? NSImage()
        }
        
        public var time: CMTime {
            CMTime(seconds: timeInSeconds, preferredTimescale: 600)
        }
        
        public static func == (lhs: VideoThumbnail, rhs: VideoThumbnail) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    private func generateThumbnail() async throws {
        guard let thumbnailURL = thumbnailURL else { return }
        
        // Skip if thumbnail already exists
        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            return
        }
        
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let time = CMTime(seconds: duration.seconds * 0.1, preferredTimescale: 600)
            
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            
            // Calculate thumbnail size based on video resolution
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                let aspectRatio = size.width / size.height
                generator.maximumSize = CGSize(width: 480, height: 480 / aspectRatio)
            }
            
            let cgImage = try await generator.image(at: time).image
            let nsImage = NSImage(cgImage: cgImage, size: .zero)
            
            guard let imageData = nsImage.heicData(compressionQuality: 0.8) else {
                throw VideoError.processingFailed(thumbnailURL, NSError(domain: "com.hypermovie", code: -1))
            }
            
            try imageData.write(to: thumbnailURL)
            logger.info("Generated thumbnail for \(self.url.path)")
        } catch {
            logger.error("Failed to generate thumbnail: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Video Processing Status Enum
public enum VideoStatus: String, Codable {
    case pending
    case processing
    case completed
    case error
}

// MARK: - Extensions for Debugging and Hashing
@available(macOS 15, *)
extension Video: CustomDebugStringConvertible {
    nonisolated public var debugDescription: String {
        "Video(id: \(id), title: \(title), duration: \(formattedDuration), resolution: \(String(describing: resolution)), isProcessed: \(isFullyProcessed))"
    }
}

@available(macOS 15, *)
extension Video: Hashable {
    nonisolated public static func == (lhs: Video, rhs: Video) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Private Extensions for Codec Extraction
private extension FourCharCode {
    func toString() -> String {
        let bytes: [CChar] = [
            CChar((self >> 24) & 0xff),
            CChar((self >> 16) & 0xff),
            CChar((self >> 8) & 0xff),
            CChar(self & 0xff),
            0
        ]
        let result = String(cString: bytes)
        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Private Extensions
private extension NSImage {
    func heicData(compressionQuality: Double = 0.8) -> Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, 
                                        properties: [.compressionFactor: compressionQuality])
    }
}
