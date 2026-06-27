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

    private enum K { static let endsAt = "twoG.endsAt"; static let startedAt = "twoG.startedAt"; static let expired = "twoG.expired"; static let userId = "twoG.userId" }

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
        let span = max(1, days)
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: span, to: start) else { return }

        busy = true; defer { busy = false }

        // 0) 유효한 세션 확보(토큰 자동 갱신) — 만료된 토큰으로 인한 '코드 저장 실패'를 막는다.
        //    currentUser만 보면 토큰이 만료돼도 비어있지 않아 insert가 401로 조용히 실패할 수 있다.
        let uid: String, email: String
        do {
            let session = try await supabase.auth.session
            uid = session.user.id.uuidString
            email = (session.user.email ?? "").lowercased()   // 인바운드 메일 매칭은 소문자 기준
        } catch {
            lastError = "로그인이 필요해요. 다시 로그인 후 시도해 주세요."; return
        }

        await loadStats()   // 최신 누적 해제 횟수 확보(지연 시간 스냅샷용)

        // 1) 새 해제코드(8자리) 발급 → Supabase 보관(유저당 1개, 매번 새 코드)
        //    저장 후 '재조회로 검증'해, 코드가 서버에 확실히 있을 때만 잠금을 건다(못 푸는 잠금 방지).
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
            struct Row: Decodable { let code: String }
            let rows: [Row] = try await supabase.from("two_g_locks")
                .select("code").eq("user_id", value: uid).limit(1).execute().value
            guard rows.first?.code == code else {
                lastError = "해제코드 저장을 확인하지 못했어요. 네트워크를 확인해 다시 시도해 주세요."; return
            }
        } catch {
            lastError = "서버 연결에 실패했어요. 네트워크를 확인해 주세요."
            return
        }

        // 2) 상태 영속(App Group)을 먼저 기록 — 확장(Monitor)은 endsAt 기준으로 동작하므로
        //    모니터링 시작 전에 새 종료 시각을 써둬야 잔여/허위 만료가 끼어들지 않는다.
        ud.set(end, forKey: K.endsAt)
        ud.set(start, forKey: K.startedAt)   // 지속시간 기록 시작점
        ud.set(uid, forKey: K.userId)        // 잠금 소유 계정 — 계정 전환 시 오적용 방지
        ud.set(false, forKey: K.expired)     // 이전에 남은 만료 플래그 제거

        // 3) 화이트리스트 잠금 적용 + 기간 모니터링 시작
        applyShield()
        startMonitoring(start: start, end: end)

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

    // MARK: 복원 / 만료 확인 (앱 실행·복귀·화면 진입 시)
    //  핵심 원칙: 한 번 활성화되면 (A) 정해둔 기간이 모두 지나 자연 만료되거나,
    //  (B) 메일로 받은 해제코드를 입력해 unlock()으로 푸는 경우 외에는 절대 꺼지지 않는다.
    //  탭 이동·백그라운드·앱 종료/재실행·일시적 저장소 읽기 실패로는 해제되지 않는다.
    func restore() {
        guard let end = ud.object(forKey: K.endsAt) as? Date else {
            // 저장된 잠금이 없을 때만 비활성. (endsAt는 teardown에서만 지워진다)
            // 진행 중인데 일시적으로 못 읽은 경우엔 끄지 않는다(오탐 방지).
            if !active { endsAt = nil }
            return
        }
        // 다른 계정이 로그인돼 있으면(서명인 + 소유 계정 불일치) 이 기기의 잠금은 그 계정 것이 아니므로 해제.
        // (로그아웃 상태=currentUser nil 일 때는 건드리지 않음 → 단순 로그아웃으로 탈출 불가)
        if let cur = supabase.auth.currentUser?.id.uuidString,
           let owner = ud.string(forKey: K.userId), cur != owner {
            clearLocalLock()
            return
        }
        if Date() >= end {
            // (A) 사전에 정해둔 시간이 모두 지남 → 자연 해제
            recordTwoG(end: end)                  // 시작~예정 종료까지 지속시간 기록
            ud.set(false, forKey: K.expired)
            Task { await teardown(deleteRemote: true) }
            return
        }
        // 아직 기간 내 → 무조건 잠금 유지/복원.
        // 모니터가 조기/허위로 만료 플래그를 세웠더라도(탭 이동 등) 기간 내면 무시한다.
        if ud.bool(forKey: K.expired) { ud.set(false, forKey: K.expired) }
        endsAt = end
        active = true
        applyShield()                             // 항상 재적용(끊김 방지 — 콜백 유발 없음)
        if !center.activities.contains(.twoG) {   // 이미 감시 중이면 재시작 금지(허위 intervalDidEnd 방지)
            startMonitoring(start: Date(), end: end)
        }
        WidgetBridge.reloadTwoG()
    }

    // MARK: 계정 기준 동기화 (앱 실행·복귀·로그인 직후)
    /// "지금 로그인된 계정"이 2G폰 모드 활성 계정인지 Supabase에서 확인하고, 기기 상태를 그에 맞춘다.
    ///  · 활성 계정이면 (어느 기기든) Screen Time 잠금을 적용/복원한다.
    ///  · 활성 잠금이 없는 계정이면 기기에 남은 잠금을 해제한다(계정 전환 대응).
    ///  · Supabase가 권위 기준. 네트워크 실패 시엔 로컬 상태를 그대로 둔다(임의로 끄지 않음).
    func syncFromCloud() async {
        guard let session = try? await supabase.auth.session else { return }   // 로그인 안 됨 → 로컬 유지
        let uid = session.user.id.uuidString
        struct Row: Decodable { let started_at: String?; let ends_at: String }
        let row: Row?
        do {
            let rows: [Row] = try await supabase.from("two_g_locks")
                .select("started_at, ends_at").eq("user_id", value: uid).limit(1).execute().value
            row = rows.first
        } catch {
            return   // 조회 실패 → 로컬 유지
        }
        guard let row else {
            // 이 계정은 활성 잠금이 없음 → 기기에 남은 잠금/상태 해제 (계정 전환·미잠금 계정 로그인).
            // 단, '현재 계정' 소유의 기간 내 로컬 잠금이 있는데 조회만 비어 온 경우(일시적 공백)엔
            // 절대 끄지 않는다 — 해제는 만료/코드 두 경로로만. (계정 전환·만료일 때만 정리)
            let owner = ud.string(forKey: K.userId)
            let localEnd = ud.object(forKey: K.endsAt) as? Date
            let currentUserValidLocal = (owner == uid) && (localEnd.map { $0 > Date() } ?? false)
            if !currentUserValidLocal, active || localEnd != nil { clearLocalLock() }
            return
        }
        // 잠금 행은 있으나 날짜 파싱 실패 → 안전하게 로컬 유지(끄지 않음). 해제는 만료/코드로만.
        guard let end = Self.parseISO(row.ends_at) else { return }
        if Date() >= end {
            // 기간 종료 → 자연 해제(+서버 코드 삭제)
            ud.set(uid, forKey: K.userId)
            recordTwoG(end: end)
            await teardown(deleteRemote: true)
            return
        }
        // 활성 잠금 → 이 기기에 적용/복원 (다른 기기에서 걸었어도 동일하게 잠금)
        if ud.object(forKey: K.startedAt) == nil {
            ud.set(row.started_at.flatMap { Self.parseISO($0) } ?? Date(), forKey: K.startedAt)
        }
        ud.set(end, forKey: K.endsAt)
        ud.set(uid, forKey: K.userId)
        ud.set(false, forKey: K.expired)
        endsAt = end
        active = true
        applyShield()
        if !center.activities.contains(.twoG) { startMonitoring(start: Date(), end: end) }
        WidgetBridge.reloadTwoG()
    }

    /// 이 기기의 잠금/상태만 해제(서버의 잠금 행·코드는 건드리지 않음).
    /// 미잠금 계정 로그인·계정 전환 시 사용. (해당 계정으로 다시 로그인하면 syncFromCloud가 재적용)
    private func clearLocalLock() {
        store.clearAllSettings()
        center.stopMonitoring([.twoG])
        ud.removeObject(forKey: K.endsAt)
        ud.removeObject(forKey: K.startedAt)
        ud.removeObject(forKey: K.userId)
        ud.set(false, forKey: K.expired)
        active = false; endsAt = nil
        WidgetBridge.reloadTwoG()
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
        ud.removeObject(forKey: K.userId)
        active = false; endsAt = nil
        WidgetBridge.reloadTwoG()            // 위젯에 해제 반영
        if deleteRemote, let uid = supabase.auth.currentUser?.id.uuidString {
            _ = try? await supabase.from("two_g_locks").delete().eq("user_id", value: uid).execute()
        }
    }

    private static func makeCode() -> String { String(format: "%08d", Int.random(in: 0...99_999_999)) }

    /// Supabase timestamptz 파싱 — 소수점 초 유무 모두 허용(PostgREST가 둘 다 보낼 수 있음)
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

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
