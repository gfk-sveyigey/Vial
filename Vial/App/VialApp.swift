import SwiftUI
import UIKit
import Observation
import MediaPlayer

@main
struct VialApp: App {
    var body: some Scene {
        WindowGroup {
            VialNavigationView()
                .tint(Color.accentColor)
        }
    }
}

private enum VialTab: String, CaseIterable, Hashable, Identifiable {
    case home
    case discover
    case radio
    case library
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "主页"
        case .discover: "新发现"
        case .radio: "广播"
        case .library: "资料库"
        case .search: "搜索"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .discover: "square.grid.2x2"
        case .radio: "dot.radiowaves.left.and.right"
        case .library: "music.note.square.stack"
        case .search: "magnifyingglass"
        }
    }

    var visibilityKey: String? {
        switch self {
        case .home: "navigation_visible_home"
        case .discover: "navigation_visible_discover"
        case .radio: "navigation_visible_radio"
        case .library: "navigation_visible_library"
        case .search: nil
        }
    }
}

@MainActor
@Observable
private final class VialNavigationPreferences {
    private(set) var tabBarCanMinimize: Bool
    private(set) var visibleTabs: [VialTab]
    private(set) var searchIsIndependent: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var defaultsObserver: UserDefaultsKeyObserver?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyKeys(defaults: defaults)
        tabBarCanMinimize = Self.bool("navigation_tabBarCanMinimize", fallback: true, defaults: defaults)
        visibleTabs = Self.readVisibleTabs(defaults: defaults)
        searchIsIndependent = Self.bool("navigation_searchIsIndependent", fallback: false, defaults: defaults)
        defaultsObserver = nil
        defaultsObserver = UserDefaultsKeyObserver(defaults: defaults, keys: Self.observedKeys) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshIfNeeded()
            }
        }
    }

    // Settings.app changes these defaults out of process; reconcile on activation without publishing unchanged values.
    func refreshIfNeeded() {
        let newTabBarCanMinimize = Self.bool("navigation_tabBarCanMinimize", fallback: true, defaults: defaults)
        let newVisibleTabs = Self.readVisibleTabs(defaults: defaults)
        let newSearchIsIndependent = Self.bool("navigation_searchIsIndependent", fallback: false, defaults: defaults)

        if tabBarCanMinimize != newTabBarCanMinimize {
            tabBarCanMinimize = newTabBarCanMinimize
        }
        if visibleTabs != newVisibleTabs {
            visibleTabs = newVisibleTabs
        }
        if searchIsIndependent != newSearchIsIndependent {
            searchIsIndependent = newSearchIsIndependent
        }
    }

    private static let observedKeys = [
        "navigation_tabBarCanMinimize",
        "navigation_visible_home",
        "navigation_visible_discover",
        "navigation_visible_radio",
        "navigation_visible_library",
        "navigation_searchIsIndependent"
    ]

    private static let legacyKeyMappings = [
        "navigation.tabBarCanMinimize": "navigation_tabBarCanMinimize",
        "navigation.visible.home": "navigation_visible_home",
        "navigation.visible.discover": "navigation_visible_discover",
        "navigation.visible.radio": "navigation_visible_radio",
        "navigation.visible.library": "navigation_visible_library",
        "navigation.searchIsIndependent": "navigation_searchIsIndependent"
    ]

    private static func migrateLegacyKeys(defaults: UserDefaults) {
        let domainName = Bundle.main.bundleIdentifier ?? "com.aholic.vial"
        let storedValues = defaults.persistentDomain(forName: domainName) ?? [:]
        for (oldKey, newKey) in legacyKeyMappings {
            if let value = storedValues[oldKey], storedValues[newKey] == nil {
                defaults.set(value, forKey: newKey)
            }
            defaults.removeObject(forKey: oldKey)
        }
    }

    private static func readVisibleTabs(defaults: UserDefaults) -> [VialTab] {
        VialTab.allCases.filter { tab in
            guard let key = tab.visibilityKey else { return true }
            return bool(key, fallback: true, defaults: defaults)
        }
    }

    private static func bool(_ key: String, fallback: Bool, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}

