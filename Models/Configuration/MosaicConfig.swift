import Foundation
import CoreGraphics

/// Configuration for mosaic generation.
@available(macOS 14.0, *)
public struct MosaicConfiguration: Codable, Sendable {
    // MARK: - Properties
    
    /// The width of the output mosaic in pixels.
    public var width: Int
    
    /// The density configuration for frame extraction.
    public var density: DensityConfig
    
    /// The output format for the mosaic.
    public var format: OutputFormat
    
    /// The layout configuration for the mosaic.
    public var layout: LayoutConfiguration
    
    /// Whether to include metadata overlay.
    public var includeMetadata: Bool
    
    /// Whether to use accurate timestamps for frame extraction.
    public var useAccurateTimestamps: Bool
    
    /// Output options for saving the mosaic.
    public var output: OutputOptions
    
    /// The compression quality for JPEG/HEIF output (0.0 to 1.0).
    public var compressionQuality: Double
    
    // MARK: - Initialization
    
    /// Creates a new MosaicConfiguration instance.
    public init(
        width: Int = 5120,
        density: DensityConfig = .default,
        format: OutputFormat = .heif,
        layout: LayoutConfiguration = .default,
        includeMetadata: Bool = true,
        useAccurateTimestamps: Bool = true,
        output: OutputOptions = .default,
        compressionQuality: Double = 0.4
    ) {
        self.width = width
        self.density = density
        self.format = format
        self.layout = layout
        self.includeMetadata = includeMetadata
        self.useAccurateTimestamps = useAccurateTimestamps
        self.output = output
        self.compressionQuality = compressionQuality
    }
    
    /// The default mosaic configuration.
    public static let `default` = MosaicConfiguration()
}

/// Output options for saving mosaics.
public struct OutputOptions: Codable, Sendable {
    /// Whether to overwrite existing files.
    public let overwrite: Bool
    
    /// Whether to save at the root directory.
    public let saveAtRoot: Bool
    
    /// Whether to create separate folders by type.
    public let separateFolders: Bool
    
    /// Whether to include the full path in the filename.
    public let addFullPath: Bool
    
    /// Creates a new OutputOptions instance.
    public init(
        overwrite: Bool = false,
        saveAtRoot: Bool = false,
        separateFolders: Bool = true,
        addFullPath: Bool = false
    ) {
        self.overwrite = overwrite
        self.saveAtRoot = saveAtRoot
        self.separateFolders = separateFolders
        self.addFullPath = addFullPath
    }
    
    /// The default output options.
    public static let `default` = OutputOptions()
} 