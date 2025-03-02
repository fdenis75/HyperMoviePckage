import Foundation
import AVFoundation
import CoreImage
import HyperMovieModels
import HyperMovieCore
import OSLog
import AppKit

@available(macOS 15, *)
/// A service that handles preview generation operations.
public actor PreviewGenerator: PreviewGenerating {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "preview-generation")
    private let processingQueue = DispatchQueue(label: "com.hypermovie.preview-generation", qos: .userInitiated)
    private let signposter = OSSignposter()
    
    private var generationTasks: [UUID: Task<URL, Error>] = [:]
    private var currentExportSession: AVAssetExportSession?
    private var _progress: Double = 0
    
    public var progress: Double { _progress }
    
    // MARK: - PreviewGenerating
    
    public func generateMultiple(for videos: [Video], config: PreviewConfiguration) async throws -> [UUID: URL] {
        logger.debug("Starting batch preview generation for \(videos.count) videos")
        var results: [UUID: URL] = [:]
        for (index, video) in videos.enumerated() {
            logger.debug("Processing video \(index + 1)/\(videos.count): \(video.url.lastPathComponent)")
            let url = try await generate(for: video, config: config) { progress in
                self._progress = (Double(index) + progress) / Double(videos.count)
            }
            results[video.id] = url
        }
        logger.debug("Completed batch preview generation")
        return results
    }
    
    public func generate(for video: Video, config: PreviewConfiguration, progressHandler: @escaping (Double) -> Void = { _ in }) async throws -> URL {
        let state = signposter.beginInterval("Generate Preview")
        defer { signposter.endInterval("Generate Preview", state) }
        
        logger.debug("Starting preview generation for \(video.url.lastPathComponent)")
        progressHandler(0.1) // Started
        
        // Create asset
        let asset = AVURLAsset(url: video.url)
        let duration = try await asset.load(.duration).seconds
        logger.debug("Video duration: \(duration) seconds")
        progressHandler(0.2) // Asset loaded
        
        // Calculate extraction parameters
        let extractParams = try calculateExtractionParameters(
            duration: duration,
            density: config.density,
            previewDuration: config.duration
        )
        logger.debug("Extraction parameters: count=\(extractParams.extractCount), duration=\(extractParams.extractDuration), speed=\(extractParams.speedMultiplier)")
        progressHandler(0.3) // Parameters calculated
        
        // Create composition
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ),
              let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ),
              let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        else {
            logger.error("Failed to create composition tracks")
            throw PreviewError.unableToCreateCompositionTracks
        }
        
        logger.debug("Created composition tracks")
        progressHandler(0.4) // Tracks created
        
        // Insert segments
        try await insertSegments(
            asset: asset,
            into: composition,
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            compositionVideoTrack: compositionVideoTrack,
            compositionAudioTrack: compositionAudioTrack,
            extractParams: extractParams,
            speedMultiplier: extractParams.speedMultiplier,
            progressHandler: { segmentProgress in
                progressHandler(0.4 + segmentProgress * 0.3) // 40-70% progress during segment insertion
            }
        )
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            logger.error("Failed to create export session")
            throw PreviewError.unableToCreateExportSession
        }
        
        // Configure export
        let previewURL = try createPreviewURL(for: video, config: config)
        logger.debug("Exporting preview to: \(previewURL.path)")
        exportSession.outputURL = previewURL
        exportSession.outputFileType = .mp4
        
        // Export with progress monitoring
        currentExportSession = exportSession
        
        while exportSession.status == .exporting {
            let currentProgress = 0.7 + Double(exportSession.progress) * 0.3
            logger.debug("Export progress: \(Int(currentProgress * 100))%")
            progressHandler(currentProgress) // 70-100% during export
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        await exportSession.export()
        
        if let error = exportSession.error {
            logger.error("Export failed: \(error.localizedDescription)")
            throw error
        }
        
        logger.debug("Preview generation completed successfully")
        progressHandler(1.0) // Complete
        return previewURL
    }
    
    public func cancel(for video: Video) {
        _progress = 0
        logger.info("Cancelling preview generation for \(video.url.path)")
        generationTasks[video.id]?.cancel()
        generationTasks[video.id] = nil
        currentExportSession?.cancelExport()
    }
    
    public func cancelAll() {
        _progress = 0
        logger.info("Cancelling all preview generation tasks")
        generationTasks.values.forEach { $0.cancel() }
        generationTasks.removeAll()
        currentExportSession?.cancelExport()
    }
    
    // MARK: - Private Methods
    
    private func calculateExtractionParameters(
        duration: Double,
        density: DensityConfig,
        previewDuration: Double
    ) throws -> (extractCount: Int, extractDuration: Double, speedMultiplier: Double) {
        let baseExtractsPerMinute: Double
        
        // Calculate base number of extracts based on video duration and density
        if duration > 0 {
            let durationInMinutes = duration / 60.0
            let initialRate = 12.0 // Base rate for extracts per minute
            let decayFactor = 0.2 // Rate at which extracts/minute decreases with duration
            baseExtractsPerMinute = (initialRate / (1 + decayFactor * durationInMinutes)) / density.extractsMultiplier
            
        } else {
            baseExtractsPerMinute = 12.0
        }
        
        // Calculate number of extracts
        let extractCount = max(4, Int(ceil(duration / 60.0 * baseExtractsPerMinute)))
        var extractDuration = previewDuration / Double(extractCount)
        if extractDuration < 0.5 {
            extractDuration = 0.5
        }
        // Calculate extract duration and speed multiplier
        let idealExtractDuration = previewDuration / Double(extractCount)
        let targetDuration = previewDuration
        let speedMultiplier = min(1.5, idealExtractDuration * Double(extractCount) / targetDuration)
        // let extractDuration = idealExtractDuration
        logger.debug("Extract count: \(extractCount), extract duration: \(extractDuration), speed multiplier: \(speedMultiplier)")
        return (extractCount, extractDuration, speedMultiplier)
    }
    
    private func createPreviewURL(for video: Video, config: PreviewConfiguration) throws -> URL {
        if config.saveInCustomLocation {
            if let customLocation = config.customSaveLocation {
                return customLocation
            } else {
                // Save next to original video
                let filename = video.url.deletingPathExtension().lastPathComponent + "-preview.mp4"
                return video.url.deletingLastPathComponent().appendingPathComponent(filename)
            }
        } else {
            // Save in temp directory
            let previewsDirectory = try FileManager.default
                .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Previews", isDirectory: true)
            
            try FileManager.default.createDirectory(at: previewsDirectory,
                                                 withIntermediateDirectories: true)
            
            return previewsDirectory
                .appendingPathComponent(video.id.uuidString)
                .appendingPathExtension("mp4")
        }
    }
    
    private func insertSegments(
        asset: AVAsset,
        into composition: AVMutableComposition,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack,
        compositionVideoTrack: AVMutableCompositionTrack,
        compositionAudioTrack: AVMutableCompositionTrack,
        extractParams: (extractCount: Int, extractDuration: Double, speedMultiplier: Double),
        speedMultiplier: Double,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        logger.debug("""
        Starting segment insertion with parameters:
        - Extract count: \(extractParams.extractCount)
        - Extract duration: \(extractParams.extractDuration)s
        - Speed multiplier: \(speedMultiplier)x
        - Composition duration: \(composition.duration.seconds)s
        """)
        let state = signposter.beginInterval("Insert Segments")
        defer { signposter.endInterval("Insert Segments", state) }
        
        let duration = try await asset.load(.duration).seconds
        let timescale: CMTimeScale = 600
        var currentTime = CMTime.zero
        let durationCMTime = CMTime(seconds: extractParams.extractDuration, preferredTimescale: timescale)
        let fastPlaybackDuration = CMTime(
            seconds: extractParams.extractDuration / speedMultiplier,
            preferredTimescale: timescale
        )
        
        for i in 0..<extractParams.extractCount {
            let startTime = CMTime(
                seconds: Double(i) * (duration - extractParams.extractDuration) / Double(extractParams.extractCount - 1),
                preferredTimescale: timescale
            )
            
            do {
                let timeRange = CMTimeRange(start: currentTime, duration: durationCMTime)
                logger.debug("Inserting video track at \(currentTime.seconds), duration \(durationCMTime.seconds)")
                try compositionVideoTrack.insertTimeRange(
                    CMTimeRange(start: startTime, duration: durationCMTime),
                    of: videoTrack,
                    at: currentTime
                )
                compositionVideoTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
                
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: startTime, duration: durationCMTime),
                    of: audioTrack,
                    at: currentTime
                )
                compositionAudioTrack.scaleTimeRange(timeRange, toDuration: fastPlaybackDuration)
                
                currentTime = CMTimeAdd(currentTime, fastPlaybackDuration)
            } catch {
                logger.error("Failed to insert or scale time range: \(error.localizedDescription)")
                throw PreviewError.segmentInsertionFailed
            }
            logger.debug("Progress: \(Double(i) / Double(extractParams.extractCount - 1))")
            progressHandler(Double(i) / Double(extractParams.extractCount - 1))
        }
    }
} 
