import Darwin
import Foundation

enum MemoryPressure {
    nonisolated static func sample(appBytes: UInt64) -> SystemMemorySnapshot {
        let total = totalPhysicalMemory()
        let stats = vmStats()
        let pageSize = UInt64(vm_kernel_page_size)

        let free = UInt64(stats.free_count) &* pageSize
        let compressed = UInt64(stats.compressor_page_count) &* pageSize
        let speculative = UInt64(stats.speculative_count) &* pageSize
        let external = UInt64(stats.external_page_count) &* pageSize
        let purgeable = UInt64(stats.purgeable_count) &* pageSize
        let used = total > free ? total &- free : 0
        let available = min(total, free &+ speculative &+ external &+ purgeable)
        let compressorRatio = total > 0 ? Double(compressed) / Double(total) : 0

        let level: PressureLevel
        switch readKernelPressureLevel() {
        case 4: level = .critical
        case 2: level = .warn
        default: level = .normal
        }

        let base: Double
        switch level {
        case .normal: base = 0.40
        case .warn: base = 0.72
        case .critical: base = 0.95
        }
        let jitter = max(0, compressorRatio - 0.20) * 0.25
        let pressureValue = min(1.0, base + jitter)

        return SystemMemorySnapshot(
            totalBytes: total,
            usedBytes: used,
            availableBytes: available,
            appBytes: appBytes,
            pressure: level,
            pressureValue: pressureValue
        )
    }

    nonisolated private static func readKernelPressureLevel() -> Int32 {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return level
    }

    nonisolated private static func vmStats() -> vm_statistics64_data_t {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let host = mach_host_self()
        _ = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(host, HOST_VM_INFO64, rebound, &count)
            }
        }
        return stats
    }

    nonisolated private static func totalPhysicalMemory() -> UInt64 {
        var size: UInt64 = 0
        var length = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &length, nil, 0)
        return size
    }
}
