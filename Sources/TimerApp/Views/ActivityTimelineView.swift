import SwiftUI
import TimerCore

/// Reports the horizontal scroll offset of the timeline content.
private struct TimelineScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// v9: zoomable, pannable day timeline with adaptive tick labels and
/// per-segment tooltips. Zoom is per-window-session state: the parent tags
/// this view with `.id(day)` (reset on date change) and the stats window
/// rebuilds its view tree on every open (reset on reopen). Only this strip
/// scrolls horizontally — the rest of the tab never does.
struct ActivityTimelineView: View {
    let first: Date
    let last: Date
    let summary: DaySummary
    let colorFor: (String) -> Color
    /// v10 drill-down: with a selection, other apps' segments dim to 0.15.
    let selectedBundleID: String?

    @State private var zoom: CGFloat = 1
    @State private var scrollOffset: CGFloat = 0
    @State private var focalFraction: CGFloat = 0.5
    /// Content-space x of the most recent mouse-down (double-click zoom target).
    @State private var pressX: CGFloat?
    /// Content-space x under the pointer (pinch zoom target).
    @State private var hoverX: CGFloat?
    @State private var pinchBase: (zoom: CGFloat, focalX: CGFloat?)?

    private static let barHeight: CGFloat = 32
    private static let controlsHeight: CGFloat = 16
    private static let labelHeight: CGFloat = 12
    private static let rowSpacing: CGFloat = 3
    /// Fixed total height: controls + bar + tick labels + two gaps.
    static let totalHeight: CGFloat = controlsHeight + barHeight + labelHeight + 2 * rowSpacing

