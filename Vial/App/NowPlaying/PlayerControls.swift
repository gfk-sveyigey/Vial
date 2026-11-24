//
//  PlayerControls.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 01.12.2024.
//

import SwiftUI

struct PlayerControls: View {
    @Binding var isAdjustingVolume: Bool

    var body: some View {
        GeometryReader {
            let size = $0.size
            let spacing = size.verticalSpacing
            VStack(spacing: 0) {
                VStack(spacing: spacing) {
                    trackInfo
                    let indicatorPadding = ViewConst.playerCardPaddings - ElasticSliderConfig.playbackProgress.growth
                    TimingIndicator()
                        .padding(.top, spacing)
                        .padding(.horizontal, indicatorPadding)
                }
                .frame(height: max(0, (size.height - 68) / 2), alignment: .top)
                PlayerButtons(spacing: min(48, size.width * 0.14))
                    .padding(.horizontal, ViewConst.playerCardPaddings)
                volume(playerSize: size)
                    .frame(height: max(0, (size.height - 68) / 2), alignment: .bottom)
            }
        }
    }
}

private extension CGSize {
    var verticalSpacing: CGFloat { height * 0.04 }
}

private extension PlayerControls {
    var palette: Palette.PlayerCard.Type {
        Palette.PlayerCard.self
    }

    var trackInfo: some View {
        HStack(alignment: .center, spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                let fade = ViewConst.playerCardPaddings
                let cfg = MarqueeText.Config(leftFade: fade, rightFade: fade)
                MarqueeText("未在播放", config: cfg)
                    .transformEffect(.identity)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(palette.opaque))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func volume(playerSize: CGSize) -> some View {
        VStack(spacing: playerSize.verticalSpacing) {
            VolumeSlider(isPressed: $isAdjustingVolume)
                .padding(.horizontal, 8)

            footer(width: playerSize.width)
                .padding(.top, playerSize.verticalSpacing)
                .padding(.horizontal, ViewConst.playerCardPaddings)
        }
    }

    func footer(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: width * 0.18) {
            Button {} label: {
                Image(systemName: "quote.bubble")
                    .font(.title2)
            }
            .disabled(true)
            .accessibilityLabel("歌词")
            PlayerRoutePicker()
                .frame(width: 44, height: 28)
            Button {} label: {
                Image(systemName: "list.bullet")
                    .font(.title2)
            }
            .disabled(true)
            .accessibilityLabel("待播清单")
        }
        .foregroundStyle(Color(palette.opaque))
        .blendMode(.overlay)
    }
}
