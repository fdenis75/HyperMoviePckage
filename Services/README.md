# HyperMovieServices

Concrete implementations of the HyperMovie application services.

## Overview

The Services package provides concrete implementations of the protocols defined in the Core layer. This layer contains the actual business logic and implementations of:

- Application state management
- Video processing services
- Mosaic generation services
- Preview generation services
- File management services
- Progress tracking and error handling

This layer depends on both the Models layer for data types and the Core layer for protocols.

## Components

### Application State

- `AppState`: Concrete implementation of `AppStateManaging` protocol
- Manages application-wide state and configuration
- Handles persistence and data management
- Coordinates service interactions

### Video Processing

- `VideoProcessor`: Concrete implementation of `VideoProcessing` protocol
- `VideoProcessingService`: High-level video processing operations
- `VideoExportService`: Video export and format conversion

### Mosaic Generation

- `MosaicGenerator`: Concrete implementation of `MosaicGenerating` protocol
- `MosaicProcessingPipeline`: Configurable mosaic processing
- `LayoutProcessor`: Mosaic layout management

### Preview Generation

- `PreviewGenerator`: Concrete implementation of `PreviewGenerating` protocol
- `ThumbnailGenerator`: Thumbnail extraction
- `PreviewExportService`: Preview export management

## Usage

```swift
import HyperMovieServices
import HyperMovieCore
import HyperMovieModels

// Initialize application state
let appState = AppState()

// Use concrete video processor
let processor = VideoProcessor()
let video = try await processor.process(url: videoURL)

// Use concrete mosaic generator
let generator = MosaicGenerator()
try await generator.generate(for: video, config: config)

// Use concrete preview generator
let previewGenerator = PreviewGenerator()
try await previewGenerator.generate(for: video, config: config)
```

## Features

### Application State Management

- SwiftData integration
- Service coordination
- UI state management
- Processing state tracking

### Video Processing Implementation

- Efficient metadata extraction
- Optimized frame extraction
- Format conversion
- Error recovery strategies

### Mosaic Generation Implementation

- Custom layout algorithms
- Quality optimization
- Metadata overlay rendering
- Progress tracking

### Preview Generation Implementation

- Efficient frame sampling
- Quality optimization
- Frame rate handling
- Batch processing optimization

## Performance

### Optimization Strategies

- Concurrent processing
- Memory management
- Resource cleanup
- Cache management

### Error Handling Implementation

- Graceful degradation
- Error recovery mechanisms
- Progress tracking
- User feedback

## Dependencies

- HyperMovieCore: Core protocols and interfaces
- HyperMovieModels: Domain models
- Collections: Efficient data structures
- Logging: Logging support
- AsyncAlgorithms: Async operations

## Documentation

For detailed documentation, see:

- [Application State](AppState/README.md)
- [Video Processing](VideoProcessing/README.md)
- [Mosaic Generation](MosaicGeneration/README.md)
- [Preview Generation](PreviewGeneration/README.md)
- [Utilities](Utils/README.md)

## Testing

Unit and integration tests are located in `Tests/Services`.
