import Foundation

enum PressureLevel: Sendable {
    case normal
    case warn
    case critical
}

struct SystemMemorySnapshot: Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let appBytes: UInt64
    let pressure: PressureLevel
    let pressureValue: Double
}
