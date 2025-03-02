import Foundation
import SwiftUI
import SwiftData
import HyperMovieModels

/// Protocol defining the interface for application state management
@available(macOS 15, *)
public protocol AppStateManaging: Observable {
    // MARK: - Properties
    
    /// The library items in the application
    var library: [HyperMovieModels.LibraryItem] { get set }
    
    /// The videos in the application
    var videos: [HyperMovieModels.Video] { get set }
    
    /// Whether the preferences window is shown
    var showPreferences: Bool { get set }
    
    /// Whether the import dialog is shown
    var showImportDialog: Bool { get set }
    
    /// Whether the preview panel is shown
    var showPreviewPanel: Bool { get set }
    
    /// The width of the sidebar
    var sidebarWidth: CGFloat { get set }
    
    /// Whether the sidebar is visible
    var isSidebarVisible: Bool { get set }
    
    /// Whether processing is in progress
    var isProcessing: Bool { get }
    
    /// The current processing progress (0.0 to 1.0)
    var processingProgress: Double { get set }
    
    /// The current processing task description
    var currentProcessingTask: String { get set }
    
    /// The mosaic configuration
    var mosaicConfig: HyperMovieModels.MosaicConfiguration { get set }
    
    /// The preview configuration
    var previewConfig: HyperMovieModels.PreviewConfiguration { get set }
    
    // MARK: - Services
    
    /// The video processing service
    var videoProcessor: VideoProcessing { get }
    
    /// The library scanning service
    
    /// The mosaic generation service
    var mosaicGenerator: any MosaicGenerating { get }
    
    /// The preview generation service
    var previewGenerator: any PreviewGenerating { get }
    
    /// The SwiftData model context
    var modelContext: ModelContext { get }
    var modelContainer: ModelContainer { get }
    
    // MARK: - Methods
    
    /// Load the library from persistent storage
    func loadLibrary() async throws
    
    /// Add videos at the specified URLs
    /// - Parameter urls: The URLs of the videos to add
    func addVideos(at urls: [URL]) async throws
} 