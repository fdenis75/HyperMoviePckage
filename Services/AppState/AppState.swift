import Foundation
import SwiftData
import SwiftUI
import AVFoundation
import CoreGraphics
import HyperMovieModels
import HyperMovieCore

/// Concrete implementation of application state management
@available(macOS 15, *)
@Observable public final class AppState: AppStateManaging {
    // MARK: - SwiftData
 
    public var modelContext: ModelContext
    public var modelContainer: ModelContainer
    
    // MARK: - Properties
    public var library: [HyperMovieModels.LibraryItem] = []
    public var videos: [HyperMovieModels.Video] = []
    
    // MARK: - Window Management
    public var showPreferences = false
    public var showImportDialog = false
    public var showPreviewPanel = true
    
    // MARK: - Sidebar Configuration
    public var sidebarWidth: CGFloat = 260
    public var isSidebarVisible = true
    
    // MARK: - Processing State
    @MainActor
    private(set) public var isProcessing: Bool = false
    public var processingProgress: Double = 0
    public var currentProcessingTask: String = ""
    
    // MARK: - Services
    public let videoProcessor: any VideoProcessing
    public let mosaicGenerator: any MosaicGenerating
    public let previewGenerator: any PreviewGenerating
    
    // MARK: - User Settings
    public var mosaicConfig = MosaicConfiguration.default
    public var previewConfig = PreviewConfiguration.default
    
    
    // MARK: - Initialization
    
    @MainActor
    public init(
        videoProcessor: any VideoProcessing,
        mosaicGenerator: any MosaicGenerating,
        previewGenerator: any PreviewGenerating
    ) throws {
        let schema = Schema([
            HyperMovieModels.Video.self,
            HyperMovieModels.LibraryItem.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        
        self.modelContainer = container
        self.modelContext = container.mainContext
        self.videoProcessor = videoProcessor
        self.mosaicGenerator = mosaicGenerator
        self.previewGenerator = previewGenerator
        
        Task {
            await loadLibrary()
        }
    }
    
    /// Convenience initializer that creates default service implementations
    @MainActor
    public convenience init() throws {
        try self.init(
            videoProcessor: VideoProcessor(),
            mosaicGenerator: MosaicGenerator(),
            previewGenerator: PreviewGenerator()
        )
    }
    
    // MARK: - Public Methods
    
    @MainActor
    public func loadLibrary() async {
        let libraryDescriptor = FetchDescriptor<HyperMovieModels.LibraryItem>()
        library = (try? modelContext.fetch(libraryDescriptor)) ?? []
        
        let videosDescriptor = FetchDescriptor<HyperMovieModels.Video>()
        videos = (try? modelContext.fetch(videosDescriptor)) ?? []
    }
    
    public func addVideos(at urls: [URL]) async throws {
        await setProcessing(true)
        defer { Task { await setProcessing(false) } }
        
        for url in urls {
            let video = try await videoProcessor.process(url: url)
            await MainActor.run {
                modelContext.insert(video)
                videos.append(video)
            }
        }
        
        try await MainActor.run {
            try modelContext.save()
        }
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func setProcessing(_ value: Bool) {
        isProcessing = value
    }
} 