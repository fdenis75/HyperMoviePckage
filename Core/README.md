# HyperMovieCore

Core protocols and interfaces for the HyperMovie application.

## Overview

The Core package defines the contract between different parts of the application through protocols and interfaces. This layer contains:

- Service protocols that define the contract for video processing operations
- Interface definitions that establish how components interact
- Core extensions that provide shared functionality
- Abstract types that define common behaviors

This layer depends on the Models layer for data types but contains no concrete implementations.

## Components

### Service Protocols

- `VideoProcessing`: Protocol for video processing operations
- `MosaicGenerating`: Protocol for mosaic generation operations
- `PreviewGenerating`: Protocol for preview generation operations

### Core Interfaces

- `AppState`: Application state management interface
- `ProcessingPipeline`: Video processing pipeline interface
- `LibraryManagement`: Library management interface

### Extensions

- Core extensions for Foundation types
- Core extensions for AVFoundation types
- Core extensions for CoreImage types

### Utilities

- Common utility functions
- Shared helper types
- Reusable components

## Usage

```swift
import HyperMovieCore
import HyperMovieModels

// Define a video processor
class MyVideoProcessor: VideoProcessing {
    func process(url: URL) async throws -> Video {
        // Implementation
    }
}

// Define a mosaic generator
class MyMosaicGenerator: MosaicGenerating {
    func generate(for video: Video) async throws {
        // Implementation
    }
}

// Define a preview generator
class MyPreviewGenerator: PreviewGenerating {
    func generate(for video: Video) async throws {
        // Implementation
    }
}
```

## Dependencies

- HyperMovieModels: Domain models and types
- Logging: Logging support

## Documentation

For detailed documentation, see:

- [Protocols](Protocols/README.md)
- [Extensions](Extensions/README.md)
- [Utilities](Utilities/README.md)

## Testing

Unit tests are located in `Tests/Core`.