private final class UserDefaultsKeyObserver: NSObject, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keys: [String]
    private let onChange: @Sendable () -> Void

    init(defaults: UserDefaults, keys: [String], onChange: @escaping @Sendable () -> Void) {
        self.defaults = defaults
        self.keys = keys
        self.onChange = onChange
        super.init()
        keys.forEach { defaults.addObserver(self, forKeyPath: $0, options: [.new], context: nil) }
    }

    deinit {
        keys.forEach { defaults.removeObserver(self, forKeyPath: $0) }
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let keyPath, keys.contains(keyPath) else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        onChange()
    }
}

struct VialNavigationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var preferences: VialNavigationPreferences
    @State private var selection: VialTab

    init() {
        let preferences = VialNavigationPreferences()
        _preferences = State(initialValue: preferences)
        _selection = State(initialValue: preferences.visibleTabs.first ?? .search)
    }

    var body: some View {
        VialNavigationShell(preferences: preferences, selection: $selection)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                preferences.refreshIfNeeded()
            }
    }
}

private struct VialNavigationShell: View {
    let preferences: VialNavigationPreferences
    @Binding var selection: VialTab

    var body: some View {
        VialTabsView(preferences: preferences, selection: $selection)
            .tabBarMinimizeBehavior(preferences.tabBarCanMinimize ? .onScrollDown : .never)
    }
}

private struct VialTabsView: View {
    let preferences: VialNavigationPreferences
    @Binding var selection: VialTab
    @State private var showsPlayer = false
    @Namespace private var playerTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $selection) {
            ForEach(preferences.visibleTabs.filter { $0 != .search }) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    NavigationStack { VialRootPage(tab: tab) }
                }
            }
            if preferences.searchIsIndependent {
                Tab("搜索", systemImage: "magnifyingglass", value: VialTab.search, role: .search) {
                    NavigationStack { VialRootPage(tab: .search) }
                }
            } else {
                Tab("搜索", systemImage: "magnifyingglass", value: VialTab.search) {
                    NavigationStack { VialRootPage(tab: .search) }
                }
            }
        }
        .tabViewBottomAccessory {
            HStack(spacing: 8) {
                Button {
                    setPlayerPresented(true)
                } label: {
                    HStack(spacing: 8) {
                        Color.clear
                            .frame(width: 32, height: 32)
                            .overlay {
                                if !showsPlayer {
                                    PlayerArtworkPlaceholder(iconSize: 15, cornerRadius: 7)
                                        .matchedGeometryEffect(id: "playerArtwork", in: playerTransition)
                                        .transition(.identity)
                                }
                            }
                            .accessibilityHidden(true)
                        Text("未在播放")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityHint("打开全屏播放器")

                Button("播放", systemImage: "play.fill") {}
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(true)
                Button("下一首", systemImage: "forward.fill") {}
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(true)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        }
        .allowsHitTesting(!showsPlayer)
        .accessibilityHidden(showsPlayer)
        .overlay {
            if showsPlayer {
                VialPlayerView(artworkTransition: playerTransition) {
                    setPlayerPresented(false)
                }
                .transition(.opacity)
            }
        }
        .onChange(of: preferences.visibleTabs) { _, tabs in
            if !tabs.contains(selection) { selection = tabs.first ?? .search }
        }
    }

    private func setPlayerPresented(_ presented: Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.42)) {
            showsPlayer = presented
        }
    }
}

private struct PlayerGrabberSettings: DynamicProperty {
    private static let defaultTopGap = 7
    private static let defaultLength = 60
    private static let defaultThickness = 4
    private static let defaultColor = "#FFFFFF"

    @AppStorage("debug.playerGrabber.topGap") var topGap = PlayerGrabberSettings.defaultTopGap
    @AppStorage("debug.playerGrabber.length") var length = PlayerGrabberSettings.defaultLength
    @AppStorage("debug.playerGrabber.thickness") var thickness = PlayerGrabberSettings.defaultThickness
    @AppStorage("debug.playerGrabber.color") var color = PlayerGrabberSettings.defaultColor
    @AppStorage("debug.playerGrabber.blur") var blur = 0
    @AppStorage("debug.playerGrabber.glass") var glass = 0

