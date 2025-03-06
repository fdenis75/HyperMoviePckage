import Foundation
import HyperMovieCore
import HyperMovieModels
import OSLog
import SwiftData

/// A service that handles finding video files in the system.
@available(macOS 15.0, *)
public actor VideoFinderService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "video-finder")
    private let signposter = OSSignposter(subsystem: "com.hypermovie", category: "video-finder-performance")
    
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
    /*
    public func findVideos(in url: URL, recursive: Bool = true) async throws -> [URL] {
        logger.info("Finding videos in folder: \(url.path), recursive: \(recursive)")
        
        guard url.hasDirectoryPath else {
            throw VideoFinderError.notADirectory(url)
        }
        
        let query = NSMetadataQuery()
       
        
        // Add location predicate
        /*let locationPredicate = NSPredicate(format: recursive ? 
            "kMDItemPath BEGINSWITH %@" : 
            "kMDItemPath BEGINSWITH %@ AND NOT kMDItemPath CONTAINS '/'", 
            url.path + "/"
        )
        predicates.append(locationPredicate)*/

        
        // Add video type predicates
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
         let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)

       // predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates))
       //query.predicate = typePredicate
        // Exclude hidden files
  
        // Combine all predicates
        query.predicate = typePredicate
        query.searchScopes = [url]
        query.sortDescriptors = [.init(key: "kMDItemFSName", ascending: true)]
        
        return try await withCheckedThrowingContinuation { @Sendable (continuation) in
            var updateObserver: NSObjectProtocol?
            var completionObserver: NSObjectProtocol?

            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { notification in
                Task {
                    let videos = (query.results as! [NSMetadataItem]).compactMap { item -> URL? in
                        guard let path = item.value(forAttribute: "kMDItemPath") as? String else {
                            return nil
                        }
                        let url = URL(fileURLWithPath: path)
                        
                        // Skip preview files
                        if url.lastPathComponent.lowercased().contains("-preview") {
                            return nil
                        }
                        
                        return url
                    }
                    
                    // Process preview files
                    let previewMap = Dictionary(grouping: videos.filter {
                        $0.lastPathComponent.lowercased().contains("-preview")
                    }) { url in
                        url.deletingPathExtension().deletingPathExtension()
                    }
                    
                    // Store preview information in UserDefaults
                    await MainActor.run {
                        UserDefaults.standard.set(previewMap.mapValues { $0.map { $0.path } }, 
                                               forKey: "VideoPreviewMap")
                    }
                    
                    continuation.resume(returning: Array(Set(videos)))
                    query.stop()
                }
            }
            
            DispatchQueue.main.async {
                query.start()
            }
        }
    }
    */
    public func findVideoFiles(
        in directory: URL,
        recursive: Bool = true,
        progress: ((String) async -> Void)? = nil
    ) async throws -> [URL] {
        let interval = signposter.beginInterval("Find Video Files", "dir: \(directory.lastPathComponent)")
        defer { signposter.endInterval("Find Video Files", interval) }
        
        let query = NSMetadataQuery()
        
        let querySetupInterval = signposter.beginInterval("Query Setup")
        let typePredicates = videoTypes.map { type in
            NSPredicate(format: "kMDItemContentTypeTree == %@", type)
        }
        
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates)
        query.predicate = typePredicate
        query.searchScopes = [directory]
        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemContentCreationDate", ascending: true)]
        signposter.endInterval("Query Setup", querySetupInterval)

        return try await withCheckedThrowingContinuation { @Sendable (continuation) in
            var completionObserver: NSObjectProtocol?
            var updateObserver: NSObjectProtocol?
            
            // Add observer for updates during the search
            updateObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryGatheringProgress,
                object: query,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else { return }
                if let currentItem = query.results.last as? NSMetadataItem,
                   let path = currentItem.value(forAttribute: "kMDItemPath") as? String {
                    Task {
                        await progress?(path)
                    }
                }
            }
            
            completionObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else {
                    if let completionObserver = completionObserver {
                        NotificationCenter.default.removeObserver(completionObserver)
                    }
                    if let updateObserver = updateObserver {
                        NotificationCenter.default.removeObserver(updateObserver)
                    }
                    continuation.resume(returning: [])
                    return
                }
                
                let processInterval = self.signposter.beginInterval("Process Query Results")
                let videos = (query.results as! [NSMetadataItem]).compactMap { item -> URL? in
                    guard let path = item.value(forAttribute: "kMDItemPath") as? String else {
                        return nil
                    }
                    let url = URL(fileURLWithPath: path)
                    return url.lastPathComponent.lowercased().contains("amprv") ? nil : url
                }
                
                if let completionObserver = completionObserver {
                    NotificationCenter.default.removeObserver(completionObserver)
                }
                if let updateObserver = updateObserver {
                    NotificationCenter.default.removeObserver(updateObserver)
                }
                
                self.signposter.endInterval("Process Query Results", processInterval)
                continuation.resume(returning: videos)
                query.stop()
            }
            
            let startInterval = signposter.beginInterval("Start Query")
            DispatchQueue.main.async {
                query.start()
                self.signposter.endInterval("Start Query", startInterval)
            }
        }
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
        
        // Add name filter - handle single and multiple names appropriately
        if let nameFilters = criteria.nameFilter {
            if nameFilters.count == 1 {
                predicates.append(NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", nameFilters[0]))
            } else if nameFilters.count > 1 {
                let namePredicates = nameFilters.map { name in
                    NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", name)
                }
                predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: namePredicates))
            }
        }
        
        // Add date range
        if let start = criteria.startDate, let end = criteria.endDate {
            predicates.append(NSPredicate(
                format: "kMDItemContentCreationDate >= %@ AND kMDItemContentCreationDate < %@",
                start as NSDate,
                end as NSDate
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
        let interval = signposter.beginInterval("Compare Content", "folder: \(folderURL.lastPathComponent)")
        defer { signposter.endInterval("Compare Content", interval) }
        
        logger.info("Comparing database content with folder: \(folderURL.path)")
        
        let scanInterval = signposter.beginInterval("Scan Folder")
        let folderVideos = try await findVideoFiles(in: folderURL, recursive: true)
        signposter.endInterval("Scan Folder", scanInterval)
        
        let compareInterval = signposter.beginInterval("Compare Results")
        let folderPaths = Set(folderVideos.map { $0.path })
        let dbPaths = Set(databaseVideos.map { $0.url.path })
        
        let missingVideos = folderVideos.filter { !dbPaths.contains($0.path) }
        let orphanedVideos = databaseVideos.filter { !folderPaths.contains($0.url.path) }
        signposter.endInterval("Compare Results", compareInterval)
        
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
            let videos = try await findVideoFiles(in: url, recursive: true)
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
} 
