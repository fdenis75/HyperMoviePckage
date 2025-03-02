import XCTest
import SwiftData
import HyperMovieModels

@available(macOS 14, *)
@MainActor
final class PersistenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([
            Video.self,
            LibraryItem.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        context = ModelContext(container)
    }
    
    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }
    
    func test_saveAndFetchVideo_shouldPersistData() async throws {
        // Given
        let url = URL(filePath: "/test/video.mp4")
        let video = try await Video(url: url)
        await video.metadata = VideoMetadata(
            codec: "H.264",
            bitrate: 10_000_000,
            custom: ["resolution": "1920x1080"]
        )
        
        // When
        context.insert(video)
        try await context.save()
        
        // Then
        let descriptor = FetchDescriptor<Video>(
            predicate: #Predicate<Video> { video in
                video.url.path == "/test/video.mp4"
            }
        )
        let fetchedVideos = try context.fetch(descriptor)
        XCTAssertEqual(fetchedVideos.count, 1)
        
        let fetchedVideo = fetchedVideos[0]
        XCTAssertEqual(fetchedVideo.url.path, url.path)
        XCTAssertEqual(fetchedVideo.metadata.codec, "H.264")
        XCTAssertEqual(fetchedVideo.metadata.bitrate, 10_000_000)
        XCTAssertEqual(fetchedVideo.metadata.custom["resolution"], "1920x1080")
    }
    
    func test_saveAndFetchLibraryItem_shouldPersistHierarchy() async throws {
        // Given
        let folder1 = LibraryItem(name: "Test Folder 1", type: .folder)
        let folder2 = LibraryItem(name: "Test Folder 2", type: .folder)
        folder1.addChild(folder2)
        
        // When
        context.insert(folder1)
        try context.save()
        
        // Then
        let descriptor = FetchDescriptor<HyperMovieModels.LibraryItem>(
            predicate: #Predicate<HyperMovieModels.LibraryItem> { item in
                item.name == "Test Folder 1"
            }
        )
        let fetchedItems = try context.fetch(descriptor)
        XCTAssertEqual(fetchedItems.count, 1)
        
        let fetchedFolder1 = fetchedItems[0]
        XCTAssertEqual(fetchedFolder1.name, "Test Folder 1")
        XCTAssertEqual(fetchedFolder1.children?.count, 1)
        
        let fetchedFolder2 = fetchedFolder1.children?.first
        XCTAssertEqual(fetchedFolder2?.name, "Test Folder 2")
        XCTAssertEqual(fetchedFolder2?.parent, fetchedFolder1)
    }
    
    func test_saveAndFetchSmartFolder_shouldPersistCriteria() async throws {
        // Given
        let criteria = SmartFolderCriteria(
            nameFilter: "Last Week's Videos",
            dateRange: DateInterval(start: Date().addingTimeInterval(-7*24*60*60), duration: 7*24*60*60),
            minSize: 1024 * 1024,
            maxSize: 1024 * 1024 * 1024
        )
        let smartFolder = HyperMovieModels.LibraryItem(name: "Smart Folder", type: .smartFolder, criteria: criteria)
        
        // When
        context.insert(smartFolder)
        try context.save()
        
        // Then
        let descriptor = FetchDescriptor<HyperMovieModels.LibraryItem>(
            predicate: #Predicate<HyperMovieModels.LibraryItem> { item in
                item.name == "Smart Folder"
            }
        )
        let fetchedItems = try context.fetch(descriptor)
        XCTAssertEqual(fetchedItems.count, 1)
        
        let fetchedSmartFolder = fetchedItems[0]
        XCTAssertEqual(fetchedSmartFolder.name, "Smart Folder")
        XCTAssertNotNil(fetchedSmartFolder.criteria)
        XCTAssertEqual(fetchedSmartFolder.criteria?.nameFilter, "Last Week's Videos")
        XCTAssertNotNil(fetchedSmartFolder.criteria?.dateRange)
        XCTAssertEqual(fetchedSmartFolder.criteria?.minSize, 1024 * 1024)
        XCTAssertEqual(fetchedSmartFolder.criteria?.maxSize, 1024 * 1024 * 1024)
    }
    
    func test_deleteVideo_shouldRemoveFromPersistence() async throws {
        // Given
        let video = try await Video(url: URL(filePath: "/test/video.mp4"))
        context.insert(video)
        try await context.save()
        
        // When
        context.delete(video)
        try await context.save()
        
        // Then
        let descriptor = FetchDescriptor<Video>()
        let remainingVideos = try context.fetch(descriptor)
        XCTAssertTrue(remainingVideos.isEmpty)
    }
    
    func test_updateVideoMetadata_shouldPersistChanges() async throws {
        // Given
        let video = try await Video(url: URL(filePath: "/test/video.mp4"))
        video.metadata = VideoMetadata(
            codec: "H.264",
            bitrate: 10_000_000,
            custom: ["resolution": "1920x1080"]
        )
        context.insert(video)
        try await context.save()
        
        // When
        video.metadata?.codec = "H.264"
        video.metadata?.bitrate = 10_000_000
        video.metadata?.custom["resolution"] = "1920x1080"
        try await context.save()
        
        // Then
        let descriptor = FetchDescriptor<Video>(
            predicate: #Predicate<Video> { video in
                video.url.path == "/test/video.mp4"
            }
        )
        let fetchedVideos = try context.fetch(descriptor)
        XCTAssertEqual(fetchedVideos.count, 1)
        
        let fetchedVideo = fetchedVideos[0]
        XCTAssertEqual(fetchedVideo.metadata.codec, "H.264")
        XCTAssertEqual(fetchedVideo.metadata.bitrate, 10_000_000)
        XCTAssertEqual(fetchedVideo.metadata.custom["resolution"], "1920x1080")
    }
    
    func test_cascadingDelete_shouldRemoveRelatedObjects() async throws {
        // Given
        let folder = HyperMovieModels.LibraryItem(name: "Test Folder", type: .folder)
        let video = try await Video(url: URL(filePath: "/test/video.mp4"))
        video.metadata = VideoMetadata(duration: 10.0, resolution: CGSize.zero, codec: "H.264")
        context.insert(folder)
        context.insert(video)
        try await context.save()
        
        // When
        context.delete(folder)
        try context.save()
        
        // Then
        let folderDescriptor = FetchDescriptor<HyperMovieModels.LibraryItem>()
        let videoDescriptor = FetchDescriptor<Video>()
        let remainingFolders = try context.fetch(folderDescriptor)
        let remainingVideos = try context.fetch(videoDescriptor)
        
        XCTAssertTrue(remainingFolders.isEmpty)
        XCTAssertEqual(remainingVideos.count, 1) // Video should remain as it's not directly owned
    }
} 