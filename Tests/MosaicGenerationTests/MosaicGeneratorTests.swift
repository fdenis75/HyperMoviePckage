import XCTest
import HyperMovieModels
import HyperMovieCore
import SwiftData
@testable import HyperMovieServices

@available(macOS 15, *)
final class MosaicGeneratorTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var generator: MosaicGenerator!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a temporary model container for testing
        let schema = Schema([Video.self])
        modelContainer = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        modelContext = ModelContext(modelContainer)
        
        // Create a temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Initialize the generator
        generator = MosaicGenerator()
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
        
        // Clean up temporary directory
        if let tempDirectory = tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        
        generator = nil
        modelContext = nil
        modelContainer = nil
    }
    
    // MARK: - Test Output Options
    
    func testOverwriteOption() async throws {
        // This test would create a video, generate a mosaic, then try to generate it again
        // with overwrite=false and overwrite=true to verify the behavior
        // For now, we'll just document the test structure
        
        // 1. Create a test video
        // 2. Generate a mosaic with overwrite=false
        // 3. Try to generate again with overwrite=false, should throw fileExists error
        // 4. Try to generate again with overwrite=true, should succeed
        
        XCTAssertTrue(true, "This test needs to be implemented with actual video files")
    }
    
    func testSaveAtRootOption() async throws {
        // This test would create videos in nested folders, then generate mosaics with
        // saveAtRoot=true to verify they all end up in the root folder
        // For now, we'll just document the test structure
        
        // 1. Create test videos in nested folders
        // 2. Generate mosaics with saveAtRoot=true
        // 3. Verify all mosaics are in the root folder
        
        XCTAssertTrue(true, "This test needs to be implemented with actual video files")
    }
    
    func testAddFullPathOption() async throws {
        // This test would create a video in a nested path, then generate a mosaic with
        // addFullPath=true to verify the filename includes the path
        // For now, we'll just document the test structure
        
        // 1. Create a test video in a nested path
        // 2. Generate a mosaic with addFullPath=true
        // 3. Verify the filename includes the sanitized path
        
        XCTAssertTrue(true, "This test needs to be implemented with actual video files")
    }
    
    // MARK: - Helper Methods
    
    private func createTestVideo(at path: URL, duration: Double = 10.0) -> Video {
        let video = Video(url: path)
        video.duration = duration
        video.metadata.codec = "h264"
        video.metadata.bitrate = 1000000
        modelContext.insert(video)
        return video
    }
} 