import SwiftUI

// ─────────────────────────────────────────────────────────────
//  RootTabView.swift — 5탭 골격 (홈 / 플래너 / 타종 / 기록 / 설정)
//  guest=true(비로그인 둘러보기)면 플래너·기록·설정 탭은
//  로그인 요청 오버레이로 덮어 사용을 막는다. 홈·타종은 그대로 사용 가능.
// ─────────────────────────────────────────────────────────────

struct RootTabView: View {
    enum Tab: Hashable { case home, planner, bell, log, settings }
    var guest: Bool = false
    @State private var tab: Tab = .home
    @State private var settingsPath: [SettingsRoute] = []   // 홈에서 설정 탭의 특정 화면으로 바로 이동

    var body: some View {
        TabView(selection: $tab) {
            HomeView(guest: guest, onOpen: { tab = $0 },
                     onOpen2G: { settingsPath = [.twoG]; tab = .settings })
                .tabItem { Label { Text("홈") } icon: { Icon(.home, size: 18) } }
                .tag(Tab.home)

            PlannerHomeView()
                .guestLocked(guest, feature: "플래너")
                .tabItem { Label { Text("플래너") } icon: { Icon(.planner, size: 18) } }
                .tag(Tab.planner)

            BellView()
                .tabItem { Label { Text("타종") } icon: { Icon(.bell, size: 18) } }
                .tag(Tab.bell)

            StudyLogView()
                .guestLocked(guest, feature: "학습 기록")
                .tabItem { Label { Text("기록") } icon: { Icon(.log, size: 18) } }
                .tag(Tab.log)

            SettingsView(path: $settingsPath)
                .guestLocked(guest, feature: "설정")
                .tabItem { Label { Text("설정") } icon: { Icon(.settings, size: 18) } }
                .tag(Tab.settings)
        }
        .tint(Theme.ink)
    }
}

// MARK: - 비로그인 잠금 오버레이

extension View {
    /// active==true면 화면을 흐리게 비활성화하고 로그인 요청 오버레이를 올린다.
    @ViewBuilder
    func guestLocked(_ active: Bool, feature: String) -> some View {
        if active { modifier(GuestLock(feature: feature)) }
        else { self }
    }
}

private struct GuestLock: ViewModifier {
    let feature: String
    func body(content: Content) -> some View {
        content
            .disabled(true)
            .blur(radius: 3)
            .overlay { LoginRequiredOverlay(feature: feature) }
    }
}

struct LoginRequiredOverlay: View {
    @EnvironmentObject var auth: AuthStore
    let feature: String

    var body: some View {
        ZStack {
            Theme.paper.opacity(0.55)
                .background(.ultraThinMaterial)

            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 60, height: 60)
                    .background(Theme.hlCheese).clipShape(Circle())

                Text("로그인이 필요해요")
                    .font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.ink)
                Text("\(feature) 기능은 로그인 후 사용할 수 있어요.\n홈과 타종 시스템은 로그인 없이 둘러볼 수 있어요.")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .lineLimit(2).minimumScaleFactor(0.8)   // 글자 크기 유지, 좁은 기기에서만 미세 축소
                    .fixedSize(horizontal: false, vertical: true)

                Button { auth.exitGuest() } label: {
                    Text("시작하기")
                        .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.vertical, 26).padding(.horizontal, 18)   // 좌우 여백 축소로 텍스트 칸을 넓힘
            .frame(maxWidth: 460)
            .card()
            .padding(.horizontal, 14)
        }
        .ignoresSafeArea()
    }
}
