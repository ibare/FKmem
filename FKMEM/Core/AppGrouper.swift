import AppKit
import Darwin
import Foundation

enum AppGrouper {
    nonisolated static func group(samples: [ProcessSample]) -> [AppMemoryEntry] {
        var totals: [pid_t: UInt64] = [:]
        totals.reserveCapacity(samples.count)
        for sample in samples {
            let owner = ResponsibilityResolver.responsiblePid(for: sample.pid)
            totals[owner, default: 0] &+= sample.physFootprint
        }

        var entries: [AppMemoryEntry] = []
        entries.reserveCapacity(totals.count)
        for (pid, bytes) in totals {
            let info = resolveAppInfo(for: pid)
            entries.append(
                AppMemoryEntry(
                    id: pid,
                    name: info.name,
                    bundlePath: info.bundlePath,
                    bytes: bytes
                )
            )
        }
        entries.sort { $0.bytes > $1.bytes }
        return entries
    }

    private struct AppInfo {
        let name: String
        let bundlePath: String?
    }

    nonisolated private static func resolveAppInfo(for pid: pid_t) -> AppInfo {
        guard let path = executablePath(for: pid) else {
            return AppInfo(name: "pid \(pid)", bundlePath: nil)
        }

        if let appPath = appBundlePath(in: path) {
            let bundle = Bundle(path: appPath)
            let dirName = (appPath as NSString)
                .lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
            let name = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle?.localizedInfoDictionary?["CFBundleName"] as? String)
                ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
                ?? dirName
            return AppInfo(name: name, bundlePath: appPath)
        }

        return AppInfo(
            name: (path as NSString).lastPathComponent,
            bundlePath: nil
        )
    }

    nonisolated private static let pidPathBufferSize = 4 * Int(MAXPATHLEN)

    nonisolated private static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: pidPathBufferSize)
        let written = proc_pidpath(pid, &buffer, UInt32(pidPathBufferSize))
        guard written > 0 else { return nil }
        return String(cString: buffer)
    }

    nonisolated private static func appBundlePath(in executablePath: String) -> String? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        let endIndex = executablePath.index(before: range.upperBound)
        return String(executablePath[..<endIndex])
    }
}
