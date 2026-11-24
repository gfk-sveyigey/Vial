import SwiftUI
import UIKit
import Observation

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
            Button {
                showsPlayer = true
            } label: {
                Label("未在播放", systemImage: "music.note")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开播放器")
        }
        .sheet(isPresented: $showsPlayer) {
            VialPlayerView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: preferences.visibleTabs) { _, tabs in
            if !tabs.contains(selection) { selection = tabs.first ?? .search }
        }
    }
}

private struct VialPlayerView: View {
    var body: some View {
        ContentUnavailableView("未在播放", systemImage: "music.note")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(
                    colors: [Color(red: 0.19, green: 0.20, blue: 0.27), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .preferredColorScheme(.dark)
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
                }
            }

            Section {
                DisclosureGroup("导航栏 Header") {
                    ForEach(VialHeaderSettings.Metric.allCases, id: \.rawValue) { metric in
                        control(for: metric)
                    }
                    ColorPicker("浅色毛玻璃色调", selection: VialHeaderTint.binding($lightTint), supportsOpacity: false)
                    ColorPicker("深色毛玻璃色调", selection: VialHeaderTint.binding($darkTint), supportsOpacity: false)
                    Button("恢复 Header 默认值", systemImage: "arrow.counterclockwise") {
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
