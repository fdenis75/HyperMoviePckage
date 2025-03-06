import Foundation
import SwiftUI
import OSLog
import Combine
import HyperMovieModels
import HyperMovieServices
import SwiftData
@MainActor
@available(macOS 15.0, *)
public class FolderDiscoveryViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var isDiscovering = false
    @Published private(set) var progress: DiscoveryProgress?
    @Published private(set) var lastError: Error?
    @Published private(set) var lastResult: DiscoveryResult?
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "folder-discovery-ui")
    
    // MARK: - Public Properties
    
    public let discoveryService: FolderDiscoveryService
    
    // MARK: - Initialization
    
    public init(discoveryService: FolderDiscoveryService) {
        self.discoveryService = discoveryService
    }
    
    // MARK: - Public Methods
    
    /// Creates folder structure for all videos in the result
    /// - Parameter modelContext: The SwiftData ModelContext to use
    /// - Returns: Array of all created or existing LibraryItems
    @available(macOS 15, *)
    public func createFolderStructure(for videos: [Video], in modelContext: ModelContext) -> [HyperMovieModels.LibraryItem] {
        var allItems: [HyperMovieModels.LibraryItem] = []
        
        for video in videos {
            let items = video.createFolderStructure(in: modelContext)
            for item in items {
                if !allItems.contains(where: { $0.id == item.id }) {
                    allItems.append(item)
                }
            }
        }
        
        return allItems
    }
    
    @available(macOS 15, *)
    public func discoverFolder(
        at url: URL,
        recursive: Bool = true,
        generateThumbnails: Bool = true
    ) async {
        isDiscovering = true
        progress = nil
        lastError = nil
        lastResult = nil
        
        do {
            let options = FolderDiscoveryOptions(
                recursive: recursive,
                generateThumbnails: generateThumbnails
            )
            
            lastResult = try await discoveryService.discoverFolder(
                at: url,
                options: options,
                delegate: self
            )
        } catch {
            logger.error("Failed to discover folder: \(error)")
            lastError = error
        }
        
        isDiscovering = false
    }
    @available(macOS 15, *)
    public func discoverSmartFolder(
        criteria: HyperMovieModels.SmartFolderCriteria,
        generateThumbnails: Bool = true
    ) async {
        isDiscovering = true
        progress = nil
        lastError = nil
        lastResult = nil
        
        do {
            let options = SmartFolderDiscoveryOptions(
                criteria: criteria,
                generateThumbnails: generateThumbnails
            )
            
            lastResult = try await discoveryService.discoverSmartFolder(
                options: options,
                delegate: self
            )
        } catch {
            logger.error("Failed to discover smart folder: \(error)")
            lastError = error
        }
        
        isDiscovering = false
    }
    @available(macOS 15, *)
    public func checkThumbnails(at url: URL) async -> [Video] {
        do {
            return try await discoveryService.checkThumbnails(at: url)
        } catch {
            logger.error("Failed to check thumbnails: \(error)")
            lastError = error
            return []
        }
    }
    @available(macOS 15, *)
    public func regenerateThumbnails(for videos: [Video]) async {
        isDiscovering = true
        progress = nil
        lastError = nil
        
        do {
            try await discoveryService.regenerateThumbnails(
                for: videos,
                delegate: self
            )
        } catch {
            logger.error("Failed to regenerate thumbnails: \(error)")
            lastError = error
        }
        
        isDiscovering = false
    }
    @available(macOS 15, *)
    public func cancel() {
        Task {
            await discoveryService.cancelDiscovery()
        }
    }
}

// MARK: - FolderDiscoveryDelegate
@available(macOS 15.0, *)
extension FolderDiscoveryViewModel: FolderDiscoveryDelegate {
    public func discoveryProgressDidUpdate(_ progress: DiscoveryProgress) {
        self.progress = progress
    }
    
    public func discoveryDidEncounterError(_ error: Error) {
        lastError = error
    }
    
    public func discoveryDidCancel() {
        isDiscovering = false
    }
    
    public func discoveryDidComplete(result: DiscoveryResult) {
        lastResult = result
    }
} 
