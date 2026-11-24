//
//  CompactNowPlaying.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 20.11.2024.
//

import SwiftUI

struct CompactNowPlaying: View {
    let open: () -> Void
    let expanded: Bool
    private var settings = MiniPlayerArtworkSettings()
    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 14
    var animationNamespace: Namespace.ID
    @State var forwardAnimationTrigger: PlayerButtonTrigger = .one(bouncing: false)

    init(open: @escaping () -> Void, expanded: Bool, animationNamespace: Namespace.ID) {
        self.open = open
        self.expanded = expanded
        self.animationNamespace = animationNamespace
    }

    var body: some View {
        HStack(spacing: 8) {
            artwork
                .frame(width: CGFloat(settings.side), height: CGFloat(settings.side))
                .padding(.leading, CGFloat(settings.leading))
                .padding(.trailing, CGFloat(settings.trailing))

            Text("未在播放")
                .lineLimit(1)
                .font(.system(size: titleSize, weight: .medium))

            Spacer(minLength: 0)

            PlayerButton(
                label: {
                    PlayerButtonLabel(type: .play, size: 20)
                },
                onEnded: {}
            )
            .playerButtonStyle(.miniPlayer)
            .disabled(true)

            PlayerButton(
                label: {
                    PlayerButtonLabel(
                        type: .forward,
                        size: 30,
                        animationTrigger: forwardAnimationTrigger
                    )
                },
                onEnded: {
                    forwardAnimationTrigger.toggle(bouncing: true)
                }
            )
            .playerButtonStyle(.miniPlayer)
            .disabled(true)
        }
        .padding(.trailing, 8)
        .frame(height: ViewConst.compactNowPlayingHeight)
        .contentShape(.rect)
        .transformEffect(.identity)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }
}

private extension CompactNowPlaying {
    @ViewBuilder
    var artwork: some View {
        if !expanded {
            PlayerArtworkPlaceholder(iconSize: CGFloat(settings.side) * 15 / 32, cornerRadius: CGFloat(settings.side) * 7 / 32)
                .accessibilityHidden(true)
                .matchedGeometryEffect(
                    id: PlayerMatchedGeometry.artwork,
                    in: animationNamespace
                )
        }
    }
}

extension PlayerButtonConfig {
    static var miniPlayer: Self {
        Self(
            size: 44,
            tint: .init(Palette.PlayerCard.translucent.withAlphaComponent(0.3))
        )
    }
}
