//
//  NowPlayingBackground.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 02.01.2025.
//

import SwiftUI

struct NowPlayingBackground: View {
    let colors: [Color]
    let expanded: Bool
    let isFullExpanded: Bool

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let expandPlayerCornerRadius: CGFloat = isFullExpanded ? 0 : 22
        return ZStack {
            Rectangle()
                .fill(.thickMaterial)
            if expanded {
                ColorfulBackground(colors: colors)
                    .overlay(Color(UIColor(white: 0.4, alpha: 0.5)))
                    .background(Color(white: 0.25))
                    .transition(.opacity)
            }
        }
        .clipShape(.rect(cornerRadius: expanded ? expandPlayerCornerRadius : 14))
        .shadow(
            color: .primary.opacity(colorScheme == .light ? 0.2 : 0),
            radius: 8,
            x: 0,
            y: 2
        )
    }
}
