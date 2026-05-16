import Darwin
import Foundation

enum ResponsibilityResolver {
    private typealias Fn = @convention(c) (pid_t) -> pid_t

    nonisolated private static let fn: Fn? = {
        let symbol = "responsibility_get_pid_responsible_for_pid"
        let candidates: [UnsafeMutableRawPointer?] = [
            dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol), // RTLD_DEFAULT
            dlopen("libquarantine.dylib", RTLD_NOW).flatMap { dlsym($0, symbol) },
            dlopen("/usr/lib/libquarantine.dylib", RTLD_NOW).flatMap { dlsym($0, symbol) },
            dlopen(nil, RTLD_NOW).flatMap { dlsym($0, symbol) }
        ]
        for sym in candidates {
            if let sym {
                return unsafeBitCast(sym, to: Fn.self)
            }
        }
        return nil
    }()

    nonisolated static var isAvailable: Bool { fn != nil }

    nonisolated static func responsiblePid(for pid: pid_t) -> pid_t {
        guard let fn else { return pid }
        let result = fn(pid)
        return result > 0 ? result : pid
    }
}
