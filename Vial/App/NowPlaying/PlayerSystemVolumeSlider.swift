import SwiftUI
import MediaPlayer

struct PlayerSystemVolumeSlider: UIViewRepresentable {
    @Binding var isPressed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPressed: $isPressed)
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = .white
        let transparentThumb = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
            .image { _ in }
        view.setVolumeThumbImage(transparentThumb, for: .normal)
        view.setVolumeThumbImage(transparentThumb, for: .highlighted)

        if let slider = view.subviews.compactMap({ $0 as? UISlider }).first {
            slider.minimumTrackTintColor = UIColor(white: 0.78, alpha: 1)
            slider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.25)
            let touch = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.adjustVolume(_:)))
            touch.minimumPressDuration = 0
            slider.addGestureRecognizer(touch)
        }
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}

    final class Coordinator: NSObject {
        @Binding var isPressed: Bool

        init(isPressed: Binding<Bool>) {
            _isPressed = isPressed
        }

        @objc func adjustVolume(_ gesture: UILongPressGestureRecognizer) {
            guard let slider = gesture.view as? UISlider else { return }
            switch gesture.state {
            case .began, .changed:
                isPressed = true
                let track = slider.trackRect(forBounds: slider.bounds)
                guard track.width > 0 else { return }
                let fraction = min(1, max(0, (gesture.location(in: slider).x - track.minX) / track.width))
                let position = slider.effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 - fraction : fraction
                slider.value = slider.minimumValue + Float(position) * (slider.maximumValue - slider.minimumValue)
                slider.sendActions(for: .valueChanged)
            case .ended, .cancelled, .failed:
                isPressed = false
            default:
                break
            }
        }
    }
}
