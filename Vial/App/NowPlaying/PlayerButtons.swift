//
//  PlayerButtons.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 15.12.2024.
//

import SwiftUI

struct PlayerButtons: View {
    let spacing: CGFloat
    let imageSize: CGFloat = 34
    @State var backwardAnimationTrigger: PlayerButtonTrigger = .one(bouncing: false)
    @State var forwardAnimationTrigger: PlayerButtonTrigger = .one(bouncing: false)

    var body: some View {
        HStack(spacing: spacing) {
            PlayerButton(
                label: {
                    PlayerButtonLabel(
                        type: .backward,
                        size: imageSize,
                        animationTrigger: backwardAnimationTrigger
                    )
                },
                onEnded: {
                    backwardAnimationTrigger.toggle(bouncing: true)

                }
            )

            PlayerButton(
                label: {
                    PlayerButtonLabel(type: .play, size: imageSize)
                },
                onEnded: {}
            )

            PlayerButton(
                label: {
                    PlayerButtonLabel(
                        type: .forward,
                        size: imageSize,
                        animationTrigger: forwardAnimationTrigger
                    )
                },
                onEnded: {
                    forwardAnimationTrigger.toggle(bouncing: true)

                }
            )
        }
        .playerButtonStyle(.expandedPlayer)
        .disabled(true)
    }
}

extension PlayerButtonConfig {
    static var expandedPlayer: Self {
        Self(
            labelColor: .init(Palette.PlayerCard.opaque),
            tint: .init(Palette.PlayerCard.translucent.withAlphaComponent(0.3)),
            pressedColor: .init(Palette.PlayerCard.opaque)
        )
    }
}
