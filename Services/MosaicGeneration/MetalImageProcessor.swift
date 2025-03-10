import Foundation
import Metal
import MetalKit
import CoreImage
import CoreVideo
import OSLog
import HyperMovieModels

/// A Metal-based image processor for high-performance mosaic generation
@available(macOS 15, *)
public final class MetalImageProcessor {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.hypermovie", category: "metal-processor")
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var textureCache: CVMetalTextureCache?
    
    // Compute pipelines for different operations
    private let scalePipeline: MTLComputePipelineState
    private let compositePipeline: MTLComputePipelineState
    private let fillPipeline: MTLComputePipelineState
    private let timestampPipeline: MTLComputePipelineState
    private let borderPipeline: MTLComputePipelineState
    private let shadowPipeline: MTLComputePipelineState
    
    // Performance metrics
    private var lastExecutionTime: CFAbsoluteTime = 0
    private var totalExecutionTime: CFAbsoluteTime = 0
    private var operationCount: Int = 0
    
    // MARK: - Initialization
    
    /// Initialize the Metal image processor
    public init() throws {
        logger.debug("🔧 Initializing Metal image processor")
        
        // Get default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("❌ No Metal device available")
            throw MetalProcessorError.deviceNotAvailable
        }
        self.device = device
        logger.debug("✅ Using Metal device: \(device.name)")
        
        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            logger.error("❌ Failed to create command queue")
            throw MetalProcessorError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue
        
        // Load Metal shader library
        do {
            self.library = try device.makeDefaultLibrary(bundle: Bundle.module)
        } catch {
            logger.error("❌ Failed to load default Metal library: \(error.localizedDescription)")
            throw MetalProcessorError.libraryCreationFailed
        }
        
        // Create texture cache for efficient conversion between CVPixelBuffer and MTLTexture
        var textureCache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        if status != kCVReturnSuccess {
            logger.error("❌ Failed to create texture cache: \(status)")
            throw MetalProcessorError.textureCacheCreationFailed
        }
        self.textureCache = textureCache
        
        // Create compute pipelines
        do {
            guard let scaleFunction = library.makeFunction(name: "scaleTexture"),
                  let compositeFunction = library.makeFunction(name: "compositeTextures"),
                  let fillFunction = library.makeFunction(name: "fillTexture"),
                  let timestampFunction = library.makeFunction(name: "addTimestamp"),
                  let borderFunction = library.makeFunction(name: "addBorder"),
                  let shadowFunction = library.makeFunction(name: "addShadow") else {
                logger.error("❌ Failed to create Metal functions")
                throw MetalProcessorError.functionNotFound
            }
            
            self.scalePipeline = try device.makeComputePipelineState(function: scaleFunction)
            self.compositePipeline = try device.makeComputePipelineState(function: compositeFunction)
            self.fillPipeline = try device.makeComputePipelineState(function: fillFunction)
            self.timestampPipeline = try device.makeComputePipelineState(function: timestampFunction)
            self.borderPipeline = try device.makeComputePipelineState(function: borderFunction)
            self.shadowPipeline = try device.makeComputePipelineState(function: shadowFunction)
            
            logger.debug("✅ Created all compute pipelines")
        } catch {
            logger.error("❌ Failed to create compute pipeline: \(error.localizedDescription)")
            throw MetalProcessorError.pipelineCreationFailed
        }
        
