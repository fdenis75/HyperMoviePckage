import Foundation
import SwiftData
import HyperMovieModels

/// Types of library items.
public enum LibraryItemType: String, Codable, Hashable {
    case folder
    case smartFolder
    case playlist
    
    public var name: String {
        switch self {
        case .folder: return "Folder"
        case .smartFolder: return "Smart Folder"
        case .playlist: return "Playlist"
        }
    }
    
    public var icon: String {
        switch self {
        case .folder: return "folder.fill"
        case .smartFolder: return "folder.badge.gearshape"
        case .playlist: return "play.square.stack"
        }
    }
}

/// A model representing an item in the library (folder, smart folder, or playlist).
@Model
public final class LibraryItem {
    // MARK: - Properties
    
    /// The unique identifier for the item.
    public var id: UUID
    
    /// The name of the item.
    public var name: String
    
    /// The type of the item (stored as string).
    public var typeString: String
    
    /// The URL of the folder (for folder type items).
    public var url: URL?
    
    /// The date the item was created.
    public var dateCreated: Date
    
    /// The date the item was last modified.
    public var dateModified: Date
    
    // MARK: - Computed Properties
    
    /// The type of the item.
    public var type: LibraryItemType {
        get {
            LibraryItemType(rawValue: typeString) ?? .folder
        }
        set {
            typeString = newValue.rawValue
        }
    }
    
    // MARK: - Initialization
    
    public init(
        id: UUID = UUID(),
        name: String,
        type: LibraryItemType,
        url: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.typeString = type.rawValue
        self.url = url
        self.dateCreated = Date()
        self.dateModified = Date()
    }
}

