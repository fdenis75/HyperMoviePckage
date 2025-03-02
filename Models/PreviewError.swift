import Foundation

/// Errors that can occur during preview generation
public enum PreviewError: LocalizedError {
    /// Unable to create composition tracks
    case unableToCreateCompositionTracks
    /// Unable to create export session
    case unableToCreateExportSession
    /// Failed to insert or scale segment
    case segmentInsertionFailed
    
    public var errorDescription: String? {
        switch self {
        case .unableToCreateCompositionTracks:
            return "Unable to create composition tracks"
        case .unableToCreateExportSession:
            return "Unable to create export session"
        case .segmentInsertionFailed:
            return "Failed to insert or scale segment"
        }
    }
} 