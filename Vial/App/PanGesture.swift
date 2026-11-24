//
//  PanGesture.swift
//  AppleMusicStylePlayer
//
//  Created by Alexey Vorobyov on 17.11.2024.
//

import SwiftUI
import UIKit

struct PanGesture: UIGestureRecognizerRepresentable {
    var onChange: (Value) -> Void
    var onEnd: (Value) -> Void
    var onCancel: () -> Void = {}
    var isEnabled = true

    func makeUIGestureRecognizer(context _: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.isEnabled = isEnabled
        return gesture
    }

    func updateUIGestureRecognizer(_ gesture: UIPanGestureRecognizer, context _: Context) {
        gesture.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        let state = recognizer.state
        let translation = recognizer.translation(in: recognizer.view?.window).toSize()
        let velocity = recognizer.velocity(in: recognizer.view?.window).toSize()
        let value = Value(translation: translation, velocity: velocity)

        if state == .began || state == .changed {
            onChange(value)
        } else if state == .ended {
            onEnd(value)
        } else if state == .cancelled || state == .failed {
            onCancel()
        }
    }

    struct Value {
        var translation: CGSize
        var velocity: CGSize
    }
}

extension CGPoint {
    func toSize() -> CGSize {
        CGSize(width: x, height: y)
    }
}
