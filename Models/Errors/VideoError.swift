import Foundation

/// Errors that can occur during video processing operations.
public enum VideoError: LocalizedError {
    /// The video track could not be found in the asset.
    case videoTrackNotFound(URL)
    
    /// The video file could not be found at the specified URL.
    case fileNotFound(URL)
    
    /// The video file could not be accessed due to permissions.
    case accessDenied(URL)
    
    /// The video file is corrupted or in an unsupported format.
    case invalidFormat(URL)
    
    /// The video processing operation failed.
    case processingFailed(URL, Error)
    
    /// The video metadata extraction failed.
    case metadataExtractionFailed(URL, Error)
    
    /// The video thumbnail generation failed.
    case thumbnailGenerationFailed(URL, Error)
    
    /// The video frame extraction failed.
    case frameExtractionFailed(URL, Error)  
    
    public var errorDescription: String? {
        switch self {
        case .videoTrackNotFound(let url):
            return "No video track found in file at \(url.path)"
        case .fileNotFound(let url):
            return "Video file not found at \(url.path)"
        case .accessDenied(let url):
            return "Access denied to video file at \(url.path)"
        case .invalidFormat(let url):
            return "Invalid or unsupported video format at \(url.path)"
        case .processingFailed(let url, let error):
            return "Failed to process video at \(url.path): \(error.localizedDescription)"
        case .metadataExtractionFailed(let url, let error):
            return "Failed to extract metadata from video at \(url.path): \(error.localizedDescription)"
        case .thumbnailGenerationFailed(let url, let error):
            return "Failed to generate thumbnail for video at \(url.path): \(error.localizedDescription)"
        case .frameExtractionFailed(let url, let error):
            return "Failed to extract frames from video at \(url.path): \(error.localizedDescription)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .videoTrackNotFound:
            return "The file does not contain a valid video track"
        case .fileNotFound:
            return "The specified file does not exist"
        case .accessDenied:
            return "The application does not have permission to access the file"
        case .invalidFormat:
            return "The file format is not supported or the file is corrupted"
        case .processingFailed(_, let error):
            return error.localizedDescription
        case .metadataExtractionFailed(_, let error):
            return error.localizedDescription
        case .thumbnailGenerationFailed(_, let error):
            return error.localizedDescription
        case .frameExtractionFailed(_, let error):
            return error.localizedDescription
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .videoTrackNotFound:
            return "Please ensure the file contains valid video content"
        case .fileNotFound:
            return "Please check if the file exists and try again"
        case .accessDenied:
            return "Please grant the application access to the file and try again"
        case .invalidFormat:
            return "Please try with a supported video format"
        case .processingFailed:
            return "Please try again or use a different video file"
        case .metadataExtractionFailed:
            return "Please ensure the video file is not corrupted and try again"
        case .thumbnailGenerationFailed:
            return "Please try again or adjust the thumbnail generation settings"
        case .frameExtractionFailed:
            return "Please try again or adjust the frame extraction settings"
        }
    }
} 