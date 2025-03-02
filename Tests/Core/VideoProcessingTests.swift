import XCTest
import HyperMovieCore
import HyperMovieModels
import Logging

@available(macOS 15, *)
final class VideoProcessingTests: XCTestCase {
    // Test paths
    let testFolder1 = "/Users/francois/Desktop/vids"
    let testVideo1 = "/Users/francois/Desktop/vids/IMG_4506 2.MOV"
    
    fileprivate var logger: Logger!
    fileprivate var mockProcessor: MockVideoProcessor!
    fileprivate var video1: Video!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = Logger(label: "com.hypermovie.tests.videoprocessing")
        mockProcessor = MockVideoProcessor()
        video1 = try await Video(url: URL(filePath: testVideo1))
    }
    
    override func tearDown() async throws {
        logger = nil
        mockProcessor = nil
        video1 = nil
        try await super.tearDown()
    }
    
    func test_process_shouldReturnProcessedVideo() async throws {
        // Given
        let url = URL(filePath: testVideo1)
        
        // When
        let processedVideo = try await mockProcessor.process(url: url)
        
        // Then
        XCTAssertEqual(processedVideo.url, url)
    }
    
    func test_generateThumbnail_shouldReturnURL() async throws {
        // Given
        let size = CGSize(width: 320, height: 240)
        let mockURL = URL(filePath: "\(testFolder1)/thumb.jpg")
        await mockProcessor.setMockThumbnailURL(mockURL)
        
        // When
        let thumbnailURL = try await mockProcessor.generateThumbnail(for: video1, size: size)
        
        // Then
        XCTAssertEqual(thumbnailURL, mockURL)
    }
}

// MARK: - Mock Implementation
@available(macOS 15, *)
private actor MockVideoProcessor: VideoProcessing {
    private var mockThumbnailURL: URL?
    
    func setMockThumbnailURL(_ url: URL) {
        mockThumbnailURL = url
    }
    
    func process(url: URL) async throws -> Video {
        return try await Video(url: url)
    }
    
    func extractMetadata(for video: Video) async throws {
        // Mock implementation
    }
    
    func generateThumbnail(for video: Video, size: CGSize) async throws -> URL {
        guard let url = mockThumbnailURL else {
            throw VideoError.thumbnailGenerationFailed(video.url, NSError(domain: "MockError", code: -1))
        }
        return url
    }
    
    func cancelAllOperations() {
        // Mock implementation
    }
} 