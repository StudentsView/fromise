import WidgetKit
import SwiftUI

// 오늘의 스케줄 — 상단 3개 + 완료율(도넛) + 순공시간 (가로형 medium 하나만, 업데이트 주기 짧게)
struct ScheduleEntry: TimelineEntry { let date: Date; let planner: WG.Planner }

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), planner: WG.Planner(
            tasks: [.init(t: "국어 비문학 기출 2지문", d: true),
                    .init(t: "수학 미적분 20문항", d: true),
                    .init(t: "영어 듣기 1회분 + 오답", d: false)],
            achievement: 66, netMin: 270, goalMin: 420))
    }
    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(ScheduleEntry(date: Date(), planner: WG.planner()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let entry = ScheduleEntry(date: Date(), planner: WG.planner())
        // 짧은 주기: 앱이 편집 때마다 reload + 2분 폴백
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(120))))
    }
}

// 앱 화면의 달성률 링과 동일한 도넛형 그래프 (% 텍스트 가운데)
struct WRing: View {
    let percent: Int
    var size: CGFloat = 58
    var line: CGFloat = 7
    var body: some View {
        ZStack {
            Circle().stroke(WTheme.line, lineWidth: line)
            Circle().trim(from: 0, to: CGFloat(max(0, min(100, percent))) / 100)
                .stroke(WTheme.good, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                .foregroundStyle(WTheme.ink).minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(width: size, height: size)
    }
}

struct ScheduleWidgetView: View {
    var entry: ScheduleEntry
    private var top: [WG.TaskLite] { Array(entry.planner.tasks.prefix(3)) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // 왼쪽: 제목 + 상단 3개
            VStack(alignment: .leading, spacing: 8) {
                Text("오늘의 스케줄").font(.system(size: 13, weight: .heavy)).foregroundStyle(WTheme.ink3)
                if top.isEmpty {
                    Spacer(minLength: 0)
                    Text("오늘 계획을 적어볼까요?")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(WTheme.ink3)
                    Spacer(minLength: 0)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(top.enumerated()), id: \.offset) { _, t in
                            HStack(spacing: 8) {
                                Image(systemName: t.d ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(t.d ? WTheme.good : WTheme.ink3)
                                Text(t.t.isEmpty ? "—" : t.t)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(t.d ? WTheme.ink3 : WTheme.ink)
                                    .strikethrough(t.d, color: WTheme.ink3)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // 오른쪽: 완료율 도넛 + 순공시간(숫자)
            VStack(spacing: 8) {
                WRing(percent: entry.planner.achievement)
                VStack(spacing: 2) {
                    Text("순공시간").font(.system(size: 10.5, weight: .bold)).foregroundStyle(WTheme.ink3)
                    Text(entry.planner.netMin.map { WG.minToHM($0) } ?? "0분")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(WTheme.ink2).minimumScaleFactor(0.6).lineLimit(1)
                }
            }
            .frame(width: 92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WTheme.paper, for: .widget)
    }
}

struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScheduleWidget", provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("오늘의 스케줄")
        .description("오늘의 계획 3가지와 순공시간을 보여줘요.")
        .supportedFamilies([.systemMedium])
    }
}
