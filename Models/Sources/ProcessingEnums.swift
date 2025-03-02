import Foundation

public enum ProcessingStage: String {
    case discovering = "Discovering Files"
    case thumbnails = "Generating Thumbnails" 
    case mosaic = "Generating Mosaic"
    case preview = "Generating Preview"
    case saving = "Saving Output"
}

public enum ProcessingMode: String, CaseIterable, Identifiable {
    case mosaic = "Mosaic"
    case preview = "Preview"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .mosaic: "photo.on.rectangle"
        case .preview: "eye"
        case .settings: "gear"
        }
    }
} 