import Foundation

/// Configuration for preview generation
public struct PreviewConfiguration {
    /// Duration of the preview in seconds
    public var duration: Double
    
    /// Density configuration affecting the number of extracts
    public var density: DensityConfig
    
    /// Whether to save the preview in a custom location
    public var saveInCustomLocation: Bool
    
    /// Custom save location. If nil and saveInCustomLocation is true, will save next to original video
    public var customSaveLocation: URL?
    
    /// Maximum speed multiplier for extracts (default 1.5)
    public var maxSpeedMultiplier: Double
    
    /// Default configuration for quick preview (30s, XS density, temp location)
    public static let `default` = PreviewConfiguration(
        duration: 30,
        density: .xs,
        saveInCustomLocation: false,
        customSaveLocation: nil,
        maxSpeedMultiplier: 1.5
    )
    
    /// Initialize a preview configuration
    /// - Parameters:
    ///   - duration: Duration of the preview in seconds (default: 30)
    ///   - density: Density configuration affecting the number of extracts (default: .xs)
    ///   - saveInCustomLocation: Whether to save in a custom location (default: false)
    ///   - customSaveLocation: Custom save location (default: nil)
    ///   - maxSpeedMultiplier: Maximum speed multiplier for extracts (default: 1.5)
    public init(
        duration: Double = 30,
        density: DensityConfig = .xs,
        saveInCustomLocation: Bool = false,
        customSaveLocation: URL? = nil,
        maxSpeedMultiplier: Double = 1.5
    ) {
        self.duration = duration
        self.density = density
        self.saveInCustomLocation = saveInCustomLocation
        self.customSaveLocation = customSaveLocation
        self.maxSpeedMultiplier = maxSpeedMultiplier
    }
}

public extension PreviewConfiguration {
    /// Creates a configuration for saving in a custom location
    /// - Parameters:
    ///   - duration: Duration of the preview in seconds
    ///   - density: Density configuration affecting the number of extracts
    ///   - saveLocation: Custom save location
    /// - Returns: A preview configuration
    static func custom(
        duration: Double,
        density: DensityConfig,
        saveLocation: URL
    ) -> PreviewConfiguration {
        PreviewConfiguration(
            duration: duration,
            density: density,
            saveInCustomLocation: true,
            customSaveLocation: saveLocation,
            maxSpeedMultiplier: 1.5
        )
    }
} 