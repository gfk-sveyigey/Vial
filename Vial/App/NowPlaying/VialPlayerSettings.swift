import SwiftUI

struct MiniPlayerArtworkSettings: DynamicProperty {
    private static let defaultLeading = 12
    private static let defaultTrailing = 8
    private static let defaultSide = 32

    @AppStorage("debug.miniPlayerArtwork.leading") var leading = MiniPlayerArtworkSettings.defaultLeading
    @AppStorage("debug.miniPlayerArtwork.trailing") var trailing = MiniPlayerArtworkSettings.defaultTrailing
    @AppStorage("debug.miniPlayerArtwork.side") var side = MiniPlayerArtworkSettings.defaultSide

    func reset() {
        leading = Self.defaultLeading
        trailing = Self.defaultTrailing
        side = Self.defaultSide
    }
}

struct PlayerGrabberSettings: DynamicProperty {
    private static let defaultTopGap = 7
    private static let defaultLength = 60
    private static let defaultThickness = 4
    private static let defaultColor = "#FFFFFF"

    @AppStorage("debug.playerGrabber.topGap") var topGap = PlayerGrabberSettings.defaultTopGap
    @AppStorage("debug.playerGrabber.length") var length = PlayerGrabberSettings.defaultLength
    @AppStorage("debug.playerGrabber.thickness") var thickness = PlayerGrabberSettings.defaultThickness
    @AppStorage("debug.playerGrabber.color") var color = PlayerGrabberSettings.defaultColor
    @AppStorage("debug.playerGrabber.opacity") var opacity = 85

    func reset() {
        topGap = Self.defaultTopGap
        length = Self.defaultLength
        thickness = Self.defaultThickness
        color = Self.defaultColor
        opacity = 85
    }
}

struct PlayerArtworkPlaceholder: View {
    let iconSize: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(uiColor: .systemGray4))
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
    }
}
