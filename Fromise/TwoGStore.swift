import Foundation
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity
import Supabase

// ─────────────────────────────────────────────────────────────
//  TwoGStore.swift — "2G폰 모드" (기간 잠금)
//  · 활성화하면 기간(최소 1일) 동안 Fromise + 허용 앱/사이트(화이트리스트)만 사용.
//  · 활성화 시점에 8자리 숫자 해제코드를 새로 발급해 Supabase(two_g_locks)에 보관.
//  · 잠금은 별도 named ManagedSettingsStore로 적용(시스템에 영속 → 앱 종료해도 유지).
//  · DeviceActivityMonitor 확장이 기간 종료 시 자동 해제(intervalDidEnd).
//  · 앱 재실행 시 만료 시각을 확인해 복원/해제(끊김 방지).
//  · 해제: 메일로 받은 코드를 입력 → Supabase의 코드와 대조 → 일치 시 해제 + 코드 삭제.
// ─────────────────────────────────────────────────────────────

enum AppGroup { static let id = "group.com.flmang.Fromise" }

extension ManagedSettingsStore.Name { static let twoG = Self("fromise.twoG") }
extension DeviceActivityName { static let twoG = Self("fromise.twoG") }

@MainActor
final class TwoGStore: ObservableObject {
    static let shared = TwoGStore()

    @Published private(set) var active = false
    @Published private(set) var endsAt: Date?
    @Published private(set) var unlockCount = 0   // 누적 메일 해제 횟수(= 다음 메일 코드 지연 시간h)
    @Published var busy = false
    @Published var lastError: String?

