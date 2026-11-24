//
//  ExpandableNowPlaying.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 17.11.2024.
//

import SwiftUI

enum PlayerMatchedGeometry {
    case artwork
}

struct CompactPlayerAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

struct ExpandableNowPlaying: View {
    @Binding var expanded: Bool
    @Binding var stackProgress: CGFloat
    let compactAnchor: Anchor<CGRect>?

    @State private var offsetY: CGFloat = 0
    @State private var isPullingDown: Bool?
    @State private var expandProgress: CGFloat = 0
    @State private var isAdjustingVolume = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var animationNamespace

    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            let full = CGRect(
                x: -safeArea.leading, y: -safeArea.top,
                width: geometry.size.width + safeArea.leading + safeArea.trailing,
                height: geometry.size.height + safeArea.top + safeArea.bottom
            )
            let compact = compactAnchor.map { geometry[$0] } ?? CGRect(
                x: 12,
                y: max(0, geometry.size.height - 54 - ViewConst.compactNowPlayingHeight),
                width: max(0, geometry.size.width - 24),
                height: ViewConst.compactNowPlayingHeight
            )
            if compact.width > 0 || expanded {
                let frame = expanded ? full : compact

                ZStack(alignment: .top) {
                    NowPlayingBackground(
                        colors: [Color(white: 0.22), Color(white: 0.36), Color(white: 0.45)],
                        expanded: expanded,
                        isFullExpanded: expandProgress >= 1
                    )
                    CompactNowPlaying(
                        open: { setExpanded(true) },
                        expanded: expanded,
                        animationNamespace: animationNamespace
                    )
                    .opacity(expanded ? 0 : 1)
                    .allowsHitTesting(!expanded)
                    .accessibilityHidden(expanded)

                    if expanded {
                        RegularNowPlaying(
                            size: full.size,
                            safeArea: safeArea,
                            animationNamespace: animationNamespace,
                            isAdjustingVolume: $isAdjustingVolume,
                            close: { setExpanded(false) }
                        )
                        .environment(\.colorScheme, .dark)
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { setExpanded(false) }
                        .transition(.identity)
                    }

                    ProgressTracker(progress: stackProgress)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(width: frame.width, height: frame.height, alignment: .top)
                .contentShape(.rect)
                .offset(x: frame.minX, y: frame.minY + offsetY)
                .gesture(
                    PanGesture(
                        onChange: { handleGestureChange(value: $0, height: full.height) },
                        onEnd: { handleGestureEnd(value: $0, height: full.height) },
                        onCancel: { setExpanded(expanded) },
                        isEnabled: expanded
                    )
                )
            }
        }
        .onPreferenceChange(NowPlayingExpandProgressPreferenceKey.self) { progress in
            expandProgress = progress
        }
    }

    private func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .playerExpandAnimation) {
            expanded = value
            stackProgress = value ? 1 : 0
            offsetY = 0
        }
        isPullingDown = nil
    }

    private func handleGestureChange(value: PanGesture.Value, height: CGFloat) {
        guard expanded, height > 0 else { return }
        if isPullingDown == nil {
            isPullingDown = !isAdjustingVolume && value.translation.height > abs(value.translation.width)
        }
        guard isPullingDown == true, !isAdjustingVolume else { return }
        let translation = max(value.translation.height, 0)
        offsetY = reduceMotion ? 0 : translation
        stackProgress = 1 - min(translation / height, 1)
    }

    private func handleGestureEnd(value: PanGesture.Value, height: CGFloat) {
        guard expanded else { return }
        let translation = max(value.translation.height, 0)
        let velocity = value.velocity.height / 5
        let dismiss = isPullingDown == true && !isAdjustingVolume &&
            translation + velocity > height * 0.3
        setExpanded(!dismiss)
    }
}

extension Animation {
    static var playerExpandAnimation: Animation {
        .smooth(duration: 0.3, extraBounce: 0)
    }
}

private struct ProgressTracker: View, Animatable {
    var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .preference(key: NowPlayingExpandProgressPreferenceKey.self, value: progress)
    }
}
