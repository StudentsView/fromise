import Foundation
import WidgetKit

// ─────────────────────────────────────────────────────────────
//  WidgetBridge — 앱 → 위젯 데이터 전달
//  앱 그룹(공유 UserDefaults)에 위젯이 읽을 스냅샷을 쓰고 타임라인 갱신을 요청한다.
//  (위젯 측 키/포맷은 FromiseWidgets/WidgetData.swift 의 WG 와 동일해야 함)
// ─────────────────────────────────────────────────────────────
enum WidgetBridge {
    static let group = "group.com.flmang.Fromise"
    private static var ud: UserDefaults? { UserDefaults(suiteName: group) }

    private static let ymdFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"; return f
    }()

    /// 오늘 누적 순공시간(초) 스냅샷
    static func updateStudy(seconds: Int, date: Date = Date()) {
        guard let ud else { return }
        ud.set(seconds, forKey: "w.study.seconds")
        ud.set(ymdFmt.string(from: date), forKey: "w.study.dayKey")
        stamp()
        reload("StudyWidget")
    }

    /// 오늘 플래너 스냅샷 (상단 몇 개 + 완료율 + 순공/목표 분)
    private struct TaskLite: Codable { let t: String; let d: Bool }
    static func updatePlanner(dayKey: String, tasks: [(text: String, done: Bool)],
                              achievement: Int, netMinutes: Int?, goalMinutes: Int?) {
        guard let ud else { return }
        let lite = tasks.prefix(6).map { TaskLite(t: $0.text, d: $0.done) }
        let json = (try? JSONEncoder().encode(Array(lite))).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        ud.set(dayKey, forKey: "w.planner.dayKey")
        ud.set(json, forKey: "w.planner.tasksJSON")
        ud.set(achievement, forKey: "w.planner.achievement")
        ud.set(netMinutes ?? -1, forKey: "w.planner.netMin")
        ud.set(goalMinutes ?? -1, forKey: "w.planner.goalMin")
        stamp()
        reload("ScheduleWidget")
    }

    /// 2G 상태(twoG.endsAt/startedAt)는 TwoGStore가 이미 앱 그룹에 쓰므로 타임라인만 갱신
    static func reloadTwoG() { reload("TwoGWidget") }

    static func reloadAll() { WidgetCenter.shared.reloadAllTimelines() }

    private static func stamp() { ud?.set(Date().timeIntervalSince1970, forKey: "w.updatedAt") }
    private static func reload(_ kind: String) { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
}
