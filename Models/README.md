# HyperMovieModels

Domain models and data types for the HyperMovie application.

## Overview

The Models package provides the core domain models and data types for HyperMovie. This layer contains ONLY data structures and their associated types, with no business logic or service implementations.

## Components

### Models

- `Video`: Represents a video file with metadata and processing state
- `LibraryItem`: Represents an item in the video library (folder, smart folder, playlist)
- `SmartFolderCriteria`: Criteria for filtering videos in smart folders
- `VideoStatus`: Status of video processing operations
- `MosaicLayout`: Layout information for mosaic generation

### Configuration

- `ProcessingConfiguration`: Configuration for video processing
- `DensityConfig`: Configuration for mosaic generation
- `PreviewConfiguration`: Configuration for preview generation
- `OutputFormat`: Output format options for processing
- `LayoutConfiguration`: Visual and layout settings for mosaics

### Error Types

- `VideoError`: Errors in video processing
- `MosaicError`: Errors in mosaic generation
- `LibraryError`: Errors in library operations
- `ProcessingError`: General processing errors

## Usage

```swift
import HyperMovieModels

// Create a video
let video = Video(url: videoURL)

// Create a library item
let folder = LibraryItem(
    name: "My Videos",
    type: .folder
)

// Configure processing
let config = ProcessingConfiguration(
    width: 1920,
    density: .default,
    format: .jpeg
)

// Create smart folder criteria
let criteria = SmartFolderCriteria(
    dateRange: DateInterval(start: startDate, end: endDate),
    keywords: ["vacation", "family"]
)

// Create mosaic layout
let layout = MosaicLayout(
    rows: 4,
    cols: 6,
    thumbnailSize: CGSize(width: 320, height: 180),
    positions: positions,
    thumbCount: 24,
    thumbnailSizes: sizes,
    mosaicSize: CGSize(width: 1920, height: 1080)
)
```

## Features

### Video Model

- Comprehensive metadata support
- Processing status tracking
- File management
- Thumbnail management

### Library Model

- Hierarchical organization
- Smart folder support
- Playlist management
- Batch operations

### Configuration

- Flexible processing options
- Quality settings
- Format options
- Layout customization

### Layout System

- Automatic layout calculation
- Custom layout support
- Aspect ratio preservation
- Screen-aware sizing

## Dependencies

- Collections: Efficient data structures

## Documentation

For detailed documentation, see:

- [Models](Models/README.md)
- [Configuration](Configuration/README.md)
- [Errors](Errors/README.md)
- [Layout](Layout/README.md)

## Testing

Unit tests are located in `Tests/Models`. 