    private let store = ManagedSettingsStore(named: .twoG)
    private let center = DeviceActivityCenter()
    private let ud = UserDefaults(suiteName: AppGroup.id) ?? .standard
    private let std = UserDefaults.standard   // 일별 지속시간 통계(학습 기록과 동일 저장소)
    private let isoFmt = ISO8601DateFormatter()
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f }()

    private enum K { static let endsAt = "twoG.endsAt"; static let startedAt = "twoG.startedAt"; static let expired = "twoG.expired" }

    private init() { restore() }

    /// 남은 시간(초)
    var remaining: TimeInterval { max(0, (endsAt ?? .distantPast).timeIntervalSinceNow) }

    // MARK: 해제 횟수 통계
    /// 누적 해제 횟수 로드(공지/지연 안내용). 화면 진입 시 호출.
    func loadStats() async {
        guard let uid = supabase.auth.currentUser?.id.uuidString else { return }
        struct StatRow: Decodable { let unlock_count: Int }
        do {
            let rows: [StatRow] = try await supabase.from("two_g_stats")
                .select("unlock_count").eq("user_id", value: uid).limit(1).execute().value
            unlockCount = rows.first?.unlock_count ?? 0
        } catch {
            // 통계 행이 없으면 0 유지
        }
    }
    private func bumpStats(to newCount: Int) async {
        guard let uid = supabase.auth.currentUser?.id.uuidString else { return }
        struct Stat: Encodable { let user_id: String; let unlock_count: Int }
        _ = try? await supabase.from("two_g_stats")
            .upsert(Stat(user_id: uid, unlock_count: newCount), onConflict: "user_id")
            .execute()
        unlockCount = newCount
    }

    // MARK: 활성화
    /// days일 동안 잠금 시작(최소 1일). 허용 앱/사이트는 FocusGuard.selection 사용.
    func activate(days: Int) async {
        lastError = nil
        guard FocusGuard.shared.authorized else { lastError = "스크린타임 권한이 필요해요."; return }
        guard let uid = supabase.auth.currentUser?.id.uuidString else { lastError = "로그인이 필요해요."; return }
        let email = supabase.auth.currentUser?.email ?? ""
        let span = max(1, days)
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: span, to: start) else { return }

        busy = true; defer { busy = false }
        await loadStats()   // 최신 누적 해제 횟수 확보(지연 시간 스냅샷용)

        // 1) 새 해제코드(8자리) 발급 → Supabase 보관(유저당 1개, 매번 새 코드)
        //    unlock_count = 지금까지의 해제 횟수 → Worker가 이만큼 시간 지연 후 발송
        let code = Self.makeCode()
        struct Lock: Encodable { let user_id, code, email, started_at, ends_at: String; let unlock_count: Int }
        do {
            _ = try await supabase.from("two_g_locks")
                .upsert(Lock(user_id: uid, code: code, email: email,
                             started_at: isoFmt.string(from: start),
                             ends_at: isoFmt.string(from: end),
                             unlock_count: unlockCount),
                        onConflict: "user_id")
                .execute()
        } catch {
            lastError = "서버 연결에 실패했어요. 네트워크를 확인해 주세요."
            return
        }

        // 2) 화이트리스트 잠금 적용 + 기간 모니터링 시작
        applyShield()
        startMonitoring(start: start, end: end)

        // 3) 상태 영속(App Group) → 앱 재실행/확장과 공유
        ud.set(end, forKey: K.endsAt)
        ud.set(start, forKey: K.startedAt)   // 지속시간 기록 시작점
        endsAt = end
        active = true
        WidgetBridge.reloadTwoG()            // 위젯에 활성 상태 반영
    }

    // MARK: 코드로 해제
    /// 입력 코드가 Supabase의 현재 코드와 일치하면 잠금 해제 + 코드 삭제
    func unlock(code input: String) async -> Bool {
        lastError = nil
        let typed = input.trimmingCharacters(in: .whitespaces)
        guard typed.count == 8, let uid = supabase.auth.currentUser?.id.uuidString else {
            lastError = "코드 8자리를 정확히 입력해 주세요."; return false
        }
        busy = true; defer { busy = false }
        struct Row: Decodable { let code: String }
        do {
            let rows: [Row] = try await supabase.from("two_g_locks")
                .select("code").eq("user_id", value: uid).limit(1).execute().value
            guard rows.first?.code == typed else {
                lastError = "코드가 일치하지 않아요."; return false
            }
        } catch {
            lastError = "확인에 실패했어요. 네트워크를 확인해 주세요."; return false
        }
        await bumpStats(to: unlockCount + 1)   // 메일 해제 1회 누적 → 다음엔 지연 1시간 증가
        recordTwoG(end: Date())                // 시작~해제까지 지속시간 기록
        await teardown(deleteRemote: true)
        return true
    }

    // MARK: 복원(앱 실행 시)
    func restore() {
        // 확장이 기간 종료로 자동 해제한 경우 → 지속시간 기록 + 원격 코드까지 정리
        if ud.bool(forKey: K.expired) {
            ud.set(false, forKey: K.expired)
            recordTwoG(end: ud.object(forKey: K.endsAt) as? Date ?? Date())
            Task { await teardown(deleteRemote: true) }
            return
        }
        guard let end = ud.object(forKey: K.endsAt) as? Date else { active = false; endsAt = nil; return }
        if end > Date() {
            endsAt = end; active = true
            applyShield()                          // 혹시 풀렸으면 재적용(끊김 방지)
            startMonitoring(start: Date(), end: end)
            WidgetBridge.reloadTwoG()
        } else {
            recordTwoG(end: end)                          // 이미 만료 → 예정 종료까지 기록
            Task { await teardown(deleteRemote: true) }
        }
    }

    // MARK: 내부
    private func applyShield() {
        let sel = FocusGuard.shared.selection
        store.shield.applicationCategories = .all(except: sel.applicationTokens)
        store.shield.webDomainCategories   = .all(except: sel.webDomainTokens)
    }
    private func startMonitoring(start: Date, end: Date) {
        let cal = Calendar.current
        let f: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents(f, from: start),
            intervalEnd:   cal.dateComponents(f, from: end),
            repeats: false)
        center.stopMonitoring([.twoG])
        try? center.startMonitoring(.twoG, during: schedule)
    }
    private func teardown(deleteRemote: Bool) async {
        store.clearAllSettings()
        center.stopMonitoring([.twoG])
        ud.removeObject(forKey: K.endsAt)
        active = false; endsAt = nil
        WidgetBridge.reloadTwoG()            // 위젯에 해제 반영
        if deleteRemote, let uid = supabase.auth.currentUser?.id.uuidString {
            _ = try? await supabase.from("two_g_locks").delete().eq("user_id", value: uid).execute()
        }
    }

    private static func makeCode() -> String { String(format: "%08d", Int.random(in: 0...99_999_999)) }

    // MARK: 2G 지속시간 일별 기록 (학습 기록 표시용)
    /// 시작 시각(영속)부터 end까지를 날짜별로 쪼개 twoG.<ymd>에 누적
    private func recordTwoG(end: Date) {
        guard let start = ud.object(forKey: K.startedAt) as? Date else { return }
        ud.removeObject(forKey: K.startedAt)
        guard end > start else { return }
        let cal = Calendar.current
        var cursor = start
        while cursor < end {
            let nextMidnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: cursor) ?? end)
            let segEnd = min(nextMidnight, end)
            let secs = Int(segEnd.timeIntervalSince(cursor))
            if secs > 0 {
                let key = "twoG.\(Self.dayFmt.string(from: cursor))"
                std.set(std.integer(forKey: key) + secs, forKey: key)
            }
            cursor = segEnd
        }
    }
}
