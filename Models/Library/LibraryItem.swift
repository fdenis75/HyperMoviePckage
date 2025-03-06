import Foundation
import SwiftData

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
@available(macOS 15, *)
@Model
public final class LibraryItem {
    // MARK: - Properties
   // #Unique<LibraryItem>([\.id],[\.name, \.typeString, \.url])

    /// The unique identifier for the item.
    public var id: UUID
    
    /// The name of the item.
    public var name: String
    
    /// The type of the item (stored as string).
    public var typeString: String
    
    /// The URL of the folder (for folder type items).
    public var url: URL?
    
    // MARK: - SwiftData Configuration
   
  
    
    /// The date the item was created.
    public var dateCreated: Date
    
    /// The date the item was last modified.
    public var dateModified: Date
    
    /// Smart folder criteria for filtering videos (only for smart folder type).
    public var smartFolderCriteria: SmartFolderCriteria?
    
    /// Last update time for smart folder contents.
    public var lastUpdateTime: Date?
    
    /// Videos in the smart folder (only for smart folder type).
    public var videos: [Video]?
    
    // MARK: - Computed Properties
    
    /// The type of the item.
    public var type: LibraryItemType {
        get {
            LibraryItemType(rawValue: typeString) ?? .folder
        }
        set {
            typeString = newValue.rawValue
            // Clear videos array if type is changed from smart folder
            if newValue != .smartFolder {
                videos = nil
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(
        id: UUID = UUID(),
        name: String,
        type: LibraryItemType,
        url: URL? = nil,
        smartFolderCriteria: SmartFolderCriteria? = nil
    ) {
        self.id = id
        self.name = name
        self.typeString = type.rawValue
        self.url = url
        self.smartFolderCriteria = smartFolderCriteria
        self.dateCreated = Date()
        self.dateModified = Date()
        self.lastUpdateTime = type == .smartFolder ? Date() : nil
        self.videos = type == .smartFolder ? [] : nil
    }
    
    // MARK: - Smart Folder Methods
    
    /// Generate a name based on smart folder criteria
    public static func generateSmartFolderName(_ criteria: SmartFolderCriteria, existingNames: [String]) -> String {
        var baseName = ""
        
        if let start = criteria.startDate, let end = criteria.endDate {
            let calendar = Calendar.current
            if calendar.isDateInToday(start) {
                baseName = "Today's Videos"
            } else if calendar.isDate(start, equalTo: Date(), toGranularity: .month) {
                baseName = "This Month's Videos"
            } else if calendar.isDate(start, equalTo: Date(), toGranularity: .year) {
                baseName = "This Year's Videos"
            }
        } else if let minSize = criteria.minSize {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            baseName = "Large Videos (>\(formatter.string(fromByteCount: minSize)))"
        } else if let nameFilter = criteria.nameFilter {
            baseName = "Videos containing '\(nameFilter)'"
        } else if !criteria.keywords.isEmpty {
            baseName = "Videos with keywords: \(criteria.keywords.joined(separator: ", "))"
        } else {
            baseName = "Smart Folder"
        }
        
        // Ensure unique name
        var uniqueName = baseName
        var counter = 2
        while existingNames.contains(uniqueName) {
            uniqueName = "\(baseName) (\(counter))"
            counter += 1
        }
        
        return uniqueName
    }
    
    /// Update the smart folder's contents
    public func updateSmartFolder() {
        guard type == .smartFolder else { return }
        
        // Preserve the relative path structure for each video
        if let videos = videos {
            for video in videos {
                // Create relative path based on the video's location
                if video.relativePath.isEmpty {
                    let baseURL = url ?? URL(fileURLWithPath: "/")
                    if let relativePath = video.url.path.removingPrefix(baseURL.path) {
                        video.relativePath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    }
                }
            }
        }
        
        lastUpdateTime = Date()
        dateModified = Date()
    }
}

// Helper extension for path handling
private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard self.hasPrefix(prefix) else { return nil }
        return String(self.dropFirst(prefix.count))
    }
}

@available(macOS 15, *)
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
@available(macOS 15, *)
public struct SmartFolderCriteria: Codable, Sendable {
    // MARK: - Properties
    
    /// Filter by video name.
 public var nameFilter: [String]?    
    /// Filter by start date.
    public var startDate: Date?
    
    /// Filter by end date.
    public var endDate: Date?
    
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
         nameFilter: [String]? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        minDuration: Double? = nil,
        maxDuration: Double? = nil,
        minSize: Int64? = nil,
        maxSize: Int64? = nil,
        keywords: [String] = [],
        pathPatterns: [String] = []
    ) {
        self.nameFilter = nameFilter
        self.startDate = startDate
        self.endDate = endDate
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.minSize = minSize
        self.maxSize = maxSize
        self.keywords = keywords
        self.pathPatterns = pathPatterns
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case nameFilter, startDate, endDate, minDuration, maxDuration
        case minSize, maxSize, keywordsString, pathPatternsString
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nameFilter = try container.decodeIfPresent([String].self, forKey: .nameFilter)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
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
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
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
        return SmartFolderCriteria(startDate: today, endDate: tomorrow)
    }
    
    /// Creates a criteria for videos from the last week.
    public static var lastWeek: SmartFolderCriteria {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!
        return SmartFolderCriteria(startDate: lastWeek, endDate: today)
    }
    
    /// Creates a criteria for videos from the last month.
    public static var lastMonth: SmartFolderCriteria {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: today)!
        return SmartFolderCriteria(startDate: lastMonth, endDate: today)
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
           !nameFilter.contains(where: { video.title.localizedCaseInsensitiveContains($0) }) {
            return false
        }
        
        // Check date range
        if let start = startDate, video.dateAdded < start {
            return false
        }
        if let end = endDate, video.dateAdded >= end {
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
