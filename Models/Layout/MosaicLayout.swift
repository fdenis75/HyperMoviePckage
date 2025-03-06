import Foundation
import CoreGraphics

/// A model representing the layout of a mosaic.
@available(macOS 15.0, *)
public struct MosaicLayout: Codable, Sendable {
    /// The number of rows in the mosaic.
    public let rows: Int
    
    /// The number of columns in the mosaic.
    public let cols: Int
    
    /// The size of each thumbnail.
    public let thumbnailSize: CGSize
    
    /// The positions of each thumbnail in the mosaic.
    public let positions: [Position]
    
    /// The total number of thumbnails.
    public let thumbCount: Int
    
    /// The sizes of each thumbnail (may vary for custom layouts).
    public let thumbnailSizes: [CGSize]
    
    /// The total size of the mosaic.
    public let mosaicSize: CGSize
    
    /// Creates a new MosaicLayout instance.
    /// - Parameters:
    ///   - rows: The number of rows.
    ///   - cols: The number of columns.
    ///   - thumbnailSize: The size of each thumbnail.
    ///   - positions: The positions of each thumbnail.
    ///   - thumbCount: The total number of thumbnails.
    ///   - thumbnailSizes: The sizes of each thumbnail.
    ///   - mosaicSize: The total size of the mosaic.
    public init(
        rows: Int,
        cols: Int,
        thumbnailSize: CGSize,
        positions: [(x: Int, y: Int)],
        thumbCount: Int,
        thumbnailSizes: [CGSize],
        mosaicSize: CGSize
    ) {
        self.rows = rows
        self.cols = cols
        self.thumbnailSize = thumbnailSize
        self.positions = positions.map(Position.init)
        self.thumbCount = thumbCount
        self.thumbnailSizes = thumbnailSizes
        self.mosaicSize = mosaicSize
    }
    public init(thumbnailSize: CGSize) {
        self.rows = 1
        self.cols = 1
        self.thumbnailSize = thumbnailSize
        self.positions = [(x: 0, y: 0)].map(Position.init)
        self.thumbCount = 1
        self.thumbnailSizes = [thumbnailSize]
        self.mosaicSize = CGSize(width: 0, height: 0)
    }
}

// MARK: - Position Type

public struct Position: Codable, Sendable {
    public let x: Int
    public let y: Int
    
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

// MARK: - Codable Support

@available(macOS 15.0, *)
extension MosaicLayout {
    private enum CodingKeys: String, CodingKey {
        case rows, cols, thumbnailSize, positions, thumbCount, thumbnailSizes, mosaicSize
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decode(Int.self, forKey: .rows)
        cols = try container.decode(Int.self, forKey: .cols)
        thumbnailSize = try container.decode(CGSizeCodable.self, forKey: .thumbnailSize).size
        positions = try container.decode([Position].self, forKey: .positions)
        thumbCount = try container.decode(Int.self, forKey: .thumbCount)
        thumbnailSizes = try container.decode([CGSizeCodable].self, forKey: .thumbnailSizes).map(\.size)
        mosaicSize = try container.decode(CGSizeCodable.self, forKey: .mosaicSize).size
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rows, forKey: .rows)
        try container.encode(cols, forKey: .cols)
        try container.encode(CGSizeCodable(size: thumbnailSize), forKey: .thumbnailSize)
        try container.encode(positions, forKey: .positions)
        try container.encode(thumbCount, forKey: .thumbCount)
        try container.encode(thumbnailSizes.map(CGSizeCodable.init), forKey: .thumbnailSizes)
        try container.encode(CGSizeCodable(size: mosaicSize), forKey: .mosaicSize)
    }
}

/// Helper struct for encoding/decoding CGSize
private struct CGSizeCodable: Codable {
    let width: Double
    let height: Double
    
    var size: CGSize {
        CGSize(width: width, height: height)
    }
    
    init(size: CGSize) {
        self.width = size.width
        self.height = size.height
    }
} 