extension LibraryItem: Identifiable {}
/*
/// Criteria for filtering videos in a smart folder.
@available(macOS 15, *)
public struct SmartFolderCriteria: Codable {
    /// The date range for video creation.
    public var dateRange: DateInterval?
    
    /// The minimum duration in seconds.
    public var minDuration: Double?
    
    /// The maximum duration in seconds.
    public var maxDuration: Double?
    
    /// The minimum file size in bytes.
    public var minFileSize: Int64?
    
    /// The maximum file size in bytes.
    public var maxFileSize: Int64?
    
    /// Keywords to match in video titles.
    public var keywords: [String]
    
    /// File path patterns to match.
    public var pathPatterns: [String]
    
    /// Creates a new SmartFolderCriteria instance.
    public init(
        dateRange: DateInterval? = nil,
        minDuration: Double? = nil,
        maxDuration: Double? = nil,
        minFileSize: Int64? = nil,
        maxFileSize: Int64? = nil,
        keywords: [String] = [],
        pathPatterns: [String] = []
    ) {
        self.dateRange = dateRange
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.minFileSize = minFileSize
        self.maxFileSize = maxFileSize
        self.keywords = keywords
        self.pathPatterns = pathPatterns
    }
    
    /// Evaluates whether a video matches the criteria.
    /// - Parameter video: The video to evaluate.
    /// - Returns: True if the video matches the criteria, false otherwise.
    public func matches(_ video: Video) -> Bool {
        // Check date range
        if let dateRange = dateRange,
           !dateRange.contains(video.dateAdded) {
            return false
        }
        
        // Check duration
        if let minDuration = minDuration,
           video.duration < minDuration {
            return false
        }
        if let maxDuration = maxDuration,
           video.duration > maxDuration {
            return false
        }
        
        // Check file size
        if let minFileSize = minFileSize, let fileSize = video.fileSize {
            if fileSize < minFileSize { return false }
        }
        if let maxFileSize = maxFileSize, let fileSize = video.fileSize {
            if fileSize > maxFileSize { return false }
        }
        
        // Check keywords
        if !keywords.isEmpty {
            let title = video.title.lowercased()
            if !keywords.contains(where: { title.contains($0.lowercased()) }) {
                return false
            }
        }
        
        // Check path patterns
        if !pathPatterns.isEmpty {
            let path = video.url.path
            if !pathPatterns.contains(where: { path.contains($0) }) {
                return false
            }
        }
        
        return true
    }
}
*/
@available(macOS 15, *)
extension LibraryItem: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        LibraryItem(
            id: \(id),
            name: \(name),
            type: \(type),
        )
        """
    }
} 


/// Criteria for filtering videos in smart folders.
@available(macOS 14, *)
public struct SmartFolderCriteria: Codable, Sendable {
    // MARK: - Properties
    
    /// Filter by video name.
    public var nameFilter: String?
    
    /// Filter by date range.
    public var dateRange: DateInterval?
    
    /// The minimum duration in seconds.
    public var minDuration: Double?
    
    /// The maximum duration in seconds.
    public var maxDuration: Double?
    
    /// Filter by minimum file size in bytes.
    public var minSize: Int64?
    
    /// Filter by maximum file size in bytes.
    public var maxSize: Int64?
    
    /// Filter by keywords in metadata.
    @Transient public var keywords: [String] {
        get { keywordsString.components(separatedBy: ",").filter { !$0.isEmpty } }
        set { keywordsString = newValue.joined(separator: ",") }
    }
    private var keywordsString: String = ""
    
    /// File path patterns to match.
    @Transient public var pathPatterns: [String] {
        get { pathPatternsString.components(separatedBy: ",").filter { !$0.isEmpty } }
        set { pathPatternsString = newValue.joined(separator: ",") }
    }
    private var pathPatternsString: String = ""
    
    // MARK: - Initialization
    
    public init(
        nameFilter: String? = nil,
        dateRange: DateInterval? = nil,
        minDuration: Double? = nil,
        maxDuration: Double? = nil,
        minSize: Int64? = nil,
        maxSize: Int64? = nil,
        keywords: [String] = [],
        pathPatterns: [String] = []
    ) {
        self.nameFilter = nameFilter
        self.dateRange = dateRange
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.minSize = minSize
        self.maxSize = maxSize
        self.keywords = keywords
        self.pathPatterns = pathPatterns
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case nameFilter, dateRange, minDuration, maxDuration
        case minSize, maxSize, keywordsString, pathPatternsString
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nameFilter = try container.decodeIfPresent(String.self, forKey: .nameFilter)
        dateRange = try container.decodeIfPresent(DateInterval.self, forKey: .dateRange)
        minDuration = try container.decodeIfPresent(Double.self, forKey: .minDuration)
        maxDuration = try container.decodeIfPresent(Double.self, forKey: .maxDuration)
        minSize = try container.decodeIfPresent(Int64.self, forKey: .minSize)
        maxSize = try container.decodeIfPresent(Int64.self, forKey: .maxSize)
        keywordsString = try container.decodeIfPresent(String.self, forKey: .keywordsString) ?? ""
        pathPatternsString = try container.decodeIfPresent(String.self, forKey: .pathPatternsString) ?? ""
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(nameFilter, forKey: .nameFilter)
        try container.encodeIfPresent(dateRange, forKey: .dateRange)
        try container.encodeIfPresent(minDuration, forKey: .minDuration)
        try container.encodeIfPresent(maxDuration, forKey: .maxDuration)
        try container.encodeIfPresent(minSize, forKey: .minSize)
        try container.encodeIfPresent(maxSize, forKey: .maxSize)
        try container.encode(keywordsString, forKey: .keywordsString)
        try container.encode(pathPatternsString, forKey: .pathPatternsString)
    }
    
    /// Creates a criteria for videos from today.
    public static var today: SmartFolderCriteria {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        return SmartFolderCriteria(dateRange: DateInterval(start: today, end: tomorrow))
    }
    
    /// Creates a criteria for videos from the last week.
    public static var lastWeek: SmartFolderCriteria {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!
        return SmartFolderCriteria(dateRange: DateInterval(start: lastWeek, end: today))
    }
    
    /// Creates a criteria for videos from the last month.
    public static var lastMonth: SmartFolderCriteria {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: today)!
        return SmartFolderCriteria(dateRange: DateInterval(start: lastMonth, end: today))
    }
    
    /// Creates a criteria for large videos (>1GB).
    public static var largeVideos: SmartFolderCriteria {
        SmartFolderCriteria(minSize: 1_000_000_000) // 1GB
    }
    
    // MARK: - Methods
    
    /// Evaluates whether a video matches the criteria.
    public func matches(_ video: Video) -> Bool {
        // Check name filter
        if let nameFilter = nameFilter,
           !video.title.localizedCaseInsensitiveContains(nameFilter) {
            return false
        }
        
        // Check date range
        if let dateRange = dateRange,
           !dateRange.contains(video.dateAdded) {
            return false
        }
        
        // Check duration
        if let minDuration = minDuration,
           video.duration < minDuration {
            return false
        }
        if let maxDuration = maxDuration,
           video.duration > maxDuration {
            return false
        }
        
        // Check file size
        if let minSize = minSize,
           let fileSize = video.fileSize,
           fileSize < minSize {
            return false
        }
        if let maxSize = maxSize,
           let fileSize = video.fileSize,
           fileSize > maxSize {
            return false
        }
        
        // Check keywords
        if !keywords.isEmpty {
            let title = video.title.lowercased()
            if !keywords.contains(where: { title.contains($0.lowercased()) }) {
                return false
            }
        }
        
        // Check path patterns
        if !pathPatterns.isEmpty {
            let path = video.url.path
            if !pathPatterns.contains(where: { path.contains($0) }) {
                return false
            }
        }
        
        return true
    }
}