        logger.debug("✅ Metal image processor initialized successfully")
    }
    
    // MARK: - Public Methods
    
    /// Create a Metal texture from a CGImage
    /// - Parameter cgImage: The source CGImage
    /// - Returns: A Metal texture containing the image data
    public func createTexture(from cgImage: CGImage) throws -> MTLTexture {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer { trackPerformance(startTime: startTime) }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create a texture descriptor
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            logger.error("❌ Failed to create texture")
            throw MetalProcessorError.textureCreationFailed
        }
        
        // Create a bitmap context
        let bytesPerRow = 4 * width
        let region = MTLRegionMake2D(0, 0, width, height)
        
        // Create a Core Graphics context
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            logger.error("❌ Failed to create CGContext")
            throw MetalProcessorError.contextCreationFailed
        }
        
        // Draw the image to the context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Copy the data to the texture
        if let data = context.data {
            texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)
        }
        
        logger.debug("✅ Created Metal texture: \(width)x\(height)")
        return texture
    }
    
    /// Create a CGImage from a Metal texture
    /// - Parameter texture: The source Metal texture
    /// - Returns: A CGImage containing the texture data
    public func createCGImage(from texture: MTLTexture) throws -> CGImage {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer { trackPerformance(startTime: startTime) }
        
        let width = texture.width
        let height = texture.height
        let bytesPerRow = 4 * width
        let dataSize = bytesPerRow * height
        
        // Create a buffer to hold the pixel data
        var data = [UInt8](repeating: 0, count: dataSize)
        
        // Copy texture data to the buffer
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&data, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        // Create a data provider from the buffer
        guard let dataProvider = CGDataProvider(data: Data(bytes: &data, count: dataSize) as CFData) else {
            logger.error("❌ Failed to create data provider")
            throw MetalProcessorError.dataProviderCreationFailed
        }
        
        // Create a CGImage from the data provider
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            logger.error("❌ Failed to create CGImage")
            throw MetalProcessorError.cgImageCreationFailed
        }
        
        logger.debug("✅ Created CGImage from texture: \(width)x\(height)")
        return cgImage
    }
    
    /// Scale a texture to a new size
    /// - Parameters:
    ///   - texture: The source texture
    ///   - size: The target size
    /// - Returns: A new scaled texture
    public func scaleTexture(_ texture: MTLTexture, to size: CGSize) throws -> MTLTexture {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer { trackPerformance(startTime: startTime) }
        
        // Create output texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            logger.error("❌ Failed to create output texture")
            throw MetalProcessorError.textureCreationFailed
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("❌ Failed to create command buffer or encoder")
            throw MetalProcessorError.commandBufferCreationFailed
        }
        
        encoder.setComputePipelineState(scalePipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        
        // Calculate threadgroup size
        let threadgroupSize = calculateThreadgroupSize(pipeline: scalePipeline)
        let threadgroupCount = MTLSize(
            width: (outputTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (outputTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        logger.debug("✅ Scaled texture: \(texture.width)x\(texture.height) -> \(outputTexture.width)x\(outputTexture.height)")
        return outputTexture
    }
    
    /// Composite a texture onto another texture at a specific position
    /// - Parameters:
    ///   - sourceTexture: The source texture to composite
    ///   - destinationTexture: The destination texture
    ///   - position: The position to place the source texture
    public func compositeTexture(
        _ sourceTexture: MTLTexture,
        onto destinationTexture: MTLTexture,
        at position: CGPoint
    ) throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer { trackPerformance(startTime: startTime) }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("❌ Failed to create command buffer or encoder")
            throw MetalProcessorError.commandBufferCreationFailed
        }
        
        encoder.setComputePipelineState(compositePipeline)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(destinationTexture, index: 1)
        
        var positionValue = uint2(UInt32(position.x), UInt32(position.y))
        encoder.setBytes(&positionValue, length: MemoryLayout<uint2>.size, index: 0)
        
        // Calculate threadgroup size
        let threadgroupSize = calculateThreadgroupSize(pipeline: compositePipeline)
        let threadgroupCount = MTLSize(
            width: (sourceTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (sourceTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        logger.debug("✅ Composited texture at position: (\(position.x), \(position.y))")
    }
    
    /// Create a new texture filled with a solid color
    /// - Parameters:
    ///   - size: The size of the texture
    ///   - color: The color to fill with (RGBA, 0.0-1.0)
    /// - Returns: A new texture filled with the specified color
    public func createFilledTexture(size: CGSize, color: SIMD4<Float>) throws -> MTLTexture {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer { trackPerformance(startTime: startTime) }
        
        // Create output texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            logger.error("❌ Failed to create output texture")
            throw MetalProcessorError.textureCreationFailed
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("❌ Failed to create command buffer or encoder")
            throw MetalProcessorError.commandBufferCreationFailed
        }
        
        encoder.setComputePipelineState(fillPipeline)
        encoder.setTexture(outputTexture, index: 0)
        
        var colorValue = color
        encoder.setBytes(&colorValue, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        
        // Calculate threadgroup size
        let threadgroupSize = calculateThreadgroupSize(pipeline: fillPipeline)
        let threadgroupCount = MTLSize(
            width: (outputTexture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (outputTexture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        logger.debug("✅ Created filled texture: \(outputTexture.width)x\(outputTexture.height)")
        return outputTexture
    }
    
    /// Add a border to a region of a texture
    /// - Parameters:
    ///   - texture: The texture to modify
    ///   - position: The position of the region
    ///   - size: The size of the region
    ///   - color: The border color (RGBA, 0.0-1.0)
    ///   - width: The border width in pixels
    public func addBorder(
        to texture: MTLTexture,
        at position: CGPoint,
        size: CGSize,
        color: SIMD4<Float>,
        width: Float
    ) throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer { trackPerformance(startTime: startTime) }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            logger.error("❌ Failed to create command buffer or encoder")
            throw MetalProcessorError.commandBufferCreationFailed
        }
        
        encoder.setComputePipelineState(borderPipeline)
        encoder.setTexture(texture, index: 0)
        
        var positionValue = uint2(UInt32(position.x), UInt32(position.y))
        var sizeValue = uint2(UInt32(size.width), UInt32(size.height))
        var colorValue = color
        var widthValue = width
        
        encoder.setBytes(&positionValue, length: MemoryLayout<uint2>.size, index: 0)
        encoder.setBytes(&sizeValue, length: MemoryLayout<uint2>.size, index: 1)
        encoder.setBytes(&colorValue, length: MemoryLayout<SIMD4<Float>>.size, index: 2)
        encoder.setBytes(&widthValue, length: MemoryLayout<Float>.size, index: 3)
        
        // Calculate threadgroup size
        let threadgroupSize = calculateThreadgroupSize(pipeline: borderPipeline)
        let threadgroupCount = MTLSize(
            width: (texture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (texture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        logger.debug("✅ Added border at position: (\(position.x), \(position.y)), size: \(size.width)x\(size.height)")
    }
    
    /// Generate a mosaic image using Metal acceleration
    /// - Parameters:
    ///   - frames: Array of frames with timestamps
    ///   - layout: Layout information
    ///   - metadata: Video metadata
    ///   - config: Mosaic configuration
    /// - Returns: Generated mosaic image
    public func generateMosaic(
        from frames: [(image: CGImage, timestamp: String)],
        layout: HyperMovieModels.MosaicLayout,
        metadata: VideoMetadata,
        config: MosaicConfiguration
    ) async throws -> CGImage {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer { 
           
            trackPerformance(startTime: startTime) }
      
        logger.debug("🎨 Starting Metal-accelerated mosaic generation - Frames: \(frames.count)")
        logger.debug("📐 Layout size: \(layout.mosaicSize.width)x\(layout.mosaicSize.height)")
        
        // Create a texture for the mosaic
        let mosaicTexture = try createFilledTexture(
            size: layout.mosaicSize,
            color: SIMD4<Float>(0.1, 0.1, 0.1, 1.0) // Dark gray background
        )
        
        // Process frames in batches to avoid GPU timeout
        let batchSize = 16
        for batchStart in stride(from: 0, to: frames.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, frames.count)
            let batchFrames = frames[batchStart..<batchEnd]
            
            logger.debug("🔄 Processing batch \(batchStart/batchSize + 1): frames \(batchStart+1)-\(batchEnd)")
            
            for (index, frame) in batchFrames.enumerated() {
                let actualIndex = batchStart + index
                guard actualIndex < layout.positions.count else { break }
                
                let position = layout.positions[actualIndex]
                let size = layout.thumbnailSizes[actualIndex]
                
                // Convert CGImage to Metal texture
                let frameTexture = try createTexture(from: frame.image)
                
                // Scale the frame if needed
                let scaledTexture: MTLTexture
                if frameTexture.width != Int(size.width) || frameTexture.height != Int(size.height) {
                    scaledTexture = try scaleTexture(
                        frameTexture,
                        to: CGSize(width: size.width, height: size.height)
                    )
                } else {
                    scaledTexture = frameTexture
                }
                
                // Add border if enabled
                if config.layout.visual.addBorder {
                    try addBorder(
                        to: scaledTexture,
                        at: CGPoint(x: 0, y: 0),
                        size: CGSize(width: scaledTexture.width, height: scaledTexture.height),
                        color: SIMD4<Float>(1.0, 1.0, 1.0, 1.0), // White border
                        width: Float(config.layout.visual.borderWidth)
                    )
                }
                
                // Composite the frame onto the mosaic
                try compositeTexture(
                    scaledTexture,
                    onto: mosaicTexture,
                    at: CGPoint(x: position.x, y: position.y)
                )
                
                // Add timestamp (simplified for now)
                // In a full implementation, we would render text using a texture atlas
                
                if Task.isCancelled {
                    logger.warning("❌ Mosaic creation cancelled")
                    throw MetalProcessorError.cancelled
                }
            }
        }
        
        // Convert the Metal texture back to a CGImage
        let cgImage = try createCGImage(from: mosaicTexture)
        
        logger.debug("✅ Metal mosaic generation complete - Size: \(cgImage.width)x\(cgImage.height)")
         let generationTime = CFAbsoluteTimeGetCurrent() - startTime
            logger.debug("🎨 Metal-accelerated mosaic generation complete - Size: \(cgImage.width)x\(cgImage.height) in \(generationTime) seconds")
        return cgImage
    }
    
    /// Get performance metrics for the Metal processor
    /// - Returns: A dictionary of performance metrics
    public func getPerformanceMetrics() -> [String: Any] {
        return [
            "averageExecutionTime": operationCount > 0 ? totalExecutionTime / Double(operationCount) : 0,
            "totalExecutionTime": totalExecutionTime,
            "operationCount": operationCount,
            "lastExecutionTime": lastExecutionTime
        ]
    }
    
    // MARK: - Private Methods
    
    private func calculateThreadgroupSize(pipeline: MTLComputePipelineState) -> MTLSize {
        let maxThreadsPerThreadgroup = pipeline.maxTotalThreadsPerThreadgroup
        let threadExecutionWidth = pipeline.threadExecutionWidth
        
        let threadsPerThreadgroup = min(maxThreadsPerThreadgroup, threadExecutionWidth * threadExecutionWidth)
        let width = min(threadExecutionWidth, threadsPerThreadgroup)
        let height = threadsPerThreadgroup / width
        
        return MTLSize(width: width, height: height, depth: 1)
    }
    
    private func trackPerformance(startTime: CFAbsoluteTime) {
        let executionTime = CFAbsoluteTimeGetCurrent() - startTime
        lastExecutionTime = executionTime
        totalExecutionTime += executionTime
        operationCount += 1
    }
}

// MARK: - Errors

/// Errors that can occur during Metal processing
public enum MetalProcessorError: Error {
    case deviceNotAvailable
    case commandQueueCreationFailed
    case libraryCreationFailed
    case textureCacheCreationFailed
    case functionNotFound
    case pipelineCreationFailed
    case textureCreationFailed
    case contextCreationFailed
    case commandBufferCreationFailed
    case dataProviderCreationFailed
    case cgImageCreationFailed
    case cancelled
} 