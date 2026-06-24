import SwiftUI

// ─────────────────────────────────────────────────────────────
//  FromiseApp.swift — 앱 진입점
//  RootFlow가 인증/온보딩/메인을 흐름에 맞게 보여줌.
// ─────────────────────────────────────────────────────────────

@main
struct FromiseApp: App {
    @StateObject private var planner = PlannerStore()        // 빈 상태로 시작 → 로그인 시 Supabase 로드
    @StateObject private var profile = ProfileStore()        // 닉네임·생년월일·D-Day
    @StateObject private var auth    = AuthStore()           // Supabase 인증
    @StateObject private var alarm   = AlarmManager.shared   // 알람/타이머
    @StateObject private var focus   = FocusGuard.shared     // 스크린타임 권한/차단
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootFlow()
                .environmentObject(planner)
                .environmentObject(profile)
                .environmentObject(auth)
                .environmentObject(alarm)
                .onAppear { alarm.configure() }
                .alert("스크린타임 권한이 필요해요", isPresented: $focus.showPrePrompt) {
                    Button("권한 요청하기") { Task { await focus.requestAuthorization() } }
                } message: {
                    Text("Fromise를 사용하기 위해 스크린 타임 권한이 필요해요. 제가 요청을 띄울테니, 권한을 허용해주세요.")
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        alarm.appBecameActive()
                        TwoGStore.shared.restore()      // 복귀 시 만료/복원 확인
                        focus.refreshAuthorization()    // 권한 상태 갱신(승인 플래그 저장)
                    }
                }
                .onChange(of: alarm.isRinging) { _, ringing in
                    RingingWindow.shared.show(ringing, alarm: alarm)
                }
        }
    }
}
