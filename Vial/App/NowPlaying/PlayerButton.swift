//
//  PlayerButton.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 18.12.2024.
//

import Combine
import SwiftUI

struct PlayerButton<Content: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.playerButtonConfig) var config
    @State private var showCircle = false
    @State private var pressed = false
    private let onPressed: (() -> Void)?
    private let onPressing: ((TimeInterval) -> Void)?
    private let onEnded: (() -> Void)?
    private let label: Content?

    init(
        label: (() -> Content)? = nil,
        onPressed: (() -> Void)? = nil,
        onPressing: ((TimeInterval) -> Void)? = nil,
        onEnded: (() -> Void)? = nil
    ) {
        self.label = label?()
        self.onPressed = onPressed
        self.onPressing = onPressing
        self.onEnded = onEnded
    }

    var body: some View {
        label
            .scaleEffect(pressed ? 0.9 : 1)
            .frame(width: config.size, height: config.size)
            .foregroundStyle(color)
            .background(showCircle ? config.tint : .clear)
            .clipShape(Ellipse())
            .scaleEffect(pressed ? 0.85 : 1)
            .onPressGesture(
                interval: config.updateUnterval,
                onPressed: {
                    guard isEnabled else { return }
                    withAnimation {
                        showCircle = true
                        pressed = true
                    }
                    onPressed?()
                },
                onPressing: { time in
                    guard isEnabled else { return }
                    onPressing?(time)
                },
                onEnded: {
                    guard isEnabled else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        withAnimation { showCircle = false }
                    }
                    withAnimation {
                        pressed = false
                    }
                    onEnded?()
                }
            )
            .contentTransition(.symbolEffect(.replace))
    }
}

private extension PlayerButton {
    var color: Color {
        isEnabled ? showCircle ? config.pressedColor : config.labelColor : config.disabledColor
    }
}

extension View {
    func playerButtonStyle(_ config: PlayerButtonConfig) -> some View {
        environment(\.playerButtonConfig, config)
    }
}

private struct PlayerButtonConfigEnvironmentKey: EnvironmentKey {
    static let defaultValue: PlayerButtonConfig = .init()
}

extension EnvironmentValues {
    var playerButtonConfig: PlayerButtonConfig {
        get { self[PlayerButtonConfigEnvironmentKey.self] }
        set { self[PlayerButtonConfigEnvironmentKey.self] = newValue }
    }
}

struct PlayerButtonConfig: Sendable {
    let updateUnterval: TimeInterval
    let size: CGFloat
    let labelColor: Color
    let tint: Color
    let pressedColor: Color
    let disabledColor: Color

    init(
        updateUnterval: TimeInterval = 0.1,
        size: CGFloat = 68,
        labelColor: Color = .init(UIColor.label),
        tint: Color = .accentColor,
        pressedColor: Color = .init(UIColor.secondaryLabel),
        disabledColor: Color = .init(UIColor.secondaryLabel)
    ) {
        self.updateUnterval = updateUnterval
        self.size = size
        self.labelColor = labelColor
        self.tint = tint
        self.pressedColor = pressedColor
        self.disabledColor = disabledColor
    }
}

extension PlayerButton where Content == EmptyView {
    init(
        onPressed: (() -> Void)? = nil,
        onPressing: ((TimeInterval) -> Void)? = nil,
        onEnded: (() -> Void)? = nil
    ) {
        label = nil
        self.onPressed = onPressed
        self.onPressing = onPressing
        self.onEnded = onEnded
    }
}