    func reset() {
        topGap = Self.defaultTopGap
        length = Self.defaultLength
        thickness = Self.defaultThickness
        color = Self.defaultColor
        blur = 0
        glass = 0
    }
}

private struct VialPlayerView: View {
    let artworkTransition: Namespace.ID
    var dismiss: () -> Void
    private var grabberSettings = PlayerGrabberSettings()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                PlayerArtworkPlaceholder(iconSize: 72, cornerRadius: 20)
                    .matchedGeometryEffect(id: "playerArtwork", in: artworkTransition)
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityLabel("歌曲封面")

                VStack(alignment: .leading, spacing: 4) {
                    Text("未在播放")
                        .font(.title2.bold())
                    progressControls
                        .modifier(PlayerControlPressEffect())
                }
                transportControls
                volumeControls
                    .modifier(PlayerControlPressEffect())
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: [VialHeaderTint.color("#6B6B6B"), VialHeaderTint.color("#404040")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .overlay(alignment: .top) {
                grabber
            }
            .environment(\.colorScheme, .dark)
            .accessibilityAddTraits(.isModal)
    }

    private var progressControls: some View {
        VStack(spacing: 4) {
            Slider(value: .constant(0.0), in: 0...1) {
                Text("播放进度")
            }
            HStack {
                Text("—:—").accessibilityLabel("已播放时长不可用")
                Spacer()
                Text("—:—").accessibilityLabel("剩余时长不可用")
            }
            .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .disabled(true)
    }

    private var transportControls: some View {
        HStack(spacing: 24) {
            Button("上一首", systemImage: "backward.fill") {}
                .font(.system(size: 28))
            Button("播放", systemImage: "play.fill") {}
                .font(.system(size: 44))
            Button("下一首", systemImage: "forward.fill") {}
                .font(.system(size: 28))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .disabled(true)
    }

    private var volumeControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .accessibilityHidden(true)
            PlayerSystemVolumeSlider()
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            Image(systemName: "speaker.wave.3.fill")
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var grabber: some View {
        Button {
            dismiss()
        } label: {
            Capsule()
                .fill(VialHeaderTint.color(grabberSettings.color).opacity(0.85))
                .blur(radius: CGFloat(grabberSettings.blur))
                .background {
                    if grabberSettings.glass > 0 {
                        VialBackdropBlur(style: .systemMaterial, strength: Double(grabberSettings.glass) / 100)
                            .clipShape(Capsule())
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: CGFloat(grabberSettings.length), height: CGFloat(grabberSettings.thickness))
                .frame(minWidth: 96, minHeight: 44, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收起播放器")
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height > 35 &&
                    value.translation.height > abs(value.translation.width) {
                    dismiss()
                }
            }
        )
        .padding(.top, CGFloat(grabberSettings.topGap))
    }
}

private struct PlayerControlPressEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 1.05 : 1)
            .animation(.easeInOut(duration: 0.18), value: isPressed)
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($isPressed) { value, pressed, _ in
                        if case .second(true, _) = value {
                            pressed = true
                        }
                    }
            )
    }
}

private struct PlayerArtworkPlaceholder: View {
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

private struct PlayerSystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

private struct VialRootPage: View {
    let tab: VialTab

    @State private var isShowingDebugSheet = false
    @State private var searchQuery = ""

