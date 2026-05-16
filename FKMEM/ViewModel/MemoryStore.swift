import Foundation
import Observation

struct PressurePoint: Identifiable, Sendable {
    let time: Date
    let value: Double
    let level: PressureLevel
    var id: Date { time }
}

@Observable
@MainActor
final class MemoryStore {
    private(set) var entries: [AppMemoryEntry] = []
    private(set) var snapshot = SystemMemorySnapshot(
        totalBytes: 0,
        usedBytes: 0,
        availableBytes: 0,
        appBytes: 0,
        pressure: .normal,
        pressureValue: 0
    )
    private(set) var lastUpdate: Date = .distantPast
    private(set) var isRefreshing = false
    private(set) var pressureHistory: [PressurePoint] = []

    private let historyCapacity = 60

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var currentInterval: TimeInterval = 0

    func startAutoRefresh(interval: TimeInterval) {
        guard currentInterval != interval || timer == nil else { return }
        currentInterval = interval
        timer?.invalidate()
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.refreshNow()
            }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
        currentInterval = 0
    }

    func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task.detached(priority: .utility) {
            let samples = ProcessSampler.sampleAll()
            let entries = AppGrouper.group(samples: samples)
            let appBytes = entries.reduce(UInt64(0)) { $0 &+ $1.bytes }
            let snapshot = MemoryPressure.sample(appBytes: appBytes)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries = entries
                self.snapshot = snapshot
                let now = Date()
                self.lastUpdate = now
                var history = self.pressureHistory
                history.append(PressurePoint(time: now, value: snapshot.pressureValue, level: snapshot.pressure))
                if history.count > self.historyCapacity {
                    history.removeFirst(history.count - self.historyCapacity)
                }
                self.pressureHistory = history
                self.isRefreshing = false
            }
        }
    }
}
