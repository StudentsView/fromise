import WidgetKit
import SwiftUI

// 학습 기록 — 오늘 하루 누적 순공 시간
struct StudyEntry: TimelineEntry { let date: Date; let seconds: Int }

struct StudyProvider: TimelineProvider {
    func placeholder(in context: Context) -> StudyEntry { StudyEntry(date: Date(), seconds: 3 * 3600 + 12 * 60) }
    func getSnapshot(in context: Context, completion: @escaping (StudyEntry) -> Void) {
        completion(StudyEntry(date: Date(), seconds: WG.studySeconds()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        let entry = StudyEntry(date: Date(), seconds: WG.studySeconds())
        // 앱이 세션 변화 때마다 reload 해주지만, 자정 넘김 등 대비해 5분 폴백
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
    }
}

struct StudyWidgetView: View {
    var entry: StudyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill").font(.system(size: 13, weight: .bold))
                Text("학습 기록").font(.system(size: 13, weight: .heavy))
            }
            .foregroundStyle(WTheme.ink3)
            Spacer(minLength: 0)
            Text(WG.hm(entry.seconds))
                .font(.system(size: family == .systemSmall ? 26 : 34, weight: .heavy, design: .rounded))
                .foregroundStyle(WTheme.ink).minimumScaleFactor(0.6).lineLimit(1)
            Text("엎어두면 차곡차곡 쌓여요")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(WTheme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WTheme.paper, for: .widget)
    }
}

struct StudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StudyWidget", provider: StudyProvider()) { entry in
            StudyWidgetView(entry: entry)
        }
        .configurationDisplayName("오늘 순공시간")
        .description("오늘 하루 누적 학습 기록을 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
