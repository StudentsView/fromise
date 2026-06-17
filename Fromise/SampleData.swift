import Foundation

// ─────────────────────────────────────────────────────────────
//  SampleData.swift — 화면 먼저 완성하기 위한 임시 데이터
//  Part 3(데이터 계층)에서 실제 모델/저장소로 교체 예정
// ─────────────────────────────────────────────────────────────

struct TodayTask: Identifiable {
    let id = UUID()
    var text: String
    var done: Bool
}

struct TodaySummary {
    var dateText: String      // "6월 17일"
    var dowText: String       // "수요일"
    var ddayText: String      // "D-155"
    var ddaySub: String
    var studiedMinutes: Int   // 270 = 4:30
    var goalMinutes: Int      // 420 = 7:00
    var tasks: [TodayTask]

    /// 달성률(완료/전체) — Achievement 자동 계산과 동일
    var achievement: Int {
        guard !tasks.isEmpty else { return 0 }
        return Int(Double(tasks.filter { $0.done }.count) / Double(tasks.count) * 100)
    }
    var doneCount: Int { tasks.filter { $0.done }.count }

    static func hm(_ min: Int) -> String { "\(min / 60):" + String(format: "%02d", min % 60) }
    var studiedText: String { Self.hm(studiedMinutes) }
    var goalText: String { Self.hm(goalMinutes) }
}

enum SampleData {
    static let today = TodaySummary(
        dateText: "6월 17일",
        dowText: "수요일",
        ddayText: "D-155",
        ddaySub: "6월 모의평가 회고는 오늘까지 마무리해요",
        studiedMinutes: 270,
        goalMinutes: 420,
        tasks: [
            TodayTask(text: "국어 비문학 기출 2지문", done: true),
            TodayTask(text: "수학 미적분 20문항", done: true),
            TodayTask(text: "영어 듣기 1회분 + 오답", done: false),
            TodayTask(text: "한국사 개념 1단원", done: true),
            TodayTask(text: "탐구 모의 1회분", done: false),
        ]
    )
}
