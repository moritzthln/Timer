import SwiftUI
import TimerCore

/// v10: the app usage list shared by the day and the week view — same row
/// design in both: name, duration, 7-day sparkline, proportional color bar,
/// and a browser domain disclosure where site data exists (week: aggregated
/// per week). Clicking a row selects the app for the timeline drill-down;
/// clicking it again (or another row) deselects/switches.
struct ActivityAppListView: View {
    let apps: [AppUsage]                       // sorted by total desc
    let sitesByBrowser: [String: [SiteUsage]]
    let colorFor: (String) -> Color
    let sparkSeries: [String: [Double]]        // bundle id -> 7 daily seconds
    let sparkHelp: String
    let selectedBundleID: String?
    let onSelect: (String) -> Void
    /// v12.1: the focus filter lowers this to 10 s — short sessions would
    /// otherwise fold every app into Sonstige.
    var foldThreshold: Double = 60

    /// v9: the list keeps at least this much height before scrolling.
    static let listMinHeight: CGFloat = 160

    var body: some View {
        let maxTotal = apps.first?.totalSeconds ?? 1
        // v14: percentage basis — every row of the displayed period incl.
        // the folded rest (with the focus filter on, the rows are already
        // clipped, so shares are fractions of the focus time).
        let basis = apps.reduce(0) { $0 + $1.totalSeconds }
        let visible = apps.filter { $0.totalSeconds >= foldThreshold }
        let restSeconds = apps.filter { $0.totalSeconds < foldThreshold }
            .reduce(0) { $0 + $1.totalSeconds }
        return ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(visible, id: \.bundleID) { app in
                    appRow(app, maxTotal: maxTotal, basis: basis)
                }
                if restSeconds >= foldThreshold {
                    HStack {
                        Text("Sonstige").font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                        Text(rowValue(seconds: restSeconds, basis: basis))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: Self.listMinHeight, maxHeight: .infinity,
            alignment: .top
        )
    }

    /// v14: "2 h 41 min · 39 %" — the row's share of `basis` right of the
    /// duration; just the duration when there is no share (basis 0).
    private func rowValue(seconds: Double, basis: Double) -> String {
        let duration = TimeFormatting.wording(seconds: seconds)
        guard let percent = UsageShare.percentLabel(seconds: seconds, total: basis) else {
            return duration
        }
        return "\(duration) · \(percent)"
    }

    private func appRow(_ app: AppUsage, maxTotal: Double, basis: Double) -> some View {
        let sites = sitesByBrowser[app.bundleID] ?? []
        return VStack(alignment: .leading, spacing: 2) {
            if sites.isEmpty {
                appRowHeader(app, maxTotal: maxTotal, basis: basis)
            } else {
                DisclosureGroup {
                    siteList(sites)
                } label: {
                    appRowHeader(app, maxTotal: maxTotal, basis: basis)
                }
            }
        }
    }

    private func siteList(_ sites: [SiteUsage]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sites, id: \.domain) { site in
                HStack {
                    Text(site.domain)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Text(TimeFormatting.wording(seconds: site.totalSeconds))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 10)
    }

    private func appRowHeader(_ app: AppUsage, maxTotal: Double, basis: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(app.name).font(.system(size: 13))
                Spacer()
                Text(rowValue(seconds: app.totalSeconds, basis: basis))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                ActivitySparklineView(
                    values: sparkSeries[app.bundleID] ?? Array(repeating: 0, count: 7),
                    help: sparkHelp
                )
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(colorFor(app.bundleID))
                    .frame(width: max(2, geo.size.width * app.totalSeconds / maxTotal))
            }
            .frame(height: 6)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(app.bundleID) }
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary.opacity(selectedBundleID == app.bundleID ? 0.7 : 0))
                .padding(-4)
        }
    }
}
