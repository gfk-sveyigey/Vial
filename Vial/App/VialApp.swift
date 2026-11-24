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
        case .discover: "sparkles"
        case .radio: "dot.radiowaves.left.and.right"
        case .library: "square.stack"
        case .search: "magnifyingglass"
        }
    }

    var subtitle: String {
        switch self {
        case .home: "为你整理的内容"
        case .discover: "看看最近有什么新内容"
        case .radio: "正在播出的频道"
        case .library: "收藏与最近访问"
        case .search: "搜索内容与频道"
        }
    }

    var visibilityKey: String? {
        switch self {
        case .home: "navigation.visible.home"
        case .discover: "navigation.visible.discover"
        case .radio: "navigation.visible.radio"
        case .library: "navigation.visible.library"
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

    init(defaults: UserDefaults = .standard) {
        tabBarCanMinimize = Self.bool("navigation.tabBarCanMinimize", fallback: true, defaults: defaults)
        visibleTabs = Self.readVisibleTabs(defaults: defaults)
        searchIsIndependent = Self.bool("navigation.searchIsIndependent", fallback: false, defaults: defaults)
    }

    // Settings.app changes these defaults out of process; reconcile on activation without publishing unchanged values.
    func refreshIfNeeded(defaults: UserDefaults = .standard) {
        let newTabBarCanMinimize = Self.bool("navigation.tabBarCanMinimize", fallback: true, defaults: defaults)
        let newVisibleTabs = Self.readVisibleTabs(defaults: defaults)
        let newSearchIsIndependent = Self.bool("navigation.searchIsIndependent", fallback: false, defaults: defaults)

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

    var body: some View {
        TabView(selection: $selection) {
            ForEach(preferences.visibleTabs) { tab in
                if tab == .search, preferences.searchIsIndependent {
                    Tab(tab.title, systemImage: tab.symbol, value: tab, role: .search) {
                        NavigationStack { VialRootPage(tab: tab) }
                    }
                } else {
                    Tab(tab.title, systemImage: tab.symbol, value: tab) {
                        NavigationStack { VialRootPage(tab: tab) }
                    }
                }
            }
        }
        .onChange(of: preferences.visibleTabs) { _, tabs in
            if !tabs.contains(selection) { selection = tabs.first ?? .search }
        }
    }
}

private struct VialRootPage: View {
    let tab: VialTab

    @AppStorage("debug.header.expandedHeight") private var headerExpandedHeight = 126
    @AppStorage("debug.header.collapsedHeight") private var headerCollapsedHeight = 68
    @AppStorage("debug.header.collapseDistance") private var headerCollapseDistance = 64
    @State private var scrollOffset: CGFloat = 0
    @State private var isShowingDebugSheet = false
    @State private var searchQuery = ""

    private var collapseProgress: CGFloat {
        return min(1, max(0, -scrollOffset / CGFloat(max(headerCollapseDistance, 1))))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: VialScrollOffsetKey.self,
                            value: proxy.frame(in: .named("vial.scroll")).minY
                        )
                    }
                    .frame(height: 0)

                    pageContent
                        .padding(.top, CGFloat(headerExpandedHeight))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
            .coordinateSpace(name: "vial.scroll")
            .scrollIndicators(.hidden)
            .onPreferenceChange(VialScrollOffsetKey.self) { scrollOffset = $0 }

            VialRootHeader(
                title: tab.title,
                subtitle: tab.subtitle,
                collapseProgress: collapseProgress,
                expandedHeight: CGFloat(headerExpandedHeight),
                collapsedHeight: CGFloat(headerCollapsedHeight)
            )
        }
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
        case .home:
            VStack(alignment: .leading, spacing: 20) {
                Text("继续探索")
                    .font(.title2.weight(.semibold))
                ContentPlaceholder(symbol: "play.rectangle", title: "还没有最近内容", detail: "你访问的内容会显示在这里。")
                Text("为你推荐")
                    .font(.title2.weight(.semibold))
                ContentPlaceholder(symbol: "sparkles", title: "推荐内容即将呈现", detail: "新内容和个性化推荐会在这里出现。")
            }
        case .discover:
            ContentPlaceholder(symbol: "sparkles", title: "发现新内容", detail: "热门内容、主题和最新更新会显示在这里。")
        case .radio:
            ContentPlaceholder(symbol: "dot.radiowaves.left.and.right", title: "广播频道", detail: "选择一个频道，开始收听正在播放的内容。")
        case .library:
            VStack(spacing: 16) {
                ContentPlaceholder(symbol: "square.stack", title: "你的资料库", detail: "收藏的内容和播放记录会整理在这里。")
                Button {
                    isShowingDebugSheet = true
                } label: {
                    Label("调试功能", systemImage: "ladybug")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        case .search:
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索内容或频道", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                ContentPlaceholder(
                    symbol: "magnifyingglass",
                    title: searchQuery.isEmpty ? "搜索 Vial" : "没有找到相关内容",
                    detail: searchQuery.isEmpty ? "输入名称，查找内容或广播频道。" : "试试其他关键词。"
                )
            }
        }
    }
}

private struct VialRootHeader: View {
    let title: String
    let subtitle: String
    let collapseProgress: CGFloat
    let expandedHeight: CGFloat
    let collapsedHeight: CGFloat

    private var headerHeight: CGFloat {
        expandedHeight - (expandedHeight - collapsedHeight) * collapseProgress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 32 - 8 * collapseProgress, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .opacity(1 - collapseProgress)
                        .frame(height: 20 * (1 - collapseProgress), alignment: .top)
                        .clipped()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .frame(height: headerHeight, alignment: .center)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
        .background(.regularMaterial)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: collapseProgress > 0.5)
    }
}

private struct ContentPlaceholder: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct VialDebugSettingsView: View {
    @AppStorage("debug.header.expandedHeight") private var expandedHeight = 126
    @AppStorage("debug.header.collapsedHeight") private var collapsedHeight = 68
    @AppStorage("debug.header.collapseDistance") private var collapseDistance = 64

    var body: some View {
        Form {
            Section {
                DisclosureGroup("导航栏 Header") {
                    Stepper(value: $expandedHeight, in: 100...180, step: 2) {
                        metricLabel("展开高度", value: expandedHeight)
                    }
                    Stepper(value: $collapsedHeight, in: 52...100, step: 2) {
                        metricLabel("收起高度", value: collapsedHeight)
                    }
                    Stepper(value: $collapseDistance, in: 24...160, step: 4) {
                        metricLabel("收起滚动距离", value: collapseDistance)
                    }
                    Button("恢复 Header 默认值", systemImage: "arrow.counterclockwise") {
                        expandedHeight = 126
                        collapsedHeight = 68
                        collapseDistance = 64
                    }
                }
            }

            Section("说明") {
                Text("调试参数用于临时调整 Vial 导航栏布局。标签栏显示状态和搜索模式请在系统设置中修改。")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("调试入口暂时位于资料库页面。")
            }
        }
    }

    private func metricLabel(_ title: String, value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct VialScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
