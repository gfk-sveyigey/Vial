//
//  TimingIndicator.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 13.12.2024.
//

import SwiftUI

struct TimingIndicator: View {
    var body: some View {
        ElasticSlider(
            value: .constant(0.0),
            in: 0...1,
            leadingLabel: {
                label("—:—").accessibilityLabel("已播放时长不可用")
            },
            trailingLabel: {
                label("—:—").accessibilityLabel("剩余时长不可用")
            }
        )
        .sliderStyle(.playbackProgress)
        .frame(height: 46)
        .disabled(true)
        .allowsHitTesting(false)
        .transformEffect(.identity)
    }
}

private extension TimingIndicator {
    func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .padding(.top, 11)
    }

}

extension ElasticSliderConfig {
    static var playbackProgress: Self {
        Self(
            labelLocation: .bottom,
            maxStretch: 0,
            minimumTrackActiveColor: Color(Palette.PlayerCard.opaque),
            minimumTrackInactiveColor: Color(Palette.PlayerCard.translucent),
            maximumTrackColor: Color(Palette.PlayerCard.translucent),
            blendMode: .overlay,
            syncLabelsStyle: true
        )
    }
}
