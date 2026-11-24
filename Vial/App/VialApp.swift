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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fullArtworkFrame = CGRect.zero
    @State private var miniArtworkFrame = CGRect.zero
    @State private var miniPlayerFrame = CGRect.zero
    private var miniArtwork = MiniPlayerArtworkSettings()

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
                    HStack(alignment: .center, spacing: 0) {
                        PlayerArtworkPlaceholder(
                            iconSize: CGFloat(miniArtwork.side) * 15 / 32,
                            cornerRadius: CGFloat(miniArtwork.side) * 7 / 32
                        )
                        .frame(width: CGFloat(miniArtwork.side), height: CGFloat(miniArtwork.side))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            miniArtworkFrame = $0
                        }
                        .opacity(hasArtworkFrames ? 0 : 1)
                        .accessibilityHidden(true)
                        .padding(.leading, CGFloat(miniArtwork.leading))
                        .padding(.trailing, CGFloat(miniArtwork.trailing))
                        Text("未在播放")
                            .font(.system(size: 14, weight: .medium))
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
            .padding(.trailing, 12)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                miniPlayerFrame = $0
            }
        }
        .allowsHitTesting(!showsPlayer)
        .accessibilityHidden(showsPlayer)
        .overlay {
            GeometryReader { viewport in
                let origin = viewport.frame(in: .global).origin
                let insets = viewport.safeAreaInsets
                let full = CGRect(
                    x: -insets.leading, y: -insets.top,
                    width: viewport.size.width + insets.leading + insets.trailing,
                    height: viewport.size.height + insets.top + insets.bottom
                )
                let compact = miniPlayerFrame.isEmpty
                    ? CGRect(x: 12, y: viewport.size.height - 50, width: max(1, viewport.size.width - 24), height: 44)
                    : miniPlayerFrame.offsetBy(dx: -origin.x, dy: -origin.y)
                let panel = showsPlayer || reduceMotion ? full : compact

                ZStack(alignment: .topLeading) {
                    VialPlayerView(drawsArtwork: !hasArtworkFrames, artworkFrame: $fullArtworkFrame) {
                        setPlayerPresented(false)
                    }
                    .coordinateSpace(name: "playerLayout")
                    .environment(\.colorScheme, .dark)
                    .mask(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: showsPlayer ? 0 : compact.height / 2)
                            .frame(width: panel.width, height: panel.height)
                            .offset(x: panel.minX, y: panel.minY)
                    }
                    .opacity(showsPlayer ? 1 : 0)
                    .allowsHitTesting(showsPlayer)
                    .accessibilityHidden(!showsPlayer)

                    if hasArtworkFrames {
                        let frame = showsPlayer
                            ? fullArtworkFrame
                            : miniArtworkFrame.offsetBy(dx: -origin.x, dy: -origin.y)
                        PlayerArtworkPlaceholder(
                            iconSize: showsPlayer ? min(72, frame.width * 0.35) : frame.width * 15 / 32,
                            cornerRadius: showsPlayer ? 20 : frame.width * 7 / 32
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .frame(width: viewport.size.width, height: viewport.size.height)
            }
        }
        .onChange(of: preferences.visibleTabs) { _, tabs in
            if !tabs.contains(selection) { selection = tabs.first ?? .search }
        }
    }

    private var hasArtworkFrames: Bool {
        !miniArtworkFrame.isEmpty && !fullArtworkFrame.isEmpty
    }

    private func setPlayerPresented(_ presented: Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.42)) {
            showsPlayer = presented
        }
    }
}

private struct MiniPlayerArtworkSettings: DynamicProperty {
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

private struct PlayerGrabberSettings: DynamicProperty {
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

private struct VialPlayerView: View {
    let drawsArtwork: Bool
    @Binding var artworkFrame: CGRect
    var dismiss: () -> Void
    @State private var isAdjustingVolume = false
    @GestureState private var isPressingProgress = false
    private var grabberSettings = PlayerGrabberSettings()

