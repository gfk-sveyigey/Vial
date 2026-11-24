import SwiftUI
import UIKit

/// The media header follows the page for one fixed content-row height.
private struct MediaHeaderGeometry {
    let pageOffset: CGFloat
    let travel: CGFloat
    var progress: CGFloat { min(1, max(0, pageOffset / max(travel, 1))) }

    func position(afterScrollDelta delta: CGFloat, from position: CGFloat) -> CGFloat {
        min(1, max(0, position + delta / max(travel, 1)))
    }

    func position(afterScrollDelta delta: CGFloat, from position: CGFloat,
                  previousScrollOffset: CGFloat, scrollOffset: CGFloat) -> CGFloat {
        let height = max(travel, 1)
        guard delta < 0, position >= 1 else {
            return self.position(afterScrollDelta: delta, from: position)
        }

        // A collapsed header stays hidden while the page is still below its
        // original travel range. Only the portion past that boundary expands it.
        let expansionDistance = min(-delta, max(0, height - scrollOffset))
        guard previousScrollOffset > height || scrollOffset > height else {
            return self.position(afterScrollDelta: delta, from: position)
        }
        return min(1, max(0, position - expansionDistance / height))
    }

    func snapTarget(for position: CGFloat, expandedThreshold: CGFloat = 0.5,
                    collapsedThreshold: CGFloat = 0.5, preferScrollDirection: Bool = false,
                    scrollDirection: CGFloat = 0) -> CGFloat {
        let canExpand = position <= expandedThreshold
        let canCollapse = 1 - position <= collapsedThreshold
        if canExpand != canCollapse { return canExpand ? 0 : 1 }
        if canExpand && preferScrollDirection && scrollDirection != 0 {
            return scrollDirection > 0 ? 1 : 0
        }
        // Also choose the nearest endpoint when neither threshold is reached.
        return position < 0.5 ? 0 : 1
    }

    func boundedScrollOffset(_ offset: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(offset, 0), max(0, maximum))
    }

    func reconciledPosition(current: CGFloat, totalOffset: CGFloat) -> CGFloat? {
        if current < 1, totalOffset >= travel { return 1 }
        if current >= 1, totalOffset <= 0 { return 0 }
        return nil
    }

    func showsGlassWhenNotCollapsed(at position: CGFloat, pageTop: CGFloat, statusBarTop: CGFloat) -> Bool {
        let clampedPosition = min(1, max(0, position))
        guard clampedPosition < 1 else { return false }
        guard clampedPosition == 0 else { return true }
        return pageTop < statusBarTop
    }

    func edgeRegionHeight(statusBarHeight: CGFloat, position: CGFloat) -> CGFloat {
        max(0, statusBarHeight + travel - travel * position)
    }

    func curveProgress(position: CGFloat, curve: Int) -> CGFloat {
        let ratio = min(1, max(0, position))
        switch curve {
        case 0: return ratio
        case 2: return ratio * ratio
        case 3: return 1 - (1 - ratio) * (1 - ratio)
        case 4: return ratio * ratio * ratio * (ratio * (6 * ratio - 15) + 10)
        default: return ratio * ratio * (3 - 2 * ratio)
        }
    }

    func headerOpacity(position: CGFloat, curve: Int) -> CGFloat {
        1 - curveProgress(position: position, curve: curve)
    }

    func edgeTopStrength(minimum: Double, maximum: Double, heightCurve: Int) -> Double {
        let collapseProgress = Double(curveProgress(position: progress, curve: heightCurve))
        return minimum + (max(minimum, maximum) - minimum) * collapseProgress
    }

    func edgeBlurSamples(top: Double, bottom: Double, curve: Int) -> [Double] {
        (0...32).map { index in
            let progress = Double(curveProgress(position: CGFloat(index) / 32, curve: curve))
            return top + (bottom - top) * progress
        }
    }
}