    var body: some View {
        VialHeaderScrollView(title: tab.title) {
            pageContent
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingDebugSheet) {
            NavigationStack {
                VialDebugSettingsView()
                    .navigationTitle("调试功能")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { isShowingDebugSheet = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch tab {
        case .home, .discover, .radio:
            EmptyView()
        case .library:
            VialActionRow("调试功能", systemImage: "ladybug") {
                isShowingDebugSheet = true
            }
        case .search:
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索内容或频道", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct VialActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct VialDebugSettingsView: View {
    private var grabberSettings = PlayerGrabberSettings()
    @ObservedObject private var layout = VialHeaderSettings.shared
    @ObservedObject private var accountRow = VialAccountRowSettings.shared
    @AppStorage("debug.header.lightTint") private var lightTint = "#FFFFFF"
    @AppStorage("debug.header.darkTint") private var darkTint = "#000000"

    var body: some View {
        Form {
            Section {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label("系统设置", systemImage: "gearshape")
                }
            }

            Section {
                DisclosureGroup("播放器白条") {
                    Stepper("距顶部安全区 \(grabberSettings.topGap) pt", value: grabberSettings.$topGap, in: 0...80)
                    Stepper("横向长度 \(grabberSettings.length) pt", value: grabberSettings.$length, in: 12...160)
                    Stepper("厚度 \(grabberSettings.thickness) pt", value: grabberSettings.$thickness, in: 1...16)
                    ColorPicker("颜色", selection: VialHeaderTint.binding(grabberSettings.$color), supportsOpacity: false)
                    Stepper("白条模糊强度 \(grabberSettings.blur) pt", value: grabberSettings.$blur, in: 0...16)
                    Stepper("背景毛玻璃强度 \(grabberSettings.glass)%", value: grabberSettings.$glass, in: 0...100, step: 5)
                    Button("恢复默认值", systemImage: "arrow.counterclockwise") {
                        grabberSettings.reset()
                    }
                }
            }

            Section {
                DisclosureGroup("账号信息行") {
                    ForEach(VialAccountRowSettings.Metric.allCases, id: \.rawValue) { metric in
                        let configuration = metric.configuration
                        Stepper(
                            value: Binding(get: { accountRow[metric] }, set: { accountRow[metric] = $0 }),
                            in: configuration.range
                        ) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(configuration.label)
                                Text("\(accountRow[metric]) pt")
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("恢复默认值", systemImage: "arrow.counterclockwise") {
                        accountRow.reset()
                    }
                }
            }

            Section {
                DisclosureGroup("导航栏 Header") {
                    ForEach(VialHeaderSettings.Metric.allCases, id: \.rawValue) { metric in
                        control(for: metric)
                    }
                    ColorPicker("浅色毛玻璃色调", selection: VialHeaderTint.binding($lightTint), supportsOpacity: false)
                    ColorPicker("深色毛玻璃色调", selection: VialHeaderTint.binding($darkTint), supportsOpacity: false)
                    Button("恢复默认值", systemImage: "arrow.counterclockwise") {
                        layout.reset()
                        lightTint = "#FFFFFF"
                        darkTint = "#000000"
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func control(for metric: VialHeaderSettings.Metric) -> some View {
        let value = Binding(get: { layout[metric] }, set: { layout[metric] = $0 })
        switch metric {
        case .mediaSnapConflict:
            Picker(metric.label, selection: value) {
                Text("根据滚动方向").tag(0)
                Text("根据距离").tag(1)
            }
        case .mediaContentOpacityCurve, .mediaContentBlurCurve, .mediaSnapCurve, .mediaEdgeHeightCurve, .mediaEdgeCurve:
            Picker(metric.label, selection: value) {
                Text("线性").tag(0)
                Text("缓入缓出").tag(1)
                Text("缓入").tag(2)
                Text("缓出").tag(3)
                Text("平滑阶梯").tag(4)
            }
        default:
            Stepper(value: value, in: metric.range) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.label)
                    metricValue(metric)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metricValue(_ metric: VialHeaderSettings.Metric) -> Text {
        switch metric {
        case .mediaGlassBorderWidth:
            Text("\(layout.mediaGlassBorderWidth, format: .number.precision(.fractionLength(2))) pt")
        case .mediaSnapDuration:
            Text("\(layout[metric]) ms")
        case .mediaGlassStrength, .mediaGlassTint, .mediaGlassBorderOpacity, .mediaSnapThreshold,
             .mediaSnapCollapsedThreshold, .mediaEdgeTopStrength, .mediaEdgeTopMaxStrength,
             .mediaEdgeBottomStrength, .mediaEdgeTint:
            Text(Double(layout[metric]) / 100, format: .percent)
        default:
            Text("\(layout[metric]) pt")
        }
    }
}
