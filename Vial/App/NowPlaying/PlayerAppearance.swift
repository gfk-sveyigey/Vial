import SwiftUI

enum ViewConst {
    static let compactNowPlayingHeight: CGFloat = 52
    static let playerCardPaddings: CGFloat = 25
}

enum Palette {
    enum PlayerCard {
        static let opaque: UIColor = .white
        static let translucent = UIColor(white: 0.784, alpha: 0.816)
    }
}

func lerp<V: BinaryFloatingPoint, T: BinaryFloatingPoint>(_ start: V, _ end: V, _ progress: T) -> V {
    start + (end - start) * V(progress)
}