// Scroll and glass behavior adapted from Vesper's immersive media header.
struct VialHeaderScrollView<Content: View>: View {
    let title: String
    private let content: Content
    @State private var showsAccount = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var mediaTitleScale: CGFloat = 1
    @AppStorage("debug.header.lightTint") private var lightTint = "#FFFFFF"
    @AppStorage("debug.header.darkTint") private var darkTint = "#000000"
    @ObservedObject private var layout = VialHeaderSettings.shared
    @State private var pageTopOffset: CGFloat = 0
    @State private var contentFitsViewport = true
    @State private var mediaHeaderPosition: CGFloat = 0
    @State private var mediaHeaderScroll: MediaHeaderScroll?
    @State private var mediaHeaderSnap: MediaHeaderSnap?
    @State private var hidesMediaGlassForCollapse = false
    @State private var followsReleasedMediaHeaderSnap = false

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    private var contentHeaderHeight: CGFloat { CGFloat(layout[.mediaHeaderHeight]) }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: contentHeaderHeight + topInset)
                        .accessibilityHidden(true)
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollEdgeEffectHidden(true, for: [.top, .bottom])
            .onScrollGeometryChange(for: ScrollMetrics.self) {
                ScrollMetrics(geometry: $0, includesTopInset: true)
            } action: { _, metrics in
                contentFitsViewport = metrics.contentHeight <= metrics.viewportHeight + 1
                pageTopOffset = metrics.offset
                if contentFitsViewport {
                    mediaHeaderScroll = nil
                    if mediaHeaderPosition != 0 || mediaHeaderSnap != nil {
                        settleMediaHeader(at: 0)
                    }
                } else {
                    updateMediaHeaderScroll(at: metrics.headerOffset)
                }
                restoreMediaHeaderAfterScrollToTop(offset: metrics.offset)
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                let metrics = ScrollMetrics(geometry: context.geometry, includesTopInset: true)
                let projected = oldPhase == .interacting && newPhase == .decelerating && (context.velocity?.dy ?? 0) > 0
                    ? metrics.projectedHeaderOffset(velocity: context.velocity) : nil
                updateMediaHeaderPhase(from: oldPhase, to: newPhase, offset: metrics.headerOffset,
                                       projectedOffset: projected)
            }
            .overlay(alignment: .top) {
                mediaHeader(topInset: topInset)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .sheet(isPresented: $showsAccount) {
            VialAccountSheet()
        }
        .task(id: mediaHeaderSnap) {
            guard let snap = mediaHeaderSnap else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, snap.end.timeIntervalSinceNow)))
            } catch { return }
            guard mediaHeaderSnap == snap else { return }
            settleMediaHeader(at: snap.target)
        }
    }

    private func updateMediaHeaderPhase(from oldPhase: ScrollPhase, to phase: ScrollPhase, offset: CGFloat,
                                        projectedOffset: CGFloat?) {
        followsReleasedMediaHeaderSnap = false
        guard !contentFitsViewport else { return }
        if oldPhase == .interacting && (phase == .decelerating || phase == .idle) {
            updateMediaHeaderScroll(at: offset)
            if (mediaHeaderScroll?.lastDirection ?? 0) > 0 {
                finishMediaHeaderScroll(at: offset, projectedOffset: projectedOffset)
                followsReleasedMediaHeaderSnap = phase == .decelerating
            }
        }
        switch phase {
        case .tracking:
            finishMediaHeaderScroll(at: offset)
        case .interacting, .animating:
            if mediaHeaderScroll == nil || phase == .animating {
                let position = mediaHeaderSnap?.position(at: .now) ?? mediaHeaderPosition
                mediaHeaderPosition = position
                mediaHeaderSnap = nil
                hidesMediaGlassForCollapse = false
                mediaHeaderScroll = MediaHeaderScroll(lastOffset: offset)
            }
            updateMediaHeaderScroll(at: offset)
        case .decelerating:
            updateMediaHeaderScroll(at: offset)
        case .idle:
            finishMediaHeaderScroll(at: offset)
            updateMediaHeaderScroll(at: offset)
            restoreMediaHeaderAfterScrollToTop(offset: offset)
        @unknown default:
            finishMediaHeaderScroll(at: offset)
        }
    }

    private func mediaHeader(topInset: CGFloat) -> some View {
        let headerHeight = contentHeaderHeight + topInset
        return TimelineView(.animation(paused: mediaHeaderSnap == nil)) { timeline in
            let position = mediaHeaderSnap?.position(at: timeline.date) ?? mediaHeaderPosition
            let displacement = contentHeaderHeight * position
            let isCollapsed = position >= 1
            let geometry = MediaHeaderGeometry(pageOffset: pageTopOffset, travel: contentHeaderHeight)
            let pageTop = -pageTopOffset
            let blurProgress = geometry.curveProgress(position: position, curve: layout[.mediaContentBlurCurve])
            let showsBackdrop = geometry.showsGlassWhenNotCollapsed(at: position, pageTop: pageTop, statusBarTop: 0)

            ZStack(alignment: .top) {
                VialMediaStatusBarBlur(displacement: displacement, travel: contentHeaderHeight, topInset: topInset)
                ZStack(alignment: .top) {
                    VialFadingBackdropBlur(style: .systemMaterial,
                        strength: Double(layout[.mediaGlassStrength]) / 100,
                        visibility: showsBackdrop ? 1 : 0, fadesAtBottom: false)
                        .frame(maxWidth: .infinity)
                        .frame(height: headerHeight, alignment: .top)
                        .animation(.easeInOut(duration: 0.14), value: showsBackdrop)
                        .overlay {
                            VialHeaderTint.color(colorScheme == .dark ? darkTint : lightTint)
                                .opacity(showsBackdrop ? Double(layout[.mediaGlassTint]) / 100 : 0)
                                .animation(.easeInOut(duration: 0.14), value: showsBackdrop)
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(uiColor: .label))
                                .frame(height: layout.mediaGlassBorderWidth)
                                .blur(radius: CGFloat(layout[.mediaGlassBorderBlur]))
                                .opacity(showsBackdrop ? Double(layout[.mediaGlassBorderOpacity]) / 100 : 0)
                                .animation(.easeInOut(duration: 0.14), value: showsBackdrop)
                        }
                        .opacity(isCollapsed || hidesMediaGlassForCollapse ? 0 : 1)
                        .animation(nil, value: isCollapsed)
                        .animation(nil, value: hidesMediaGlassForCollapse)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    HStack(alignment: .top) {
                        Text(title)
                            .font(.system(size: 34 * mediaTitleScale, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Button {
                            showsAccount = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 30, weight: .medium))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("账户")
                    }
                        .foregroundStyle(Color(uiColor: .label))
                        .padding(.horizontal, 15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: contentHeaderHeight, alignment: .top)
                        .padding(.top, topInset)
                        .compositingGroup()
                        .blur(radius: CGFloat(layout[.mediaContentBlur]) * blurProgress)
                        .opacity(geometry.headerOpacity(position: position, curve: layout[.mediaContentOpacityCurve]))
                        .allowsHitTesting(!isCollapsed)
                        .accessibilityHidden(isCollapsed)
                }
                .frame(height: headerHeight)
                .clipped()
                .offset(y: -displacement)
            }
            .frame(height: headerHeight, alignment: .top)
        }
    }

    private func restoreMediaHeaderAfterScrollToTop(offset: CGFloat) {
        guard !followsReleasedMediaHeaderSnap, offset <= 0,
              mediaHeaderPosition != 0 || mediaHeaderSnap != nil else { return }
        settleMediaHeaderImmediately(at: 0)
    }

    private func updateMediaHeaderScroll(at offset: CGFloat) {
        // Intermediate inertia offsets must not override the release decision.
        guard !followsReleasedMediaHeaderSnap else { return }
        var nextPosition = mediaHeaderSnap?.position(at: .now) ?? mediaHeaderPosition
        if var scroll = mediaHeaderScroll {
            nextPosition = scroll.updatePosition(
                at: offset,
                height: contentHeaderHeight,
                currentPosition: nextPosition
            )
            mediaHeaderScroll = scroll
        }

        if let corrected = reconciledMediaHeaderPosition(nextPosition, totalOffset: offset) {
            settleMediaHeaderImmediately(at: corrected)
        } else if mediaHeaderScroll != nil {
            mediaHeaderPosition = nextPosition
        }
    }

    private func reconciledMediaHeaderPosition(_ position: CGFloat, totalOffset: CGFloat) -> CGFloat? {
        MediaHeaderGeometry(pageOffset: 0, travel: contentHeaderHeight).reconciledPosition(
            current: position,
            totalOffset: totalOffset
        )
    }

    private func settleMediaHeaderImmediately(at position: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            mediaHeaderPosition = position
            mediaHeaderSnap = nil
            hidesMediaGlassForCollapse = position >= 1
        }
    }

    private func finishMediaHeaderScroll(at offset: CGFloat, projectedOffset: CGFloat? = nil) {
        guard mediaHeaderScroll != nil else { return }
        updateMediaHeaderScroll(at: offset)
        guard var scroll = mediaHeaderScroll else { return }
        mediaHeaderScroll = nil
        // Downward scrolling never snaps, including when inertia reaches idle.
        guard scroll.lastDirection > 0 else { return }
        let landingOffset = projectedOffset ?? offset
        let landingPosition = scroll.updatePosition(at: landingOffset, height: contentHeaderHeight,
                                                    currentPosition: mediaHeaderPosition)
        let geometry = MediaHeaderGeometry(pageOffset: 0, travel: contentHeaderHeight)
        let target = geometry.snapTarget(
            for: landingPosition,
            expandedThreshold: CGFloat(layout[.mediaSnapThreshold]) / 100,
            collapsedThreshold: CGFloat(layout[.mediaSnapCollapsedThreshold]) / 100,
            preferScrollDirection: layout[.mediaSnapConflict] == 0,
            scrollDirection: scroll.lastDirection
        )
        snapMediaHeader(to: reconciledMediaHeaderPosition(target, totalOffset: landingOffset) ?? target)
    }

    private func snapMediaHeader(to target: CGFloat) {
        // The backdrop disappears at release, while the foreground still snaps.
        hidesMediaGlassForCollapse = target >= 1
        guard !reduceMotion, mediaHeaderPosition != target else {
            settleMediaHeader(at: target)
            return
        }
        mediaHeaderSnap = MediaHeaderSnap(
            start: .now,
            initial: mediaHeaderPosition,
            target: target,
            duration: Double(layout[.mediaSnapDuration]) / 1000,
            curve: layout[.mediaSnapCurve]
        )
    }

    private func settleMediaHeader(at position: CGFloat) {
        mediaHeaderPosition = position
        mediaHeaderSnap = nil
        hidesMediaGlassForCollapse = position >= 1
    }

    private struct MediaHeaderScroll {
        var lastOffset: CGFloat
        var lastDirection: CGFloat = 0

        mutating func updatePosition(at offset: CGFloat, height: CGFloat, currentPosition: CGFloat) -> CGFloat {
            let delta = offset - lastOffset
            let previousOffset = lastOffset
            lastOffset = offset
            if delta != 0 { lastDirection = delta > 0 ? 1 : -1 }
            return MediaHeaderGeometry(pageOffset: 0, travel: height)
                .position(afterScrollDelta: delta, from: currentPosition,
                          previousScrollOffset: previousOffset, scrollOffset: offset)
        }
    }

    private struct MediaHeaderSnap: Equatable {
        let start: Date
        let initial: CGFloat
        let target: CGFloat
        let duration: TimeInterval
        let curve: Int

        var end: Date { start.addingTimeInterval(duration) }

        func position(at date: Date) -> CGFloat {
            let elapsed = CGFloat(date.timeIntervalSince(start) / duration)
            let fraction = min(1, max(0, elapsed))
            if fraction == 1 { return target }
            let progress = MediaHeaderGeometry(pageOffset: 0, travel: 1)
                .curveProgress(position: fraction, curve: curve)
            return initial + (target - initial) * progress
        }
    }

    private struct ScrollMetrics: Equatable {
        let offset: CGFloat
        let viewportHeight: CGFloat
        let contentHeight: CGFloat

        init(geometry: ScrollGeometry, includesTopInset: Bool) {
            let topInset = geometry.contentInsets.top
            offset = geometry.contentOffset.y + topInset
            viewportHeight = max(0, geometry.containerSize.height - geometry.contentInsets.bottom
                                 - (includesTopInset ? topInset : 0))
            contentHeight = geometry.contentSize.height
        }

        var headerOffset: CGFloat {
            // Header travel follows real content scrolling, not either edge's rubber-band.
            MediaHeaderGeometry(pageOffset: 0, travel: 1)
                .boundedScrollOffset(offset, maximum: contentHeight - viewportHeight)
        }

        func projectedHeaderOffset(velocity: CGVector?) -> CGFloat? {
            guard let speed = velocity?.dy, speed.isFinite else { return nil }
            // Project points/second using UIKit's normal per-millisecond decay.
            let rate = UIScrollView.DecelerationRate.normal.rawValue
            let distance = speed / 1000 * rate / (1 - rate)
            return MediaHeaderGeometry(pageOffset: 0, travel: 1)
                .boundedScrollOffset(headerOffset + distance, maximum: contentHeight - viewportHeight)
        }
    }

}

