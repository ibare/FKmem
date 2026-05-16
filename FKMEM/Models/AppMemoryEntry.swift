import Foundation

struct AppMemoryEntry: Identifiable, Sendable, Hashable {
    let id: pid_t
    let name: String
    let bundlePath: String?
    let bytes: UInt64
}
