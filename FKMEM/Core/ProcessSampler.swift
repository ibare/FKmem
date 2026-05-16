import Darwin
import Foundation

struct ProcessSample: Sendable {
    let pid: pid_t
    let physFootprint: UInt64
}

enum ProcessSampler {
    nonisolated static func sampleAll() -> [ProcessSample] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }

        let capacity = Int(needed) / MemoryLayout<pid_t>.size + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = pids.withUnsafeMutableBufferPointer { buffer -> Int32 in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.size)
            )
        }
        guard written > 0 else { return [] }
        let realCount = Int(written) / MemoryLayout<pid_t>.size

        var samples: [ProcessSample] = []
        samples.reserveCapacity(realCount)
        for pid in pids.prefix(realCount) where pid > 0 {
            if let footprint = physFootprint(pid: pid) {
                samples.append(ProcessSample(pid: pid, physFootprint: footprint))
            }
        }
        return samples
    }

    nonisolated private static let rusageBufferSize = max(MemoryLayout<rusage_info_v4>.size, 2048)

    nonisolated private static func physFootprint(pid: pid_t) -> UInt64? {
        let raw = UnsafeMutableRawPointer.allocate(byteCount: rusageBufferSize, alignment: 16)
        defer { raw.deallocate() }
        memset(raw, 0, rusageBufferSize)

        let typed = raw.assumingMemoryBound(to: rusage_info_t?.self)
        let status = proc_pid_rusage(pid, RUSAGE_INFO_V4, typed)
        guard status == 0 else { return nil }

        return raw.assumingMemoryBound(to: rusage_info_v4.self).pointee.ri_phys_footprint
    }
}
