import SwiftUI
import TimerCore

/// v10: the app usage list shared by the day and the week view — same row
/// design in both: name, duration, proportional color bar, and a browser
/// domain disclosure where site data exists (week: aggregated per week).
struct ActivityAppListView: View {
    let apps: [AppUsage]                       // sorted by total desc
    let sitesByBrowser: [String: [SiteUsage]]
    let colorFor: (String) -> Color

    /// v9: the list keeps at least this much height before scrolling.
    static let listMinHeight: CGFloat = 160

    var body: some View {
        let maxTotal = apps.first?.totalSeconds ?? 1
        let visible = apps.filter { $0.totalSeconds >= 60 }
        let restSeconds = apps.filter { $0.totalSeconds < 60 }
            .reduce(0) { $0 + $1.totalSeconds }
        return ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(visible, id: \.bundleID) { app in
                    appRow(app, maxTotal: maxTotal)
                }
                if restSeconds >= 60 {
                    HStack {
                        Text("Sonstige").font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                        Text(TimeFormatting.wording(seconds: restSeconds))
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

    private func appRow(_ app: AppUsage, maxTotal: Double) -> some View {
        let sites = sitesByBrowser[app.bundleID] ?? []
        return VStack(alignment: .leading, spacing: 2) {
            if sites.isEmpty {
                appRowHeader(app, maxTotal: maxTotal)
            } else {
                DisclosureGroup {
                    siteList(sites)
                } label: {
                    appRowHeader(app, maxTotal: maxTotal)
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

    private func appRowHeader(_ app: AppUsage, maxTotal: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(app.name).font(.system(size: 13))
                Spacer()
                Text(TimeFormatting.wording(seconds: app.totalSeconds))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(colorFor(app.bundleID))
                    .frame(width: max(2, geo.size.width * app.totalSeconds / maxTotal))
            }
            .frame(height: 6)
        }
    }
}
