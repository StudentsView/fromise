import SwiftUI

// ─────────────────────────────────────────────────────────────
//  WidgetData.swift — 앱 그룹(공유 UserDefaults)에서 위젯용 데이터를 읽는다.
//  앱(WidgetBridge)이 같은 키로 써 둔 스냅샷을 읽어서 표시.
//  2G 상태(twoG.endsAt / twoG.startedAt)는 TwoGStore가 이미 앱 그룹에 쓰는 값을 그대로 사용.
// ─────────────────────────────────────────────────────────────

enum WG {
    static let group = "group.com.flmang.Fromise"
    static var ud: UserDefaults? { UserDefaults(suiteName: group) }

    static let ymdFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"; return f
    }()
    static let dayKeyFmt: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    // MARK: 학습 누적(초) — 저장된 날짜가 오늘이 아니면 0
    static func studySeconds(now: Date = Date()) -> Int {
        guard let ud else { return 0 }
        let saved = ud.string(forKey: "w.study.dayKey") ?? ""
        return saved == ymdFmt.string(from: now) ? ud.integer(forKey: "w.study.seconds") : 0
    }

    // MARK: 2G폰 모드
    struct TwoG { let active: Bool; let startedAt: Date?; let endsAt: Date? }
    static func twoG(now: Date = Date()) -> TwoG {
        guard let ud, let end = ud.object(forKey: "twoG.endsAt") as? Date, end > now else {
            return TwoG(active: false, startedAt: nil, endsAt: nil)
        }
        return TwoG(active: true, startedAt: ud.object(forKey: "twoG.startedAt") as? Date, endsAt: end)
    }

    // MARK: 오늘 플래너 스냅샷
    struct TaskLite: Codable { let t: String; let d: Bool }
    struct Planner { let tasks: [TaskLite]; let achievement: Int; let netMin: Int?; let goalMin: Int? }
    static func planner(now: Date = Date()) -> Planner {
        guard let ud, ud.string(forKey: "w.planner.dayKey") == dayKeyFmt.string(from: now) else {
            return Planner(tasks: [], achievement: 0, netMin: nil, goalMin: nil)
        }
        let json = ud.string(forKey: "w.planner.tasksJSON") ?? "[]"
        let tasks = (try? JSONDecoder().decode([TaskLite].self, from: Data(json.utf8))) ?? []
        let net = ud.integer(forKey: "w.planner.netMin"), goal = ud.integer(forKey: "w.planner.goalMin")
        return Planner(tasks: tasks, achievement: ud.integer(forKey: "w.planner.achievement"),
                       netMin: net < 0 ? nil : net, goalMin: goal < 0 ? nil : goal)
    }

    // MARK: 포맷
    static func hm(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }
    static func minToHM(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
    }
    /// 일/시/분 — 2G 지속·남은 시간 표시용
    static func dhm(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval)), d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)일 \(h)시간 \(m)분" }
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(m)분"
    }
}

// 위젯 전용 팔레트 (앱 Theme는 다른 타깃이라 직접 못 씀)
enum WTheme {
    static let paper  = Color(red: 0.99, green: 0.98, blue: 0.95)
    static let ink    = Color(red: 0.13, green: 0.12, blue: 0.11)
    static let ink2   = Color(red: 0.36, green: 0.34, blue: 0.31)
    static let ink3   = Color(red: 0.55, green: 0.52, blue: 0.49)
    static let good   = Color(red: 0.20, green: 0.62, blue: 0.40)
    static let cheese = Color(red: 0.97, green: 0.76, blue: 0.34)
    static let sky    = Color(red: 0.40, green: 0.66, blue: 0.85)
    static let line   = Color(red: 0.88, green: 0.86, blue: 0.82)
}
