import SwiftUI

// ─────────────────────────────────────────────────────────────
//  RootTabView.swift — 5탭 골격 (홈 / 플래너 / 타종 / 기록 / 설정)
// ─────────────────────────────────────────────────────────────

struct RootTabView: View {
    enum Tab: Hashable { case home, planner, bell, log, settings }
    @State private var tab: Tab = .home

    var body: some View {
        TabView(selection: $tab) {
            HomeView(onOpen: { tab = $0 })
                .tabItem { Label { Text("홈") } icon: { Icon(.home, size: 18) } }
                .tag(Tab.home)

            PlannerHomeView()
                .tabItem { Label { Text("플래너") } icon: { Icon(.planner, size: 18) } }
                .tag(Tab.planner)

            BellView()
                .tabItem { Label { Text("타종") } icon: { Icon(.bell, size: 18) } }
                .tag(Tab.bell)

            StudyLogView()
                .tabItem { Label { Text("기록") } icon: { Icon(.log, size: 18) } }
                .tag(Tab.log)

            SettingsView()
                .tabItem { Label { Text("설정") } icon: { Icon(.settings, size: 18) } }
                .tag(Tab.settings)
        }
        .tint(Theme.ink)
    }
}
