import Foundation
import AVFoundation

/// Configuration for video processing operations.
public struct ProcessingConfiguration: Codable, Sendable {
    /// The width of the output in pixels.
    public var width: Int
    
    /// The output format configuration.
    public var format: OutputFormat
    
    /// Whether to use accurate timestamps.
    public var useAccurateTimestamps: Bool
    
    /// The video export preset to use.
    public var exportPreset: String
    
    /// The compression quality for image outputs (0.0 to 1.0).
    public var compressionQuality: Double
    
    /// Whether to use hardware acceleration when available.
    public var useHardwareAcceleration: Bool
    
    /// Creates a new ProcessingConfiguration instance.
    /// - Parameters:
    ///   - width: The width of the output in pixels.
    ///   - format: The output format configuration.
    ///   - useAccurateTimestamps: Whether to use accurate timestamps.
    ///   - exportPreset: The video export preset to use.
    ///   - compressionQuality: The compression quality for image outputs.
    ///   - useHardwareAcceleration: Whether to use hardware acceleration.
    public init(
        width: Int = 1920,
        format: OutputFormat = .heif,
        useAccurateTimestamps: Bool = true,
        exportPreset: String = AVAssetExportPresetHEVC1920x1080,
        compressionQuality: Double = 0.8,
        useHardwareAcceleration: Bool = true
    ) {
        self.width = width
        self.format = format
        self.useAccurateTimestamps = useAccurateTimestamps
        self.exportPreset = exportPreset
        self.compressionQuality = compressionQuality
        self.useHardwareAcceleration = useHardwareAcceleration
    }
    
    /// The default processing configuration.
    public static let `default` = ProcessingConfiguration()
}

/// The output format for processed videos.
public enum OutputFormat: String, Codable, Sendable {
    /// JPEG format.
    case jpeg
    /// PNG format.
    case png
    /// HEIF format.
    case heif
}

