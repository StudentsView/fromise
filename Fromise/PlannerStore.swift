import SwiftUI
import Combine
import PencilKit

// ─────────────────────────────────────────────────────────────
//  PlannerStore.swift — 플래너 상태 (days 변경 시 onChange → Supabase 저장)
//  색·타임테이블은 UInt(0xRRGGBB)로 저장
// ─────────────────────────────────────────────────────────────

struct PlannerTask: Identifiable, Hashable {
    var id = UUID()
    var text = ""
    var done = false
    var hl: UInt? = nil          // 형광펜 색(hex)
}

struct CheckItem: Identifiable, Hashable {
    var id = UUID()
    var text = ""
    var done = false
}

struct DayData {
    var tasks: [PlannerTask] = []
    var checklist: [CheckItem] = []
    var goalMinutes: Int? = nil
    var netMinutes: Int? = nil
    var timetable: [String: UInt] = [:]   // "row_col" → 색(hex). row 0..<22(=06시~), col 0..<6
    var drawing = PKDrawing()

    /// 달성률(자동) = 완료/내용있는 항목
    var achievement: Int {
        let ne = tasks.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !ne.isEmpty else { return 0 }
        return Int(Double(ne.filter { $0.done }.count) / Double(ne.count) * 100)
    }
}

final class PlannerStore: ObservableObject {
    @Published var days: [String: DayData] = [:] { didSet { onChange?(); pushTodayWidget() } }
    /// days가 바뀔 때 호출 (Supabase 저장 예약 등). 로그인 시 RootFlow에서 연결.
    var onChange: (() -> Void)? = nil

    func day(_ key: String) -> DayData { days[key] ?? DayData() }

    /// 오늘 플래너(상단 항목·완료율·순공/목표 분)를 위젯으로 내보낸다.
    func pushTodayWidget() {
        let key = PKey.key(Date())
        let d = days[key] ?? DayData()
        let real = d.tasks.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        WidgetBridge.updatePlanner(dayKey: key,
                                   tasks: real.map { (text: $0.text, done: $0.done) },
                                   achievement: d.achievement,
                                   netMinutes: d.netMinutes, goalMinutes: d.goalMinutes)
    }

    /// DayData 전체에 대한 바인딩 (day.tasks[i].text 식으로 바로 편집 가능)
    func binding(_ key: String) -> Binding<DayData> {
        Binding(get: { self.days[key] ?? DayData() },
                set: { self.days[key] = $0 })
    }

    /// 달력 점/시간 표시에 쓰는 요약
    func hasContent(_ key: String) -> Bool {
        guard let d = days[key] else { return false }
        return d.tasks.contains { !$0.text.isEmpty } || d.netMinutes != nil || !d.timetable.isEmpty
    }

    // 화면 확인용 샘플 한 칸 (오늘)
    static let sample: PlannerStore = {
        let s = PlannerStore()
        var d = DayData()
        d.tasks = [
            PlannerTask(text: "국어 비문학 기출 2지문", done: true),
            PlannerTask(text: "수학 미적분 20문항", done: true, hl: 0xFCE8A6),
            PlannerTask(text: "영어 듣기 1회분 + 오답", done: false),
        ]
        d.checklist = [CheckItem(text: "단어장 30개", done: true),
                       CheckItem(text: "오답노트 정리", done: false)]
        d.goalMinutes = 420; d.netMinutes = 270
        s.days[PKey.key(Date())] = d
        return s
    }()
}

// MARK: - 날짜 키 유틸
enum PKey {
    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(_ d: Date) -> String { fmt.string(from: d) }
    static func date(_ k: String) -> Date { fmt.date(from: k) ?? Date() }
}

/// 형광펜 6색 (hex) — 타임테이블·태스크·드로잉 공용
let HL_HEX: [UInt] = [0xFCE8A6, 0xCDEBA3, 0xF9B79C, 0xCDB8EC, 0xF8B9D4, 0xA9D9F5]
