# Layout Models

Models for handling mosaic and thumbnail layouts in HyperMovie.

## Overview

The Layout module provides models for representing and managing the layout of mosaics and thumbnails. These models are used by the mosaic generation services to determine how frames should be arranged and sized.

## Models

### MosaicLayout

Represents the complete layout information for a mosaic:

```swift
public struct MosaicLayout: Codable, Sendable {
    public let rows: Int
    public let cols: Int
    public let thumbnailSize: CGSize
    public let positions: [(x: Int, y: Int)]
    public let thumbCount: Int
    public let thumbnailSizes: [CGSize]
    public let mosaicSize: CGSize
}
```

#### Properties

- `rows`: Number of rows in the mosaic grid
- `cols`: Number of columns in the mosaic grid
- `thumbnailSize`: Base size for thumbnails
- `positions`: Array of (x,y) coordinates for each thumbnail
- `thumbCount`: Total number of thumbnails
- `thumbnailSizes`: Array of individual thumbnail sizes (may vary in custom layouts)
- `mosaicSize`: Total size of the mosaic

#### Usage

```swift
let layout = MosaicLayout(
    rows: 4,
    cols: 6,
    thumbnailSize: CGSize(width: 320, height: 180),
    positions: [(0, 0), (320, 0), ...],
    thumbCount: 24,
    thumbnailSizes: Array(repeating: CGSize(width: 320, height: 180), count: 24),
    mosaicSize: CGSize(width: 1920, height: 1080)
)
```

## Features

- Codable support for persistence
- Screen-aware sizing
- Support for variable thumbnail sizes
- Efficient position calculation
- Aspect ratio preservation

## Related Types

- `LayoutConfiguration`: Configuration for layout settings
- `DensityConfig`: Controls thumbnail density and spacing
- `AspectRatio`: Predefined aspect ratios for layouts
- `VisualSettings`: Visual customization options 