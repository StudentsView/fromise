import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────
//  FromiseWidgetsBundle — 위젯 익스텐션 진입점
//  ① 오늘 순공시간  ② 2G폰 모드 지속/남은 시간  ③ 오늘의 스케줄
// ─────────────────────────────────────────────────────────────
@main
struct FromiseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        StudyWidget()
        TwoGWidget()
    }
}
