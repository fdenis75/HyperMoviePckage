import XCTest
import HyperMovieCore
import HyperMovieModels
import HyperMovieServices
import Logging

final class VideoFinderServiceTests: XCTestCase {
    // Test paths
    let testFolder1 = "/Users/francois/Desktop/vids"
    let testFolder2 = "/Users/francois/Desktop/vids/2"
    let testVideo1 = "/Users/francois/Desktop/vids/IMG_4506 2.MOV"
    let testVideo2 = "/Users/francois/Desktop/vids/2/IMG_4506.MOV"
    
    var logger: Logger!
    var finderService: VideoFinderService!
    
    override func setUp() async throws {
        super.setUp()
        logger = Logger(label: "com.hypermovie.tests.videofinder")
        finderService = VideoFinderService(logger: logger)
    }
    
    override func tearDown() async throws {
        logger = nil
        finderService = nil
        super.tearDown()
    }
    
    func test_findVideos_inFolder_shouldReturnVideos() async throws {
        // When
        let videos = try await finderService.findVideos(in: URL(filePath: testFolder1))
        
        // Then
        XCTAssertFalse(videos.isEmpty)
        XCTAssertTrue(videos.contains { $0.url.path == testVideo1 })
    }
    
    func test_findVideos_inNestedFolders_shouldReturnAllVideos() async throws {
        // When
        let videos = try await finderService.findVideos(in: URL(filePath: testFolder1), recursive: true)
        
        // Then
        XCTAssertFalse(videos.isEmpty)
        XCTAssertTrue(videos.contains { $0.url.path == testVideo1 })
        XCTAssertTrue(videos.contains { $0.url.path == testVideo2 })
    }
    
    func test_findVideos_withFilter_shouldReturnFilteredVideos() async throws {
        // Given
        let criteria = SmartFolderCriteria(
            name: "Large Videos",
            minSize: 1024 * 1024 * 100 // 100MB
        )
        
        // When
        let videos = try await finderService.findVideos(
            in: URL(filePath: testFolder1),
            recursive: true,
            matching: criteria
        )
        
        // Then
        XCTAssertFalse(videos.isEmpty)
        for video in videos {
            XCTAssertNotNil(video.metadata)
            XCTAssertGreaterThanOrEqual(video.metadata?.fileSize ?? 0, criteria.minSize ?? 0)
        }
    }
    
    func test_findVideos_withInvalidPath_shouldThrow() async {
        // Given
        let invalidPath = "/invalid/path"
        
        // Then
        await XCTAssertThrowsError(
            try await finderService.findVideos(in: URL(filePath: invalidPath))
        )
    }
} 