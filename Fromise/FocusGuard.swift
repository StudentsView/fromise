import Foundation
import Combine
import FamilyControls
import ManagedSettings

// ─────────────────────────────────────────────────────────────
//  FocusGuard.swift — 집중 화이트리스트(Screen Time API)
//  · 사용자가 고른 "허용 앱/사이트"만 쓸 수 있게 하고 나머지는 전부 차단.
//  · 차단의 핵심은 ManagedSettings의 .all(except:) 정책(= 화이트리스트).
//  · 기록 세션이 시작되면 차단을 켜고, 끝나면 해제.
//  · 권한은 FamilyControls 권한(설정 > 스크린타임)으로 1회 승인.
// ─────────────────────────────────────────────────────────────
@MainActor
final class FocusGuard: ObservableObject {
    static let shared = FocusGuard()

    private let store = ManagedSettingsStore()
    private let d = UserDefaults.standard
    private let key = "focus.selection"

    /// 허용 앱/사이트 선택값 (FamilyActivityPicker 바인딩)
    @Published var selection = FamilyActivitySelection() { didSet { save() } }
    /// 권한 승인 여부
    @Published var authorized = false
    /// 현재 차단(화이트리스트) 적용 중인지
    @Published var shielded = false
    /// 시스템 권한 요청 전에 띄울 자체 안내 팝업 표시 여부
    @Published var showPrePrompt = false

    private init() {
        load()
        refreshAuthorization()
    }

    // MARK: 권한
    func refreshAuthorization() {
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }
    /// 메인 화면 진입 시 권한 확인. 콜드스타트 직후엔 authorizationStatus가 잠깐 .notDetermined로
    /// 잘못 보고될 수 있어, 여러 번 재확인해 "정말 권한이 없을 때"만 자체 안내 팝업을 띄운다.
    func ensureAuthorization() async {
        refreshAuthorization()
        if authorized { return }
        for _ in 0..<3 {                       // 상태 안정화까지 재확인(승인 상태면 곧 잡힘)
            try? await Task.sleep(for: .milliseconds(300))
            refreshAuthorization()
            if authorized { return }
        }
        // 여러 번 확인해도 미승인 → 실제로 권한 없음(미요청 또는 거부)
        let status = AuthorizationCenter.shared.authorizationStatus
        if status == .notDetermined || status == .denied {
            showPrePrompt = true
        }
    }
    /// 스크린타임 권한 요청(설정 다이얼로그). 승인되어야 차단을 걸 수 있음.
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            // 거부/실패 — authorized는 아래에서 갱신
        }
        refreshAuthorization()
    }

    // MARK: 선택 저장/로드
    private func load() {
        guard let data = d.data(forKey: key),
              let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return }
        selection = sel
    }
    private func save() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        d.set(data, forKey: key)
    }

    /// 허용 항목이 하나라도 지정됐는지
    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty
        || !selection.webDomainTokens.isEmpty
        || !selection.categoryTokens.isEmpty
    }
    var allowedAppCount: Int { selection.applicationTokens.count }
    var allowedWebCount: Int { selection.webDomainTokens.count }

    // MARK: 차단(화이트리스트) 켜기/끄기
    /// 선택한 앱/사이트를 제외한 전체를 차단 — .all(except:)가 화이트리스트
    func startShield() {
        guard authorized else { return }
        store.shield.applicationCategories = .all(except: selection.applicationTokens)
        store.shield.webDomainCategories   = .all(except: selection.webDomainTokens)
        shielded = true
    }
    /// 모든 차단 해제
    func stopShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        shielded = false
    }
}
