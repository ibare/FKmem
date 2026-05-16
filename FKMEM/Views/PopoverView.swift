import AppKit
import Charts
import SwiftUI

struct PopoverView: View {
    let store: MemoryStore

    private let displayThreshold: UInt64 = 100 * 1024 * 1024
    private let chartWindowSeconds: TimeInterval = 180

    var body: some View {
        VStack(spacing: 0) {
            header
            pressureChart
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 360, height: 480)
        .background(.regularMaterial)
    }

    private var pressureChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("메모리 압력")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Chart(store.pressureHistory) { point in
                AreaMark(
                    x: .value("time", point.time),
                    yStart: .value("y0", 0.0),
                    yEnd: .value("y1", max(0.06, point.value))
                )
                .foregroundStyle(chartColor.opacity(0.55))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("time", point.time),
                    y: .value("y", max(0.06, point.value))
                )
                .foregroundStyle(chartColor)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...1)
            .chartXScale(domain: chartXDomain)
            .chartPlotStyle { plot in
                plot.background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 56)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var chartXDomain: ClosedRange<Date> {
        let end = store.pressureHistory.last?.time ?? Date()
        return end.addingTimeInterval(-chartWindowSeconds)...end
    }

    private var chartColor: Color {
        switch store.snapshot.pressure {
        case .normal: return .green
        case .warn: return .yellow
        case .critical: return .red
        }
    }

    private var filteredEntries: [AppMemoryEntry] {
        store.entries.filter { $0.bytes >= displayThreshold }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FKMEM")
                    .font(.system(size: 13, weight: .semibold))
                Text(summaryLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("새로고침")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let visible = filteredEntries
                if visible.isEmpty {
                    Text(store.lastUpdate == .distantPast ? "측정 중…" : "100MB 이상 사용 중인 앱이 없습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ForEach(visible) { entry in
                        EntryRow(entry: entry)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("마지막 갱신: \(timeString)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("종료") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    private var summaryLine: String {
        let total = MemoryFormatter.format(store.snapshot.appBytes)
        let available = MemoryFormatter.format(store.snapshot.availableBytes)
        let pressureLabel: String
        switch store.snapshot.pressure {
        case .normal: pressureLabel = "정상"
        case .warn: pressureLabel = "주의"
        case .critical: pressureLabel = "위험"
        }
        return "총 사용 \(total) · 가용 \(available) · 압력: \(pressureLabel)"
    }

    private var timeString: String {
        guard store.lastUpdate != .distantPast else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: store.lastUpdate)
    }
}

private struct EntryRow: View {
    let entry: AppMemoryEntry
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            iconView
                .frame(width: 18, height: 18)
            Text(entry.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(MemoryFormatter.format(entry.bytes))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        if let path = entry.bundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
