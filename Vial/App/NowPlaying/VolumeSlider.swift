//
//  VolumeSlider.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 24.12.2024.
//

import AVKit
import SwiftUI

struct VolumeSlider: View {
    @Binding var isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "speaker.fill")
                .accessibilityHidden(true)
            PlayerSystemVolumeSlider(isPressed: $isPressed)
                .frame(height: 32)
            Image(systemName: "speaker.wave.3.fill")
                .accessibilityHidden(true)
        }
        .font(.system(size: 14))
        .padding(.horizontal, ViewConst.playerCardPaddings - 8)
        .frame(height: 50)
        .scaleEffect(isPressed && !reduceMotion ? 1.05 : 1)
        .brightness(isPressed ? 0.16 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isPressed)
    }
}

struct PlayerRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
