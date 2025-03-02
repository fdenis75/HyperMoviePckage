import Foundation

/// Metrics for monitoring system resources during video processing
public struct ProcessingMetrics {
    /// Current CPU usage (0.0 to 1.0)
    public let cpuUsage: Double
    
    /// Available memory in bytes
    public let memoryAvailable: UInt64
    
    /// Disk I/O pressure (0.0 to 1.0)
    public let diskIOPressure: Double
    
    /// Initialize processing metrics
    /// - Parameters:
    ///   - cpuUsage: Current CPU usage (0.0 to 1.0)
    ///   - memoryAvailable: Available memory in bytes
    ///   - diskIOPressure: Disk I/O pressure (0.0 to 1.0)
    public init(cpuUsage: Double, memoryAvailable: UInt64, diskIOPressure: Double) {
        self.cpuUsage = cpuUsage
        self.memoryAvailable = memoryAvailable
        self.diskIOPressure = diskIOPressure
    }
    
    /// Recommended number of concurrent operations based on system metrics
    public var recommendedConcurrency: Int {
        // Start with base concurrency of 4
        var concurrent = 4
        
        // Adjust based on CPU usage (reduce if high)
        if cpuUsage > 0.7 { concurrent -= 2 }
        else if cpuUsage < 0.3 { concurrent += 2 }
        
        // Adjust based on memory (reduce if low)
        if memoryAvailable < 1_000_000_000 { concurrent -= 1 } // < 1GB
        else if memoryAvailable > 4_000_000_000 { concurrent += 1 } // > 4GB
        
        // Adjust based on disk I/O (reduce if high)
        if diskIOPressure > 0.7 { concurrent -= 1 }
        
        return concurrent
    }
    
    /// String representation of memory available
    public var formattedMemoryAvailable: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(memoryAvailable))
    }
    
    /// String representation of CPU usage
    public var formattedCPUUsage: String {
        String(format: "%.1f%%", cpuUsage * 100)
    }
    
    /// String representation of disk I/O pressure
    public var formattedDiskPressure: String {
        String(format: "%.1f%%", diskIOPressure * 100)
    }
} 