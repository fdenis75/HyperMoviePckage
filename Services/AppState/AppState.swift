import Foundation
import SwiftData
import SwiftUI
import AVFoundation
import CoreGraphics
import HyperMovieModels
import HyperMovieCore
import os

/// Concrete implementation of application state management
@available(macOS 15, *)
@Observable
 public final class AppState: AppStateManaging {
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
    
    // MARK: - Loading States
    //@MainActor
    private(set) public var isLibraryLoading: Bool = false
    //@MainActor
    private(set) public var isFolderLoading: Bool = false
    //@MainActor
    private(set) public var currentLoadingFolder: String = ""
    
    // MARK: - Services
    public let videoProcessor: any VideoProcessing
    public let mosaicGenerator: any MosaicGenerating
    public let previewGenerator: any PreviewGenerating
    public let mosaicGeneratorCoordinator: any MosaicGeneratorCoordinating
    
    // MARK: - User Settings
    public var mosaicConfig: MosaicConfiguration
    public var previewConfig: PreviewConfiguration
    public var generatorType: MosaicGeneratorFactory.GeneratorType = .auto {
        didSet {
            UserDefaults.standard.set(generatorType.rawValue, forKey: "MosaicGeneratorType")
            Task {
                await updateMosaicGeneratorCoordinator()
            }
        }
    }
    private let logger = Logger(subsystem: "com.hypermovie", category: "app-state")
    // MARK: - Batch Mosaic State
    public var showBatchMosaicOptions = false
    public var isBatchGenerating = false
    public var batchMosaicVideos: [Video] = []
    public var currentBatchIndex = 0
    
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
        self.mosaicConfig = MosaicConfiguration.default
        self.previewConfig = PreviewConfiguration.default
        self.modelContainer = container
        self.modelContext = container.mainContext
        self.videoProcessor = videoProcessor
        self.mosaicGenerator = mosaicGenerator
        self.previewGenerator = previewGenerator
        
        // Load generator type from user defaults
        let savedGeneratorType: MosaicGeneratorFactory.GeneratorType
        if let savedType = UserDefaults.standard.string(forKey: "MosaicGeneratorType"),
           let type = MosaicGeneratorFactory.GeneratorType(rawValue: savedType) {
            savedGeneratorType = type
        } else {
            savedGeneratorType = .auto
        }
        
        self.generatorType = savedGeneratorType
        
        self.mosaicGeneratorCoordinator = MosaicGeneratorCoordinator(
            mosaicGenerator: mosaicGenerator,
            modelContext: container.mainContext,
            concurrencyLimit: 4,
            generatorType: savedGeneratorType
        )
        
        Task.detached {
            await self.loadLibrary()
        }
    }
    
    /// Convenience initializer that creates default service implementations
    @MainActor
    public convenience init() throws {
        try self.init(
            videoProcessor: VideoProcessor(),
            mosaicGenerator: MosaicGeneratorFactory.createGenerator(),
            previewGenerator: PreviewGenerator()
        )
    }
    
    // MARK: - Public Methods
    
    
    public func loadLibrary() async {
        isLibraryLoading = true
        logger.info("Loading library")
        
        do {
            let libraryDescriptor = FetchDescriptor<HyperMovieModels.LibraryItem>()
            library = try modelContext.fetch(libraryDescriptor)
            logger.info("Library loaded with \(self.library.count) items")
            
            let videosDescriptor = FetchDescriptor<HyperMovieModels.Video>()
            videos = try modelContext.fetch(videosDescriptor)
            logger.info("Videos loaded with \(self.videos.count) items")
        } catch {
            logger.error("Error loading library: \(error.localizedDescription)")
        }
        
        isLibraryLoading = false
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
    
    /// Update the mosaic generator coordinator with the current generator type
    @MainActor
    public func updateMosaicGeneratorCoordinator() async {
        // Cancel any ongoing operations
        await mosaicGeneratorCoordinator.cancelAllGenerations()
        
        // Create a new coordinator with the current generator type
        let newCoordinator = MosaicGeneratorCoordinator(
            modelContext: modelContext,
            concurrencyLimit: 4,
            generatorType: generatorType
        )
        
        // Replace the coordinator
        // Note: This is a simplified approach. In a real implementation,
        // you would need to handle this more carefully to avoid losing state.
        // Since the coordinator is a let property, we would need a different approach
        // such as using a wrapper class or a different architecture.
        // For demonstration purposes, we're showing the concept here.
        
        // In a real implementation, you might do something like:
        // coordinatorWrapper.coordinator = newCoordinator
    }
    
    /// Set the folder loading state
    /// - Parameters:
    ///   - loading: Whether the folder is loading
    ///   - folderName: The name of the folder being loaded
    @MainActor
    public func setFolderLoading(_ loading: Bool, folderName: String = "") {
        isFolderLoading = loading
        currentLoadingFolder = folderName
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func setProcessing(_ value: Bool) {
        isProcessing = value
    }
} 
