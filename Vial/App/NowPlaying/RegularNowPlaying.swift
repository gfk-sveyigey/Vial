//
//  RegularNowPlaying.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 20.11.2024.
//

import SwiftUI

struct RegularNowPlaying: View {
    private var settings = PlayerGrabberSettings()
    var size: CGSize
    var safeArea: EdgeInsets
    var animationNamespace: Namespace.ID
    @Binding var isAdjustingVolume: Bool
    let close: () -> Void

    init(
        size: CGSize,
        safeArea: EdgeInsets,
        animationNamespace: Namespace.ID,
        isAdjustingVolume: Binding<Bool>,
        close: @escaping () -> Void
    ) {
        self.size = size
        self.safeArea = safeArea
        self.animationNamespace = animationNamespace
        _isAdjustingVolume = isAdjustingVolume
        self.close = close
    }

    var body: some View {
        let verticalPadding: CGFloat = size.height < 700 ? 10 : 30
        let artworkSide = max(0, min(
            size.width - 50,
            size.height - safeArea.top - safeArea.bottom - 300 - verticalPadding * 2,
            490
        ))

        VStack(spacing: 12) {
            artwork
                .frame(width: artworkSide, height: artworkSide)
                .padding(.vertical, verticalPadding)

            PlayerControls(isAdjustingVolume: $isAdjustingVolume)
                .transition(.move(edge: .bottom))
        }
        .padding(.top, safeArea.top + 24)
        .padding(.bottom, safeArea.bottom + 8)
        .padding(.horizontal, max(safeArea.leading, safeArea.trailing))
        .frame(maxWidth: 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            grip.padding(.top, safeArea.top + CGFloat(settings.topGap))
        }
    }

    private var grip: some View {
        Button(action: close) {
            Capsule()
                .fill(VialHeaderTint.color(settings.color).opacity(Double(settings.opacity) / 100))
                .frame(width: CGFloat(settings.length), height: CGFloat(settings.thickness))
                .frame(minWidth: 96, minHeight: 44, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收起播放器")
    }

    private var artwork: some View {
        GeometryReader { geometry in
            let side = max(0, min(geometry.size.width, geometry.size.height))
            let inset = min(48, side * 0.18)
            PlayerArtworkPlaceholder(iconSize: min(72, side * 0.26), cornerRadius: 10)
                .matchedGeometryEffect(id: PlayerMatchedGeometry.artwork, in: animationNamespace)
                .frame(width: side - inset * 2, height: side - inset * 2)
                .shadow(color: .black.opacity(0.13), radius: 3, y: 3)
                .frame(width: side, height: side)
                .accessibilityLabel("歌曲封面")
        }
    }
}
