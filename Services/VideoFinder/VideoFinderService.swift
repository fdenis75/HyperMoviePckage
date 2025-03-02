import Foundation
import HyperMovieCore
import HyperMovieModels
import OSLog

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
            .creationDateKey
        ]
        
        // If not recursive, use contentsOfDirectory instead of enumerator
        if !recursive {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
            
            return try contents.filter { fileURL in
                guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                      let contentType = resourceValues.contentType,
                      let isDirectory = resourceValues.isDirectory,
                      !isDirectory else {
                    return false
                }
                
                return videoTypes.contains(contentType.identifier)
            }
        }
        
        // For recursive search, use enumerator
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        var videos: [URL] = []
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  let contentType = resourceValues.contentType,
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory else {
                continue
            }
            
            if videoTypes.contains(contentType.identifier) {
                videos.append(fileURL)
            }
        }
        
        logger.info("Found \(videos.count) videos in \(url.path)")
        return videos
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