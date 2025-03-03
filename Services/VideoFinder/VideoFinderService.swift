import Foundation
import HyperMovieCore
import HyperMovieModels
import OSLog
import SwiftData

/// A service that handles finding video files in the system.
@available(macOS 14.0, *)
public actor VideoFinderService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "video-finder")
    
    /// Supported video file types
    private let videoTypes = [
        "public.mpeg-4",
        "public.movie",
        "com.apple.quicktime-movie",
        "public.avi",
        "public.mpeg"
    ]
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// Find all videos in a folder.
    /// - Parameters:
    ///   - url: The folder URL to search in.
    ///   - recursive: Whether to search in subfolders. Defaults to true.
    /// - Returns: An array of found video URLs.
    public func findVideos(in url: URL, recursive: Bool = true) async throws -> [URL] {
        logger.info("Finding videos in folder: \(url.path), recursive: \(recursive)")
        
        guard url.hasDirectoryPath else {
            throw VideoFinderError.notADirectory(url)
        }
        
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .contentTypeKey,
            .fileSizeKey,
            .creationDateKey,
            .fileResourceIdentifierKey,
            .parentDirectoryURLKey // For deduplication
        ]
        
        // Use Set to automatically handle duplicates
        var uniqueVideos: Set<URL> = []
        var processedIdentifiers: Set<String> = []
        var previewMap: [URL: [URL]] = [:] // Map original videos to their previews
        
        // Helper function to process URL
        func processURL(_ fileURL: URL) throws -> Bool {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  let contentType = resourceValues.contentType,
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory else {
                return false
            }
            
            // Skip hidden files
            if fileURL.lastPathComponent.hasPrefix(".") {
                return false
            }
            
            // Get unique identifier for the file
            if let fileID = resourceValues.fileResourceIdentifier as? String {
                if processedIdentifiers.contains(fileID) {
                    return false
                }
                processedIdentifiers.insert(fileID)
            }
            
            // Check if it's a video file
            guard videoTypes.contains(contentType.identifier) else {
                return false
            }
            
            // Check if it's a preview file
            let filename = fileURL.lastPathComponent.lowercased()
            if filename.contains("-preview") {
                // Find the original video file
                let originalName = filename.replacingOccurrences(of: "-preview", with: "")
                let parentURL = resourceValues.parentDirectory
                
                // Break down the complex comparison
                let matchingVideos = uniqueVideos.filter { url in
                    let urlName = url.deletingPathExtension().lastPathComponent.lowercased()
                    let originalNameComponents = originalName.components(separatedBy: ".")
                    let originalNameStripped = originalNameComponents[0].lowercased()
                    let sameParent = url.deletingLastPathComponent() == parentURL
                    return urlName == originalNameStripped && sameParent
                }
                
                if let originalURL = matchingVideos.first {
                    if previewMap[originalURL] == nil {
                        previewMap[originalURL] = []
                    }
                    previewMap[originalURL]?.append(fileURL)
                }
                return false
            }
            
            return true
        }
        
        // If not recursive, use contentsOfDirectory
        if !recursive {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in contents {
                if try processURL(fileURL) {
                    uniqueVideos.insert(fileURL)
                }
            }
            
            return Array(uniqueVideos)
        }
        
        // For recursive search, use enumerator starting from the specified folder
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if try processURL(fileURL) {
                uniqueVideos.insert(fileURL)
            }
        }
        
        // Store preview information in UserDefaults for later use
        await MainActor.run {
            UserDefaults.standard.set(previewMap.mapValues { $0.map { $0.path } }, forKey: "VideoPreviewMap")
        }
        
        logger.info("Found \(uniqueVideos.count) unique videos in \(url.path)")
        return Array(uniqueVideos)
    }
    
    /// Find videos created between specific dates.
    /// - Parameters:
    ///   - start: The start date.
    ///   - end: The end date.
    /// - Returns: An array of found video URLs.
    public func findVideos(between start: Date, and end: Date) async throws -> [URL] {
        logger.info("Finding videos between \(start) and \(end)")
        
        let query = NSMetadataQuery()
        
        let datePredicate = NSPredicate(
            format: "kMDItemContentCreationDate >= %@ AND kMDItemContentCreationDate < %@",
            start as NSDate,
            end as NSDate
        )
        
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
        
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, typePredicate])
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [.init(key: "kMDItemContentCreationDate", ascending: true)]
        
        return try await withCheckedThrowingContinuation { continuation in
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                let videos = (query.results as! [NSMetadataItem]).compactMap { item -> URL? in
                    guard let path = item.value(forAttribute: "kMDItemPath") as? String else {
                        return nil
                    }
                    let url = URL(fileURLWithPath: path)
                    // Filter out certain file types
                    return (url.lastPathComponent.lowercased().contains("amprv") || 
                            url.pathExtension.lowercased().contains("rmvb")) ? nil : url
                }
                continuation.resume(returning: videos)
                query.stop()
            }
            
            DispatchQueue.main.async {
                query.start()
            }
        }
    }
    
    /// Find videos created today.
    /// - Returns: An array of found video URLs.
    public func findTodayVideos() async throws -> [URL] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        return try await findVideos(between: today, and: tomorrow)
    }
    
    /// Find videos in a smart folder based on criteria.
    /// - Parameter criteria: The criteria to filter videos.
    /// - Returns: An array of found video URLs.
    public func findVideos(matching criteria: SmartFolderCriteria) async throws -> [URL] {
        logger.info("Finding videos matching criteria")
        
        let query = NSMetadataQuery()
        var predicates: [NSPredicate] = []
        
        // Add name filter
        if let nameFilter = criteria.nameFilter {
            predicates.append(NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", nameFilter))
        }
        
        // Add date range
        if let dateRange = criteria.dateRange {
            predicates.append(NSPredicate(
                format: "kMDItemContentCreationDate >= %@ AND kMDItemContentCreationDate < %@",
                dateRange.start as NSDate,
                dateRange.end as NSDate
            ))
        }
        
        // Add file size range
        if let minSize = criteria.minSize {
            predicates.append(NSPredicate(format: "kMDItemFSSize >= %lld", minSize))
        }
        if let maxSize = criteria.maxSize {
            predicates.append(NSPredicate(format: "kMDItemFSSize <= %lld", maxSize))
        }
        
        // Add video type filter
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
        predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates))
        
        // Combine all predicates
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [.init(key: "kMDItemContentCreationDate", ascending: false)]
        
        return try await withCheckedThrowingContinuation { continuation in
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                let videos = (query.results as! [NSMetadataItem]).compactMap { item -> URL? in
                    guard let path = item.value(forAttribute: "kMDItemPath") as? String else {
                        return nil
                    }
                    return URL(fileURLWithPath: path)
                }
                continuation.resume(returning: videos)
                query.stop()
            }
            
            DispatchQueue.main.async {
                query.start()
            }
        }
    }
    
    /// Compare database content with folder content and identify discrepancies
    /// - Parameters:
    ///   - databaseVideos: Array of Video objects from the database
    ///   - folderURL: URL of the folder to scan
    /// - Returns: A tuple containing missing videos (in folder but not in DB) and orphaned videos (in DB but not in folder)
    public func compareContent(databaseVideos: [Video], folderURL: URL) async throws -> (missing: [URL], orphaned: [Video]) {
        logger.info("Comparing database content with folder: \(folderURL.path)")
        
        // Get all videos in the folder
        let folderVideos = try await findVideos(in: folderURL, recursive: true)
        let folderPaths = Set(folderVideos.map { $0.path })
        
        // Get all video paths from database
        let dbPaths = Set(databaseVideos.map { $0.url.path })
        
        // Find missing videos (in folder but not in DB)
        let missingVideos = folderVideos.filter { !dbPaths.contains($0.path) }
        
        // Find orphaned videos (in DB but not in folder)
        let orphanedVideos = databaseVideos.filter { !folderPaths.contains($0.url.path) }
        
        logger.info("""
        Content comparison results:
        - Missing videos (need to be added to DB): \(missingVideos.count)
        - Orphaned videos (not found in folder): \(orphanedVideos.count)
        """)
        
        return (missingVideos, orphanedVideos)
    }
    
    /// Delete all data related to a folder including database entries, thumbnails, and cached data.
    /// - Parameters:
    ///   - url: The folder URL to delete data for.
    ///   - confirmationHandler: A closure that will be called before deletion to confirm the action.
    ///   - modelContext: The SwiftData ModelContext to delete database entries.
    /// - Returns: A tuple containing the number of items deleted and any error that occurred.
    public func deleteAllData(for url: URL, modelContext: ModelContext, confirmationHandler: @escaping (String) -> Bool) async -> (itemsDeleted: Int, error: Error?) {
        logger.info("Preparing to delete all data for folder: \(url.path)")
        
        // Count items to be deleted
        var itemCount = 0
        do {
            let videos = try await findVideos(in: url, recursive: true)
            itemCount = videos.count
            
            // Prepare warning message
            let warningMessage = """
            WARNING: You are about to delete all data related to folder: \(url.lastPathComponent)
            This will remove:
            - \(itemCount) video entries from the database
            - All associated thumbnails and preview files
            - All cached data and metadata
            
            This action cannot be undone. Do you want to proceed?
            """
            
            // Get confirmation
            let shouldProceed = await MainActor.run {
                confirmationHandler(warningMessage)
            }
            
            guard shouldProceed else {
                logger.info("Deletion cancelled by user")
                return (0, nil)
            }
            
            // Delete data
            var deletedCount = 0
            for videoURL in videos {
                // Remove from UserDefaults preview map
                if var previewMap = UserDefaults.standard.dictionary(forKey: "VideoPreviewMap") {
                    previewMap.removeValue(forKey: videoURL.path)
                    await MainActor.run {
                        UserDefaults.standard.set(previewMap, forKey: "VideoPreviewMap")
                    }
                }
                
                // Delete thumbnails directory for this video
                let thumbnailsDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Thumbnails")
                    .appendingPathComponent(videoURL.lastPathComponent)
                try? FileManager.default.removeItem(at: thumbnailsDir)
                
                // Delete from database
                await MainActor.run {
                    let descriptor = FetchDescriptor<Video>(
                        predicate: #Predicate<Video> { video in
                            video.url.path == videoURL.path
                        }
                    )
                    if let videos = try? modelContext.fetch(descriptor) {
                        videos.forEach { modelContext.delete($0) }
                    }
                    try? modelContext.save()
                }
                
                deletedCount += 1
            }
            
            logger.info("Successfully deleted data for \(deletedCount) videos")
            return (deletedCount, nil)
            
        } catch {
            logger.error("Failed to delete data: \(error.localizedDescription)")
            return (0, error)
        }
    }
}

/// Errors that can occur during video finding operations.
public enum VideoFinderError: LocalizedError {
    /// The specified path is not a directory.
    case notADirectory(URL)
    /// Failed to access the directory.
    case accessDenied(URL)
    /// Failed to enumerate directory contents.
    case enumerationFailed(URL, Error)
    /// Failed to execute metadata query.
    case queryFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .notADirectory(let url):
            return "The path is not a directory: \(url.path)"
        case .accessDenied(let url):
            return "Access denied to directory: \(url.path)"
        case .enumerationFailed(let url, let error):
            return "Failed to enumerate directory \(url.path): \(error.localizedDescription)"
        case .queryFailed(let error):
            return "Failed to execute metadata query: \(error.localizedDescription)"
        }
    }
} 
