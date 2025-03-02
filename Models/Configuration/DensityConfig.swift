import Foundation

public struct DensityConfig: Equatable, Hashable, Codable, Sendable {
    public let name: String
    public let factor: Double
    public let extractsMultiplier: Double
    public let thumbnailCountDescription: String
    
    // MARK: - Codable
    private enum CodingKeys: String, CodingKey {
        case factor
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(factor, forKey: .factor)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let factor = try container.decode(Double.self, forKey: .factor)
        
        // Find the matching case based on factor
        if let config = DensityConfig.allCases.first(where: { $0.factor == factor }) {
            self = config
        } else {
            // Default to .s if no match found
            self = .s
        }
    }
    
    public init(name: String, factor: Double, extractsMultiplier: Double, thumbnailCountDescription: String) {
        self.name = name
        self.factor = factor
        self.extractsMultiplier = extractsMultiplier
        self.thumbnailCountDescription = thumbnailCountDescription
    }
    
    public static let xxl = DensityConfig(name: "XXL", factor: 0.25, extractsMultiplier: 0.25, thumbnailCountDescription: "minimal")
    public static let xl = DensityConfig(name: "XL", factor: 0.5, extractsMultiplier: 0.5, thumbnailCountDescription: "low")
    public static let l = DensityConfig(name: "L", factor: 0.75, extractsMultiplier: 0.75, thumbnailCountDescription: "medium")
    public static let m = DensityConfig(name: "M", factor: 1.0, extractsMultiplier: 1.0, thumbnailCountDescription: "high")        
    public static let s = DensityConfig(name: "S", factor: 2.0, extractsMultiplier: 1.5, thumbnailCountDescription: "very high")
    public static let xs = DensityConfig(name: "XS", factor: 3.0, extractsMultiplier: 2.0, thumbnailCountDescription: "super high")
    public static let xxs = DensityConfig(name: "XXS", factor: 4.0, extractsMultiplier: 3.0, thumbnailCountDescription: "maximal")
    
    public static let allCases = [xxl, xl, l, m, s, xs, xxs]
    public static let `default` = m
} 