    private static let minZoom = CGFloat(TimelineTicks.minZoom)
    private static let maxZoom = CGFloat(TimelineTicks.maxZoom)
    private static let focalMarkerID = "timelineFocalMarker"
    private static let scrollSpaceName = "timelineScroll"

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private var span: TimeInterval { last.timeIntervalSince(first) }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    zoomControls(viewportWidth: geo.size.width, proxy: proxy)
                    scrollArea(viewportWidth: geo.size.width, proxy: proxy)
                }
            }
        }
        .frame(height: Self.totalHeight)
    }

    // MARK: - Controls

    private func zoomControls(viewportWidth: CGFloat, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            Spacer()
            Button("−") {
                setZoom(zoom / 2, focusContentX: nil, viewportWidth: viewportWidth, proxy: proxy)
            }
            .disabled(zoom <= Self.minZoom)
            .help("Rauszoomen")
            Button("＋") {
                setZoom(zoom * 2, focusContentX: nil, viewportWidth: viewportWidth, proxy: proxy)
            }
            .disabled(zoom >= Self.maxZoom)
            .help("Reinzoomen")
            Button("1×") {
                setZoom(1, focusContentX: nil, viewportWidth: viewportWidth, proxy: proxy)
            }
            .disabled(zoom <= Self.minZoom)
            .help("Zoom zurücksetzen")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(height: Self.controlsHeight)
    }

    // MARK: - Scroll area

    private func scrollArea(viewportWidth: CGFloat, proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            timelineContent(viewportWidth: viewportWidth, proxy: proxy)
        }
        .coordinateSpace(name: Self.scrollSpaceName)
        .onPreferenceChange(TimelineScrollOffsetKey.self) { scrollOffset = $0 }
    }

    private func timelineContent(viewportWidth: CGFloat, proxy: ScrollViewProxy) -> some View {
        let width = max(viewportWidth, 1) * zoom
        return VStack(alignment: .leading, spacing: Self.rowSpacing) {
            bar(width: width)
            tickLabels(width: width, viewportWidth: viewportWidth)
        }
        .frame(width: width)
        .background(scrollOffsetReader)
        .background(alignment: .topLeading) { focalMarker(width: width) }
        .onContinuousHover { phase in
            if case .active(let point) = phase { hoverX = point.x } else { hoverX = nil }
        }
        // macOS 13 has no tap-with-location API; a simultaneous zero-distance
        // drag records each mouse-down, so the double-click zooms on the
        // second click's position.
        .onTapGesture(count: 2) {
            setZoom(zoom * 2, focusContentX: pressX, viewportWidth: viewportWidth, proxy: proxy)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { pressX = $0.startLocation.x }
        )
        .simultaneousGesture(pinchGesture(viewportWidth: viewportWidth, proxy: proxy))
    }

    // MARK: - Bar and tick labels

    private func bar(width: CGFloat) -> some View {
        let allSegments = summary.apps.flatMap(\.segments)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.6))
            ForEach(allSegments) { segment in
                if case .app(let bundleID, let name) = segment.kind {
                    let x = segment.start.timeIntervalSince(first) / span
                    let w = segment.end.timeIntervalSince(segment.start) / span
                    Rectangle()
                        .fill(colorFor(bundleID))
                        .opacity(dimOpacity(for: bundleID))
                        .frame(width: max(1, width * w))
                        .offset(x: width * x)
                        .help(Self.tooltip(name: name, segment: segment))
                }
            }
        }
        .frame(width: width, height: Self.barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func dimOpacity(for bundleID: String) -> Double {
        guard let selectedBundleID else { return 1 }
        return selectedBundleID == bundleID ? 1 : 0.15
    }

    /// "Safari · 9:12–9:47 (35 min)". Presence gaps draw no segment rect,
    /// so they naturally get no tooltip.
    static func tooltip(name: String, segment: ActivitySegment) -> String {
        let start = hourFormatter.string(from: segment.start)
        let end = hourFormatter.string(from: segment.end)
        let duration = TimeFormatting.wording(
            seconds: segment.end.timeIntervalSince(segment.start)
        )
        return "\(name) · \(start)–\(end) (\(duration))"
    }

    private func tickLabels(width: CGFloat, viewportWidth: CGFloat) -> some View {
        let interval = TimelineTicks.tickIntervalMinutes(
            zoom: zoom, spanMinutes: span / 60, viewportWidth: viewportWidth
        )
        return Group {
            if let interval {
                intervalTickLabels(width: width, intervalMinutes: interval)
            } else {
                coarseTickLabels()
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .frame(width: width, height: Self.labelHeight, alignment: .topLeading)
    }

    private func coarseTickLabels() -> some View {
        HStack {
            Text(Self.hourFormatter.string(from: first))
            Spacer()
            Text(Self.hourFormatter.string(from: first.addingTimeInterval(span / 2)))
            Spacer()
            Text(Self.hourFormatter.string(from: last))
        }
    }

    private func intervalTickLabels(width: CGFloat, intervalMinutes: Int) -> some View {
        let offsets = TimelineTicks.tickOffsetsMinutes(
            startMinuteOfDay: Self.minuteOfDay(of: first),
            spanMinutes: span / 60,
            intervalMinutes: intervalMinutes
        )
        return ZStack(alignment: .topLeading) {
            ForEach(offsets, id: \.self) { offset in
                Text(Self.hourFormatter.string(from: first.addingTimeInterval(offset * 60)))
                    .fixedSize()
                    .position(x: width * offset / (span / 60), y: Self.labelHeight / 2)
            }
        }
    }

    private static func minuteOfDay(of date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return Double(comps.hour ?? 0) * 60 + Double(comps.minute ?? 0)
            + Double(comps.second ?? 0) / 60
    }

    // MARK: - Zoom mechanics

    /// Applies a clamped zoom and re-centers the focal point: the time at
    /// `focusContentX` (content coordinates; nil = current viewport center)
    /// ends up in the middle of the viewport.
    private func setZoom(
        _ target: CGFloat, focusContentX: CGFloat?,
        viewportWidth: CGFloat, proxy: ScrollViewProxy
    ) {
        let clamped = min(max(target, Self.minZoom), Self.maxZoom)
        guard clamped != zoom, viewportWidth > 0 else { return }
        let oldContentWidth = viewportWidth * zoom
        let focalX = focusContentX ?? (scrollOffset + viewportWidth / 2)
        focalFraction = min(max(focalX / oldContentWidth, 0), 1)
        zoom = clamped
        // The marker sits at the focal fraction of the resized content;
        // scrolling it to center is deferred one runloop turn so the new
        // content width is laid out first.
        DispatchQueue.main.async {
            proxy.scrollTo(Self.focalMarkerID, anchor: .center)
        }
    }

    private func pinchGesture(viewportWidth: CGFloat, proxy: ScrollViewProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Freeze zoom and focal point at pinch start; `value` is the
                // relative magnification since then.
                if pinchBase == nil { pinchBase = (zoom, hoverX) }
                guard let base = pinchBase else { return }
                setZoom(
                    base.zoom * value, focusContentX: base.focalX,
                    viewportWidth: viewportWidth, proxy: proxy
                )
            }
            .onEnded { _ in pinchBase = nil }
    }

    /// 1×1 pt invisible layout marker at the focal fraction of the content;
    /// `scrollTo(_:anchor: .center)` centers it in the viewport.
    private func focalMarker(width: CGFloat) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .id(Self.focalMarkerID)
            .padding(.leading, min(max(focalFraction, 0), 1) * max(width - 1, 0))
            .allowsHitTesting(false)
    }

    private var scrollOffsetReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: TimelineScrollOffsetKey.self,
                value: -geo.frame(in: .named(Self.scrollSpaceName)).minX
            )
        }
    }
}
