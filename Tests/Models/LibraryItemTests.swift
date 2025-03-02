import XCTest
import HyperMovieModels

@available(macOS 14, *)
final class LibraryItemTests: XCTestCase {
    // Test paths
    let testFolder1 = "/Users/francois/Desktop/vids"
    let testFolder2 = "/Users/francois/Desktop/vids/2"
    let testVideo1 = "/Users/francois/Desktop/vids/IMG_4506 2.MOV"
    let testVideo2 = "/Users/francois/Desktop/vids/2/IMG_4506.MOV"
    
    var folder1: HyperMovieModels.LibraryItem!
    var folder2: HyperMovieModels.LibraryItem!
    var smartFolder: HyperMovieModels.LibraryItem!
    
    override func setUp() {
        super.setUp()
        // Create test folders
        folder1 = HyperMovieModels.LibraryItem(name: "Test Folder 1", type: .folder, url: URL(filePath: testFolder1))
        folder2 = HyperMovieModels.LibraryItem(name: "Test Folder 2", type: .folder, url: URL(filePath: testFolder2))
        
        // Create smart folder
        let criteria = SmartFolderCriteria(
            nameFilter: "Test",
            dateRange: DateInterval(start: Date(), duration: -7*24*60*60),
            minSize: 1024 * 1024,
            maxSize: 1024 * 1024 * 1024
        )
        smartFolder = HyperMovieModels.LibraryItem(name: "Smart Folder", type: .smartFolder, criteria: criteria)
    }
    
    override func tearDown() {
        folder1 = nil
        folder2 = nil
        smartFolder = nil
        super.tearDown()
    }
    
    func test_libraryItemInitialization_shouldSucceed() {
        XCTAssertEqual(folder1.name, "Test Folder 1")
        XCTAssertEqual(folder1.type, .folder)
        XCTAssertEqual(folder1.url?.path, testFolder1)
        XCTAssertTrue(folder1.children?.isEmpty ?? true)
    }
    
    func test_smartFolderInitialization_shouldSucceed() {
        XCTAssertEqual(smartFolder.name, "Smart Folder")
        XCTAssertEqual(smartFolder.type, .smartFolder)
        XCTAssertNotNil(smartFolder.criteria)
        XCTAssertEqual(smartFolder.criteria?.nameFilter, "Test")
    }
    
    func test_libraryItemHierarchy_shouldManageParentChildRelationship() {
        // When
        folder1.addChild(folder2)
        
        // Then
        XCTAssertEqual(folder1.children?.count, 1)
        XCTAssertEqual(folder2.parent, folder1)
        XCTAssertTrue(folder1.children?.contains(folder2) ?? false)
        
        // When
        folder1.removeChild(folder2)
        
        // Then
        XCTAssertTrue(folder1.children?.isEmpty ?? true)
        XCTAssertNil(folder2.parent)
    }
    
    func test_folderPath_shouldReturnFullPath() {
        // Given
        folder1.addChild(folder2)
        
        // Then
        XCTAssertEqual(folder2.folderPath, "Test Folder 1 / Test Folder 2")
    }
    
    func test_isDescendant_shouldReturnCorrectResult() {
        // Given
        folder1.addChild(folder2)
        
        // Then
        XCTAssertTrue(folder2.isDescendant(of: folder1))
        XCTAssertFalse(folder1.isDescendant(of: folder2))
    }
    
    func test_smartFolderCriteria_shouldMatchAppropriateVideos() async throws {
        // Given
        let video1 = try await Video(url: URL(filePath: testVideo1))
        let video2 = try await Video(url: URL(filePath: testVideo2))
        
        // Set metadata for testing
        video1.metadata = VideoMetadata(
            codec: "H.264",
            bitrate: 10_000_000,
            custom: [
                "fileSize": String(1024 * 1024 * 100),
                "duration": "10.0",
                "resolution": "1920x1080"
            ]
        )
        
        video2.metadata = VideoMetadata(
            codec: "H.264",
            bitrate: 5_000_000,
            custom: [
                "fileSize": String(1024 * 1024 * 50),
                "duration": "5.0",
                "resolution": "1280x720"
            ]
        )
        
        // Test criteria matching
        XCTAssertTrue(smartFolder.criteria?.matches(video1) ?? false)
        XCTAssertTrue(smartFolder.criteria?.matches(video2) ?? false)
    }
} 
