import SwiftUI
import TimerCore

struct ActivityView: View {
    let store: ActivityStore

    @State private var day = Date()
    @State private var summary: DaySummary?

    private static let palette: [Color] = [
        Color(red: 0.50, green: 0.47, blue: 0.87),
        Color(red: 0.36, green: 0.79, blue: 0.65),
        Color(red: 0.94, green: 0.60, blue: 0.48),
        Color(red: 0.83, green: 0.33, blue: 0.49),
        Color(red: 0.22, green: 0.54, blue: 0.87),
        Color(red: 0.59, green: 0.77, blue: 0.35),
        Color(red: 0.94, green: 0.62, blue: 0.15),
        Color(red: 0.53, green: 0.53, blue: 0.50),
    ]

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EE, d. MMMM"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let summary, summary.firstActivity != nil {
                presenceLine(summary)
                timeline(summary)
                appList(summary)
            } else {
                Text("Keine Daten für diesen Tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            }
            Text("Alle Daten bleiben lokal auf diesem Mac")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear(perform: reload)
    }

    private var header: some View {
        HStack {
            Button("‹") { shift(by: -1) }.buttonStyle(.plain)
            Spacer()
            Text(Self.titleFormatter.string(from: day))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("›") { shift(by: 1) }
                .buttonStyle(.plain)
                .disabled(isToday)
                .foregroundStyle(isToday ? .tertiary : .primary)
        }
    }

    private func shift(by days: Int) {
        guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        day = min(shifted, Date())
        reload()
    }

    private func reload() {
        summary = store.daySummary(for: day)
    }

    private func presenceLine(_ summary: DaySummary) -> some View {
        HStack {
            Text("Am PC")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if let first = summary.firstActivity, let last = summary.lastActivity {
                Text("\(Self.hourFormatter.string(from: first)) – \(Self.hourFormatter.string(from: last)) · aktiv \(TimeFormatting.wording(seconds: summary.presenceSeconds))")
                    .font(.system(size: 11, design: .monospaced))
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private func colorFor(bundleID: String, in summary: DaySummary) -> Color {
        let rank = summary.apps.firstIndex { $0.bundleID == bundleID } ?? Self.palette.count - 1
        return Self.palette[min(rank, Self.palette.count - 1)]
    }

    private func timeline(_ summary: DaySummary) -> some View {
        guard let first = summary.firstActivity, let last = summary.lastActivity,
              last > first else {
            return AnyView(EmptyView())
        }
        let span = last.timeIntervalSince(first)
        let allSegments = summary.apps.flatMap(\.segments)
        return AnyView(VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.6))
                    ForEach(allSegments) { segment in
                        if case .app(let bundleID, _) = segment.kind {
                            let x = segment.start.timeIntervalSince(first) / span
                            let w = segment.end.timeIntervalSince(segment.start) / span
                            Rectangle()
                                .fill(colorFor(bundleID: bundleID, in: summary))
                                .frame(width: max(1, geo.size.width * w))
                                .offset(x: geo.size.width * x)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 22)
            HStack {
                Text(Self.hourFormatter.string(from: first))
                Spacer()
                Text(Self.hourFormatter.string(from: first.addingTimeInterval(span / 2)))
                Spacer()
                Text(Self.hourFormatter.string(from: last))
            }
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
        })
    }

    private func appList(_ summary: DaySummary) -> some View {
        let maxTotal = summary.apps.first?.totalSeconds ?? 1
        let visible = summary.apps.filter { $0.totalSeconds >= 60 }
        let restSeconds = summary.apps.filter { $0.totalSeconds < 60 }
            .reduce(0) { $0 + $1.totalSeconds }
        return ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(visible, id: \.bundleID) { app in
                    appRow(app, maxTotal: maxTotal, summary: summary)
                }
                if restSeconds >= 60 {
                    HStack {
                        Text("Sonstige").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(TimeFormatting.wording(seconds: restSeconds))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private func appRow(_ app: AppUsage, maxTotal: Double, summary: DaySummary) -> some View {
        let sites = summary.sitesByBrowser[app.bundleID] ?? []
        return VStack(alignment: .leading, spacing: 2) {
            if sites.isEmpty {
                appRowHeader(app, maxTotal: maxTotal, summary: summary)
            } else {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(sites, id: \.domain) { site in
                            HStack {
                                Text(site.domain)
                                    .font(.system(size: 10, design: .monospaced))
                                Spacer()
                                Text(TimeFormatting.wording(seconds: site.totalSeconds))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 10)
                } label: {
                    appRowHeader(app, maxTotal: maxTotal, summary: summary)
                }
            }
        }
    }

    private func appRowHeader(_ app: AppUsage, maxTotal: Double, summary: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(app.name).font(.system(size: 11))
                Spacer()
                Text(TimeFormatting.wording(seconds: app.totalSeconds))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorFor(bundleID: app.bundleID, in: summary))
                    .frame(width: max(2, geo.size.width * app.totalSeconds / maxTotal))
            }
            .frame(height: 4)
        }
    }
}
