import SwiftUI

// ─────────────────────────────────────────────────────────────
//  RootFlow.swift — 앱 흐름 게이트
//  로그인 순간: 계정 메타데이터 → ProfileStore, 웹 플래너 → PlannerStore(읽기).
//  로그아웃: 로컬 초기화.
// ─────────────────────────────────────────────────────────────

struct RootFlow: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var planner: PlannerStore

    var body: some View {
        ZStack {
            switch auth.phase {
            case .signedOut:
                AuthView().transition(.opacity)
            case .verifying:
                VerifyView().transition(.opacity)
            case .signedIn:
                if profile.onboarded {
                    RootTabView().transition(.opacity)
                } else {
                    OnboardingView().transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.45), value: auth.phase)
        .animation(.easeInOut(duration: 0.45), value: profile.onboarded)
        .onAppear { if auth.phase == .signedIn { onSignedIn() } }
        .onChange(of: auth.phase) { _, phase in
            if phase == .signedIn { onSignedIn() }
            else if phase == .signedOut { onSignedOut() }
        }
    }

    private func onSignedIn() {
        let m = auth.currentMeta()
        profile.applyMetadata(nickname: m.nickname, birth: m.birth, exam: m.exam)
        let p = planner
        let a = auth
        p.onChange = { PlannerSync.scheduleSave(from: p) }
        SyncQueue.shared.uploadNickname = { await a.updateNickname($0) }
        SyncQueue.shared.uploadBirth    = { await a.setBirthOnce($0) }
        SyncQueue.shared.uploadPlanner  = { await PlannerSync.save(from: p); return true }
        Task { await PlannerSync.load(into: p); await SyncQueue.shared.flush() }
    }
    private func onSignedOut() {
        profile.reset()
        planner.onChange = nil
        PlannerSync.clear()
        planner.days = [:]
    }
}
