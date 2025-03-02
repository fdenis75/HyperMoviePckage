import XCTest
import HyperMovieModels

@available(macOS 14, *)
final class VideoTests: XCTestCase {
    let testVideo1 = "/Users/francois/Desktop/vids/IMG_4506 2.MOV"
    
    var video: Video!
    
    override func setUp() async throws {
        try await super.setUp()
        // Create test video
        video = try await Video(url: URL(filePath: testVideo1))
    }
    
    override func tearDown() async throws {
        video = nil
        try await super.tearDown()
    }
    
    func test_videoInitialization_withValidURL_shouldSucceed() {
        XCTAssertNotNil(video)
        XCTAssertEqual(video.url.path, testVideo1)
        XCTAssertEqual(video.title, URL(filePath: testVideo1).deletingPathExtension().lastPathComponent)
    }
    
    func test_videoMetadata_shouldHaveDefaultValues() {
        XCTAssertNotNil(video.metadata)
        XCTAssertNil(video.metadata.codec)
        XCTAssertNil(video.metadata.bitrate)
        XCTAssertTrue(video.metadata.custom.isEmpty)
    }
    
    func test_videoMetadataUpdate_shouldPersist() {
        // Given
        let newMetadata = VideoMetadata(
            codec: "H.264",
            bitrate: 10_000_000,
            custom: ["resolution": "1920x1080"]
        )
        
        // When
        video.metadata = newMetadata
        
        // Then
        XCTAssertEqual(video.metadata.codec, "H.264")
        XCTAssertEqual(video.metadata.bitrate, 10_000_000)
        XCTAssertEqual(video.metadata.custom["resolution"], "1920x1080")
    }
} 