private struct VialAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var row = VialAccountRowSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: CGFloat(row[.avatarSize]), height: CGFloat(row[.avatarSize]))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("未登录")
                                .font(.system(size: CGFloat(row[.usernameSize]), weight: .semibold))
                            Text("占位信息")
                                .font(.system(size: CGFloat(row[.detailSize])))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, CGFloat(row[.top]))
                    .padding(.bottom, CGFloat(row[.bottom]))
                    .padding(.leading, CGFloat(row[.leading]))
                    .padding(.trailing, CGFloat(row[.trailing]))
                    .frame(maxWidth: .infinity, minHeight: CGFloat(row[.height]), alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, CGFloat(row[.outerTop]))
                    .padding(.bottom, CGFloat(row[.outerBottom]))
                    .padding(.leading, CGFloat(row[.outerLeading]))
                    .padding(.trailing, CGFloat(row[.outerTrailing]))
                    .accessibilityElement(children: .combine)

                    VialActionRow("应用设置", systemImage: "gear") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("账户")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

private struct VialMediaStatusBarBlur: View {
    let displacement: CGFloat
    let travel: CGFloat
    @ObservedObject private var layout = VialHeaderSettings.shared
    let topInset: CGFloat

    var body: some View {
        let geometry = MediaHeaderGeometry(pageOffset: displacement, travel: travel)
        let regionHeight = geometry.edgeRegionHeight(statusBarHeight: topInset, position: geometry.progress)
        if regionHeight > 0 {
            let resolvedTop = geometry.edgeTopStrength(
                minimum: Double(layout[.mediaEdgeTopStrength]) / 100,
                maximum: Double(layout[.mediaEdgeTopMaxStrength]) / 100,
                heightCurve: layout[.mediaEdgeHeightCurve]
            )
            let bottomStrength = Double(layout[.mediaEdgeBottomStrength]) / 100
            let tintStrength = Double(layout[.mediaEdgeTint]) / 100
            let samples = geometry.edgeBlurSamples(top: resolvedTop, bottom: bottomStrength, curve: layout[.mediaEdgeCurve])
            let peak = max(resolvedTop, bottomStrength)
            VialBackdropBlur(style: .regular, strength: peak,
                               verticalMask: samples.map { peak > 0 ? $0 / peak : 0 })
                .overlay {
                    LinearGradient(
                        colors: samples.map { Color(uiColor: .systemBackground).opacity(tintStrength * $0) },
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .frame(height: regionHeight)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Keep the backdrop mounted and interpolate the UIKit blur strength as visibility changes.
private struct VialFadingBackdropBlur: View, Animatable {
    let style: UIBlurEffect.Style
    let strength: Double
    nonisolated var visibility: Double
    let fadesAtBottom: Bool

    nonisolated var animatableData: Double {
        get { visibility }
        set { visibility = newValue }
    }

    var body: some View {
        VialBackdropBlur(style: style, strength: strength * visibility, fadesAtBottom: fadesAtBottom)
    }
}

/// A paused UIKit effect transition provides a public blur-strength control.
private struct VialBackdropBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style
    let strength: Double
    var fadesAtBottom = false
    var verticalMask: [Double]? = nil

    func makeUIView(context: Context) -> BackdropView {
        BackdropView(style: style, fadesAtBottom: fadesAtBottom || verticalMask != nil)
    }

    func updateUIView(_ view: BackdropView, context: Context) {
        view.setStrength(strength)
        if let verticalMask { view.setVerticalMask(verticalMask) }
    }

    final class BackdropView: UIVisualEffectView {
        private let blur: UIBlurEffect
        private let edgeMask: GradientMask?
        private var animator: UIViewPropertyAnimator?
        private var strength: Double?

        init(style: UIBlurEffect.Style, fadesAtBottom: Bool) {
            blur = UIBlurEffect(style: style)
            edgeMask = fadesAtBottom ? GradientMask() : nil
            super.init(effect: nil)
            isUserInteractionEnabled = false
            clipsToBounds = true
            mask = edgeMask
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func setStrength(_ value: Double) {
            let value = min(1, max(0, value))
            guard strength != value else { return }
            strength = value
            if value == 0 || value == 1 {
                animator?.stopAnimation(true)
                animator = nil
                effect = value == 0 ? nil : blur
                return
            }
            if animator == nil {
                effect = nil
                let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
                    guard let self else { return }
                    self.effect = self.blur
                }
                animator.pausesOnCompletion = true
                animator.startAnimation()
                animator.pauseAnimation()
                self.animator = animator
            }
            animator?.fractionComplete = value
        }

        private var maskSamples: [Double]?

        func setVerticalMask(_ samples: [Double]) {
            guard let edgeMask, maskSamples != samples else { return }
            maskSamples = samples
            let gradient = edgeMask.layer as! CAGradientLayer
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.colors = samples.map { UIColor.black.withAlphaComponent(CGFloat($0)).cgColor }
            gradient.locations = nil
            CATransaction.commit()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let edgeMask, edgeMask.frame != bounds else { return }
            edgeMask.frame = bounds
            mask = edgeMask
        }
    }

    private final class GradientMask: UIView {
        override class var layerClass: AnyClass { CAGradientLayer.self }

        init() {
            super.init(frame: .zero)
            let gradient = layer as! CAGradientLayer
            gradient.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
            gradient.locations = [0, 0.55, 1]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
