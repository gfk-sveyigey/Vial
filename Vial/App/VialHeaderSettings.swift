import SwiftUI
import Combine
import UIKit

@MainActor
final class VialHeaderSettings: ObservableObject {
    static let shared = VialHeaderSettings()
    private static let storageKey = "debug.immersiveHeader"
    @Published private var values = UserDefaults.standard.dictionary(forKey: VialHeaderSettings.storageKey) as? [String: Int] ?? [:]

    enum Metric: String, CaseIterable {
        case mediaHeaderHeight
        case mediaGlassStrength
        case mediaGlassTint
        case mediaContentBlur
        case mediaGlassBorderWidth
        case mediaGlassBorderBlur
        case mediaGlassBorderOpacity
        case mediaContentOpacityCurve
        case mediaContentBlurCurve
        case mediaSnapThreshold
        case mediaSnapCollapsedThreshold
        case mediaSnapConflict
        case mediaSnapDuration
        case mediaSnapCurve
        case mediaEdgeTopStrength
        case mediaEdgeTopMaxStrength
        case mediaEdgeHeightCurve
        case mediaEdgeBottomStrength
        case mediaEdgeTint
        case mediaEdgeCurve

        var label: String {
            switch self {
            case .mediaHeaderHeight: "固定内容高度"
            case .mediaGlassStrength: "下层毛玻璃强度"
            case .mediaGlassTint: "毛玻璃颜色叠加强度"
            case .mediaContentBlur: "标题最大模糊"
            case .mediaGlassBorderWidth: "毛玻璃底边框宽度"
            case .mediaGlassBorderBlur: "毛玻璃底边框模糊"
            case .mediaGlassBorderOpacity: "毛玻璃底边框不透明度"
            case .mediaContentOpacityCurve: "标题透明度曲线"
            case .mediaContentBlurCurve: "标题模糊曲线"
            case .mediaSnapThreshold: "展开吸附阈值"
            case .mediaSnapCollapsedThreshold: "收起吸附阈值"
            case .mediaSnapConflict: "吸附冲突处理"
            case .mediaSnapDuration: "吸附动画时长"
            case .mediaSnapCurve: "吸附动画曲线"
            case .mediaEdgeTopStrength: "顶部模糊最小强度"
            case .mediaEdgeTopMaxStrength: "顶部模糊最大强度"
            case .mediaEdgeHeightCurve: "顶部模糊高度曲线"
            case .mediaEdgeBottomStrength: "模糊底端强度"
            case .mediaEdgeTint: "顶部模糊颜色叠加强度"
            case .mediaEdgeCurve: "顶部模糊渐变曲线"
            }
        }

        var defaultValue: Int {
            switch self {
            case .mediaHeaderHeight: 54
            case .mediaGlassStrength: 5
            case .mediaGlassTint: 50
            case .mediaContentBlur: 3
            case .mediaGlassBorderWidth: 10
            case .mediaGlassBorderBlur: 0
            case .mediaGlassBorderOpacity: 15
            case .mediaContentOpacityCurve: 2
            case .mediaContentBlurCurve: 2
            case .mediaSnapThreshold: 70
            case .mediaSnapCollapsedThreshold: 70
            case .mediaSnapConflict: 0
            case .mediaSnapDuration: 300
            case .mediaSnapCurve: 3
            case .mediaEdgeTopStrength: 5
            case .mediaEdgeTopMaxStrength: 70
            case .mediaEdgeHeightCurve: 3
            case .mediaEdgeBottomStrength: 0
            case .mediaEdgeTint: 50
            case .mediaEdgeCurve: 1
            }
        }

