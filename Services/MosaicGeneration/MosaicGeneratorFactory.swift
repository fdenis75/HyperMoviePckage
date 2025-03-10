import Foundation
import HyperMovieCore
import OSLog
import Metal

/// A factory for creating mosaic generators
@available(macOS 15, *)
public enum MosaicGeneratorFactory {
    /// The type of mosaic generator to create
    public enum GeneratorType: String, Codable {
        /// Standard CPU-based mosaic generator
        case standard = "Standard"
        
        /// Metal-accelerated mosaic generator
        case metal = "Metal"
        
        /// Automatically choose the best generator based on hardware
        case auto = "Auto"
        
        public init?(rawValue: String) {
            switch rawValue {
            case "Standard": self = .standard
            case "Metal": self = .metal
            case "Auto": self = .auto
            default: return nil
            }
        }
    }
    
    private static let logger = Logger(subsystem: "com.hypermovie", category: "mosaic-factory")
    
    /// Create a mosaic generator of the specified type
    /// - Parameter type: The type of generator to create
    /// - Returns: A mosaic generator
    public static func createGenerator(type: GeneratorType = .auto) -> any MosaicGenerating {
        switch type {
        case .standard:
            logger.debug("🔧 Creating standard mosaic generator")
            return MosaicGenerator()
            
        case .metal:
            logger.debug("🔧 Creating Metal-accelerated mosaic generator")
            do {
                return try MetalMosaicGenerator()
            } catch {
                logger.error("❌ Failed to create Metal mosaic generator: \(error.localizedDescription), falling back to standard")
                return MosaicGenerator()
            }
            
        case .auto:
            // Check if Metal is available and we're on Apple Silicon
            if isMetalAvailable() && isAppleSilicon() {
                logger.debug("🔧 Auto-selecting Metal mosaic generator (Apple Silicon detected)")
                do {
                    return try MetalMosaicGenerator()
                } catch {
                    logger.error("❌ Failed to create Metal mosaic generator: \(error.localizedDescription), falling back to standard")
                    return MosaicGenerator()
                }
            } else {
                logger.debug("🔧 Auto-selecting standard mosaic generator")
                return MosaicGenerator()
            }
        }
    }
    
    /// Check if Metal is available on this system
    /// - Returns: True if Metal is available
    private static func isMetalAvailable() -> Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }
    
    /// Check if we're running on Apple Silicon
    /// - Returns: True if running on Apple Silicon
    private static func isAppleSilicon() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    
    /// Get information about the available mosaic generators
    /// - Returns: A dictionary with information about the available generators
    public static func getGeneratorInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        // System information
        info["isAppleSilicon"] = isAppleSilicon()
        info["isMetalAvailable"] = isMetalAvailable()
        
        // Available generators
        info["availableGenerators"] = [
            "standard": true,
            "metal": isMetalAvailable()
        ]
        
        // Recommended generator
        if isMetalAvailable() && isAppleSilicon() {
            info["recommendedGenerator"] = "metal"
        } else {
            info["recommendedGenerator"] = "standard"
        }
        
        return info
    }
} 