    var body: some View {
        GeometryReader { viewport in
            let isCompact = viewport.size.height < 560
            let spacing: CGFloat = isCompact ? 12 : 24
            VStack(spacing: 24) {
                GeometryReader { artwork in
                    let side = max(0, min(artwork.size.width, artwork.size.height))
                    PlayerArtworkPlaceholder(iconSize: min(72, side * 0.35), cornerRadius: 20)
                        .frame(width: side, height: side)
                        .opacity(drawsArtwork ? 1 : 0)
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .named("playerLayout"))
                        } action: { artworkFrame = $0 }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("歌曲封面")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(spacing: spacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未在播放")
                            .font(.title2.bold())
                        progressControls
                    }
                    transportControls
                    volumeControls
                        .modifier(PlayerControlPressEffect(isPressed: isAdjustingVolume))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, spacing)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background {
                LinearGradient(
                    stops: (0...24).map { index in
                        let position = Double(index) / 24
                        let gray = (107 - 43 * position * position) / 255
                        return Gradient.Stop(
                            color: Color(red: gray, green: gray, blue: gray),
                            location: CGFloat(position)
                        )
                    },
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .overlay(alignment: .top) { grabber }
        }
            .accessibilityAddTraits(.isModal)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 12).onEnded { value in
                    let movement = value.translation
                    if !isAdjustingVolume && movement.height > 35 && movement.height > abs(movement.width) {
                        dismiss()
                    }
                }
            )
    }

    private var progressControls: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(.white.opacity(0.25))
                .frame(height: 5)
                .frame(maxWidth: .infinity, minHeight: 32)
                .accessibilityLabel("播放进度不可用")
            HStack {
                Text("—:—").accessibilityLabel("已播放时长不可用")
                Spacer()
                Text("—:—").accessibilityLabel("剩余时长不可用")
            }
            .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .modifier(PlayerControlPressEffect(isPressed: isPressingProgress))
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressingProgress) { _, pressed, _ in
                    pressed = true
                }
        )
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
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "speaker.fill")
                .accessibilityHidden(true)
            PlayerSystemVolumeSlider(isPressed: $isAdjustingVolume)
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
                .fill(VialHeaderTint.color(grabberSettings.color).opacity(Double(grabberSettings.opacity) / 100))
                .frame(width: CGFloat(grabberSettings.length), height: CGFloat(grabberSettings.thickness))
                .frame(minWidth: 96, minHeight: 44, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("收起播放器")
        .padding(.top, CGFloat(grabberSettings.topGap))
    }
}

private struct PlayerControlPressEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 1.05 : 1)
            .brightness(isPressed ? 0.16 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isPressed)
    }
}

private struct PlayerArtworkPlaceholder: View, Animatable {
    var iconSize: CGFloat
    var cornerRadius: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(iconSize, cornerRadius) }
        set {
            iconSize = newValue.first
            cornerRadius = newValue.second
        }
    }

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
    private var miniArtwork = MiniPlayerArtworkSettings()
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
                DisclosureGroup("迷你播放器封面") {
                    Stepper("左边距 \(miniArtwork.leading) pt", value: miniArtwork.$leading, in: 0...32)
                    Stepper("右边距 \(miniArtwork.trailing) pt", value: miniArtwork.$trailing, in: 0...32)
                    Stepper("封面边长 \(miniArtwork.side) pt", value: miniArtwork.$side, in: 16...44)
                    Button("恢复默认值", systemImage: "arrow.counterclockwise") {
                        miniArtwork.reset()
                    }
                }
            }

            Section {
                DisclosureGroup("播放器白条") {
                    Stepper("距顶部安全区 \(grabberSettings.topGap) pt", value: grabberSettings.$topGap, in: 0...80)
                    Stepper("横向长度 \(grabberSettings.length) pt", value: grabberSettings.$length, in: 12...160)
                    Stepper("厚度 \(grabberSettings.thickness) pt", value: grabberSettings.$thickness, in: 1...16)
                    ColorPicker("颜色", selection: VialHeaderTint.binding(grabberSettings.$color), supportsOpacity: false)
                    Stepper("不透明度 \(grabberSettings.opacity)%", value: grabberSettings.$opacity, in: 0...100)
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