        var range: ClosedRange<Int> {
            switch self {
            case .mediaHeaderHeight: 30...120
            case .mediaGlassStrength: 0...100
            case .mediaGlassTint: 0...100
            case .mediaContentBlur: 0...40
            case .mediaGlassBorderWidth: 0...40
            case .mediaGlassBorderBlur: 0...10
            case .mediaGlassBorderOpacity: 0...100
            case .mediaContentOpacityCurve: 0...4
            case .mediaContentBlurCurve: 0...4
            case .mediaSnapThreshold: 5...95
            case .mediaSnapCollapsedThreshold: 5...95
            case .mediaSnapConflict: 0...1
            case .mediaSnapDuration: 100...1000
            case .mediaSnapCurve: 0...4
            case .mediaEdgeTopStrength: 0...100
            case .mediaEdgeTopMaxStrength: 0...100
            case .mediaEdgeHeightCurve: 0...4
            case .mediaEdgeBottomStrength: 0...100
            case .mediaEdgeTint: 0...100
            case .mediaEdgeCurve: 0...4
            }
        }
    }

    subscript(_ metric: Metric) -> Int {
        get { min(metric.range.upperBound, max(metric.range.lowerBound, values[metric.rawValue] ?? metric.defaultValue)) }
        set {
            let value = min(metric.range.upperBound, max(metric.range.lowerBound, newValue))
            guard self[metric] != value else { return }
            values[metric.rawValue] = value
            UserDefaults.standard.set(values, forKey: Self.storageKey)
        }
    }

    var mediaGlassBorderWidth: CGFloat { CGFloat(self[.mediaGlassBorderWidth]) / 20 }

    func reset() {
        values = [:]
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}

@MainActor
final class VialAccountRowSettings: ObservableObject {
    static let shared = VialAccountRowSettings()
    private static let storageKey = "debug.accountRow"
    @Published private var values = UserDefaults.standard.dictionary(forKey: VialAccountRowSettings.storageKey) as? [String: Int] ?? [:]

    enum Metric: String, CaseIterable {
        case avatarSize, top, bottom, leading, trailing, height, usernameSize, detailSize
        case outerTop, outerBottom, outerLeading, outerTrailing

        var configuration: (label: String, initial: Int, range: ClosedRange<Int>) {
            switch self {
            case .avatarSize: ("头像大小", 52, 16...120)
            case .top: ("上内边距", 0, 0...48)
            case .bottom: ("下内边距", 0, 0...48)
            case .leading: ("左内边距", 20, 0...48)
            case .trailing: ("右内边距", 20, 0...48)
            case .height: ("最小行高", 52, 24...220)
            case .usernameSize: ("用户名字号", 17, 10...42)
            case .detailSize: ("第二行字号", 15, 10...42)
            case .outerTop: ("上外边距", 12, 0...48)
            case .outerBottom: ("下外边距", 0, 0...48)
            case .outerLeading: ("左外边距", 16, 0...48)
            case .outerTrailing: ("右外边距", 16, 0...48)
            }
        }
    }

    subscript(_ metric: Metric) -> Int {
        get {
            let configuration = metric.configuration
            let value = values[metric.rawValue] ?? configuration.initial
            return min(configuration.range.upperBound, max(configuration.range.lowerBound, value))
        }
        set {
            guard metric.configuration.range.contains(newValue), self[metric] != newValue else { return }
            values[metric.rawValue] = newValue
            UserDefaults.standard.set(values, forKey: Self.storageKey)
        }
    }
}

extension VialAccountRowSettings {
    func reset() {
        values = [:]
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}

enum VialHeaderTint {
    static func color(_ hex: String) -> Color {
        guard hex.count == 7, hex.hasPrefix("#"), let rgb = UInt32(hex.dropFirst(), radix: 16) else {
            return Color(uiColor: .systemBackground)
        }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }

    static func binding(_ hex: Binding<String>) -> Binding<Color> {
        Binding {
            color(hex.wrappedValue)
        } set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            func byte(_ component: CGFloat) -> Int { Int((min(1, max(0, component)) * 255).rounded()) }
            hex.wrappedValue = String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        }
    }
}
