import SwiftUI
import TimerCore

/// Shared layout constants of the zoomable timelines (non-generic home so
/// the views can reference them in their height math).
enum TimelineZoom {
    static let controlsHeight: CGFloat = 16
}

/// Reports the horizontal scroll offset of the zoomable timeline content.
private struct TimelineScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// v11: the shared zoom-and-pan chrome of the activity timelines, extracted
/// unchanged from the v9 day timeline: a −/＋/1× control row (steps ×2,
/// clamp 1–16), one horizontal ScrollView whose content is
/// `viewport × zoom` wide, trackpad pinch centered on the pointer
/// (`onContinuousHover`), double-click ×2 centered on the clicked spot
/// (position from a simultaneous zero-distance drag — macOS-13-safe), and
/// a focal marker + `ScrollViewReader` keeping the zoom target centered.
/// Zoom is per-view-identity state: parents reset it by re-`id`-ing this
/// container's owner (date/week navigation, mode switch, window reopen).
///
/// The week view adds a fixed `leading` column (day labels, never scrolls)
/// left of the scroll area and an `onSingleClick` action (content
/// coordinates) arbitrated after the double-click via `ExclusiveGesture`,
/// so it fires only when no second click follows.
struct TimelineZoomContainer<Leading: View, Content: View>: View {
    /// Vertical gap between the control row and the scroll area.
    let spacing: CGFloat
    /// Width of the fixed leading column (0 = no column).
    let leadingWidth: CGFloat
    /// Horizontal gap between the leading column and the scroll area.
    let leadingGap: CGFloat
    /// Single-click action (content coordinates), fired only when no second
    /// click follows. nil = plain clicks do nothing (day view).
    let onSingleClick: ((CGPoint) -> Void)?
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let content: (_ width: CGFloat, _ viewportWidth: CGFloat) -> Content

    @State private var zoom: CGFloat = 1
    @State private var scrollOffset: CGFloat = 0
    @State private var focalFraction: CGFloat = 0.5
    /// Content-space location of the most recent mouse-down (double-click
    /// zoom target, single-click position).
    @State private var pressPoint: CGPoint?
    /// Content-space x under the pointer (pinch zoom target).
    @State private var hoverX: CGFloat?
    @State private var pinchBase: (zoom: CGFloat, focalX: CGFloat?)?

    private var minZoom: CGFloat { CGFloat(TimelineTicks.minZoom) }
    private var maxZoom: CGFloat { CGFloat(TimelineTicks.maxZoom) }
    private var focalMarkerID: String { "timelineFocalMarker" }
    private var scrollSpaceName: String { "timelineScroll" }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                let viewportWidth = max(geo.size.width - leadingWidth - leadingGap, 1)
                VStack(alignment: .leading, spacing: spacing) {
                    zoomControls(viewportWidth: viewportWidth, proxy: proxy)
                    if leadingWidth > 0 {
                        HStack(alignment: .top, spacing: leadingGap) {
                            leading().frame(width: leadingWidth, alignment: .leading)
                            scrollArea(viewportWidth: viewportWidth, proxy: proxy)
                        }
                    } else {
                        scrollArea(viewportWidth: viewportWidth, proxy: proxy)
                    }
                }
            }
        }
    }

    // MARK: - Controls

    private func zoomControls(viewportWidth: CGFloat, proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            Spacer()
            Button("−") {
                setZoom(zoom / 2, focusContentX: nil, viewportWidth: viewportWidth, proxy: proxy)
            }
            .disabled(zoom <= minZoom)
            .help("Rauszoomen")
            Button("＋") {
                setZoom(zoom * 2, focusContentX: nil, viewportWidth: viewportWidth, proxy: proxy)
            }
            .disabled(zoom >= maxZoom)
            .help("Reinzoomen")
            Button("1×") {
                setZoom(1, focusContentX: nil, viewportWidth: viewportWidth, proxy: proxy)
            }
            .disabled(zoom <= minZoom)
            .help("Zoom zurücksetzen")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(height: TimelineZoom.controlsHeight)
    }

    // MARK: - Scroll area

    private func scrollArea(viewportWidth: CGFloat, proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            zoomedContent(viewportWidth: viewportWidth, proxy: proxy)
        }
        .coordinateSpace(name: scrollSpaceName)
        .onPreferenceChange(TimelineScrollOffsetKey.self) { scrollOffset = $0 }
    }

    private func zoomedContent(viewportWidth: CGFloat, proxy: ScrollViewProxy) -> some View {
        let width = max(viewportWidth, 1) * zoom
        return content(width, viewportWidth)
            .frame(width: width)
            .background(scrollOffsetReader)
            .background(alignment: .topLeading) { focalMarker(width: width) }
            .onContinuousHover { phase in
                if case .active(let point) = phase { hoverX = point.x } else { hoverX = nil }
            }
            // macOS 13 has no tap-with-location API; a simultaneous
            // zero-distance drag records each mouse-down, so the taps know
            // where the click landed.
            .gesture(clickGestures(viewportWidth: viewportWidth, proxy: proxy))
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).onChanged { pressPoint = $0.startLocation }
            )
            .simultaneousGesture(pinchGesture(viewportWidth: viewportWidth, proxy: proxy))
    }

    /// Double-click ×2 takes precedence; the single-click action (if any)
    /// is arbitrated via `ExclusiveGesture`, so it fires only after the
    /// double-click window passes without a second click.
    private func clickGestures(viewportWidth: CGFloat, proxy: ScrollViewProxy) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                setZoom(
                    zoom * 2, focusContentX: pressPoint?.x,
                    viewportWidth: viewportWidth, proxy: proxy
                )
            }
            .exclusively(before: TapGesture().onEnded {
                if let onSingleClick, let point = pressPoint { onSingleClick(point) }
            })
    }

    // MARK: - Zoom mechanics

    /// Applies a clamped zoom and re-centers the focal point: the time at
    /// `focusContentX` (content coordinates; nil = current viewport center)
    /// ends up in the middle of the viewport.
    private func setZoom(
        _ target: CGFloat, focusContentX: CGFloat?,
        viewportWidth: CGFloat, proxy: ScrollViewProxy
    ) {
        let clamped = min(max(target, minZoom), maxZoom)
        guard clamped != zoom, viewportWidth > 0 else { return }
        let oldContentWidth = viewportWidth * zoom
        let focalX = focusContentX ?? (scrollOffset + viewportWidth / 2)
        focalFraction = min(max(focalX / oldContentWidth, 0), 1)
        zoom = clamped
        // The marker sits at the focal fraction of the resized content;
        // scrolling it to center is deferred one runloop turn so the new
        // content width is laid out first.
        let markerID = focalMarkerID
        DispatchQueue.main.async {
            proxy.scrollTo(markerID, anchor: .center)
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
            .id(focalMarkerID)
            .padding(.leading, min(max(focalFraction, 0), 1) * max(width - 1, 0))
            .allowsHitTesting(false)
    }

    private var scrollOffsetReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: TimelineScrollOffsetKey.self,
                value: -geo.frame(in: .named(scrollSpaceName)).minX
            )
        }
    }
}

extension TimelineZoomContainer where Leading == EmptyView {
    /// Container without a leading column (the day timeline).
    init(
        spacing: CGFloat,
        onSingleClick: ((CGPoint) -> Void)? = nil,
        @ViewBuilder content: @escaping (_ width: CGFloat, _ viewportWidth: CGFloat) -> Content
    ) {
        self.init(
            spacing: spacing, leadingWidth: 0, leadingGap: 0,
            onSingleClick: onSingleClick, leading: { EmptyView() }, content: content
        )
    }
}
