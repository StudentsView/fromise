import SwiftUI
import AdFitSDK
import AppTrackingTransparency

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
    @State private var didRequestATT = false

    init() {
        AdFit.configInit()                                   // 애드핏 SDK 초기화(앱 1회)
    }

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
                        requestTrackingIfNeeded()       // 최초 실행 시 ATT 추적 동의 요청
                    } else if phase == .background {
                        // 백그라운드 진입 시 위젯 최신화(오늘 누적/플래너/2G)
                        WidgetBridge.updateStudy(seconds: StudyTracker.shared.todaySeconds)
                        planner.pushTodayWidget()
                        WidgetBridge.reloadAll()
                    }
                }
                .onChange(of: alarm.isRinging) { _, ringing in
                    RingingWindow.shared.show(ringing, alarm: alarm)
                }
        }
    }

    /// 앱이 처음으로 활성화될 때 한 번만 ATT(추적 투명성) 동의창을 띄운다.
    /// 시스템 동의창은 foreground active 상태에서만 노출되므로 scenePhase==.active에서 호출.
    private func requestTrackingIfNeeded() {
        guard !didRequestATT,
              ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        didRequestATT = true
        // 활성화 직후 잠깐 늦춰 호출해야 동의창이 안정적으로 표시됨
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}
