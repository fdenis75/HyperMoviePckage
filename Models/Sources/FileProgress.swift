import Foundation

public struct FileProgress: Identifiable, Hashable {
    public let id = UUID()
    public let filename: String
    public var progress: Double = 0.0
    public var stage: String = "Queued"
    public var isComplete: Bool = false
    public var isCancelled: Bool = false
    public var isSkipped: Bool = false
    public var isError: Bool = false
    public var errorMessage: String?
    public var outputURL: URL?
    
    public init(filename: String) {
        self.filename = filename
    }
} 