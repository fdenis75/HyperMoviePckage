import Foundation
import AVFoundation
import CoreGraphics
import OSLog
import AppKit
import HyperMovieModels

/// A service that handles video thumbnail generation
@available(macOS 15, *)
public actor VideoThumbnailService {
    private let logger = Logger(subsystem: "com.hypermovie", category: "video-thumbnails")
    private let thumbnailProcessor: ThumbnailProcessor
    
    public init() {
        self.thumbnailProcessor = ThumbnailProcessor(config: .default)
    }
    
    public func generateThumbnails(
        for video: Video,
        count: Int,
        size: CGSize = CGSize(width: 160, height: 90)
    ) async throws -> [HyperMovieModels.Video.VideoThumbnail] {
        logger.debug("🎬 Starting thumbnail generation for video: \(video.title)")
        
        let asset = AVURLAsset(url: video.url)
        let frames = try await thumbnailProcessor.extractThumbnailsUI(
            from: video.url,
            count: count,
            size: size,
            asset: asset
        )
        
        return frames.map { frame in
            HyperMovieModels.Video.VideoThumbnail(
                id: UUID(),
                image: NSImage(cgImage: frame.image, size: size),
                time: CMTime(seconds: Double(frame.timestamp.split(separator: ":").map { Double($0) ?? 0 }.reduce(0) { $0 * 60 + $1 }), preferredTimescale: 600),
                videoURL: video.url
            )
        }
    }
} 