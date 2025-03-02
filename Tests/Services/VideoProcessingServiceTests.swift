import XCTest
import HyperMovieCore
import HyperMovieModels
import HyperMovieServices
import Logging

final class VideoProcessingServiceTests: XCTestCase {
    // Test paths
    let testFolder1 = "/Users/francois/Desktop/vids"
    let testFolder2 = "/Users/francois/Desktop/vids/2"
    let testVideo1 = "/Users/francois/Desktop/vids/IMG_4506 2.MOV"
    let testVideo2 = "/Users/francois/Desktop/vids/2/IMG_4506.MOV"
    
    var logger: Logger!
    var processingService: VideoProcessingService!
    var video1: Video!
    var video2: Video!
    
    override func setUp() async throws {
        super.setUp()
        logger = Logger(label: "com.hypermovie.tests.videoprocessing")
        processingService = VideoProcessingService(logger: logger)
        video1 = Video(url: URL(filePath: testVideo1))
        video2 = Video(url: URL(filePath: testVideo2))
    }
    
    override func tearDown() async throws {
        logger = nil
        processingService = nil
        video1 = nil
        video2 = nil
        super.tearDown()
    }
    
    func test_processVideo_shouldExtractMetadata() async throws {
        // When
        try await processingService.extractMetadata(for: video1)
        
        // Then
        XCTAssertNotNil(video1.metadata)
        XCTAssertGreaterThan(video1.metadata?.duration ?? 0, 0)
        XCTAssertGreaterThan(video1.metadata?.fileSize ?? 0, 0)
        XCTAssertNotNil(video1.metadata?.codec)
        XCTAssertNotEqual(video1.metadata?.resolution, .zero)
    }
    
    func test_generateThumbnails_shouldCreateImages() async throws {
        // Given
        let times: [TimeInterval] = [0.0, 1.0, 2.0]
        
        // When
        let thumbnails = try await withThrowingTaskGroup(of: NSImage.self) { group in
            for time in times {
                group.addTask {
                    try await self.processingService.generateThumbnail(for: self.video1, at: time)
                }
            }
            
            var results: [NSImage] = []
            for try await thumbnail in group {
                results.append(thumbnail)
            }
            return results
        }
        
        // Then
        XCTAssertEqual(thumbnails.count, times.count)
        for thumbnail in thumbnails {
            XCTAssertGreaterThan(thumbnail.size.width, 0)
            XCTAssertGreaterThan(thumbnail.size.height, 0)
        }
    }
    
    func test_generatePreview_shouldCreatePreviewFile() async throws {
        // When
        let previewURL = try await processingService.generatePreview(for: video1)
        
        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        
        // Cleanup
        try? FileManager.default.removeItem(at: previewURL)
    }
    
    func test_processInvalidVideo_shouldThrow() async {
        // Given
        let invalidVideo = Video(url: URL(filePath: "/invalid/path/video.mp4"))
        
        // Then
        await XCTAssertThrowsError(try await processingService.extractMetadata(for: invalidVideo))
        await XCTAssertThrowsError(try await processingService.generateThumbnail(for: invalidVideo, at: 0))
        await XCTAssertThrowsError(try await processingService.generatePreview(for: invalidVideo))
    }
    
    func test_processConcurrentVideos_shouldSucceed() async throws {
        // When
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.processingService.extractMetadata(for: self.video1)
            }
            group.addTask {
                try await self.processingService.extractMetadata(for: self.video2)
            }
            try await group.waitForAll()
        }
        
        // Then
        XCTAssertNotNil(video1.metadata)
        XCTAssertNotNil(video2.metadata)
    }
} 