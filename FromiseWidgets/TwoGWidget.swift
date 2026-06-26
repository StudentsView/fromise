import WidgetKit
import SwiftUI

// 2G폰 모드 — 활성 상태에서 지속시간 / 남은 시간
struct TwoGEntry: TimelineEntry { let date: Date; let twoG: WG.TwoG }

struct TwoGProvider: TimelineProvider {
    func placeholder(in context: Context) -> TwoGEntry {
        TwoGEntry(date: Date(), twoG: WG.TwoG(active: true,
                                              startedAt: Date().addingTimeInterval(-3600 * 5),
                                              endsAt: Date().addingTimeInterval(3600 * 19)))
    }
    func getSnapshot(in context: Context, completion: @escaping (TwoGEntry) -> Void) {
        completion(TwoGEntry(date: Date(), twoG: WG.twoG()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TwoGEntry>) -> Void) {
        let g = WG.twoG()
        guard g.active, let end = g.endsAt else {
            // 비활성: 15분마다 폴백 확인
            let e = TwoGEntry(date: Date(), twoG: g)
            completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(900))))
            return
        }
        // 활성: 1분 간격 60개 엔트리를 미리 만들어 앱을 깨우지 않고 분 단위로 갱신(.atEnd)
        var entries: [TwoGEntry] = []
        let start = Date()
        for i in 0..<60 {
            guard let d = Calendar.current.date(byAdding: .minute, value: i, to: start) else { continue }
            if d >= end {
                entries.append(TwoGEntry(date: d, twoG: WG.TwoG(active: false, startedAt: nil, endsAt: nil)))
                break
            }
            entries.append(TwoGEntry(date: d, twoG: g))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TwoGWidgetView: View {
    var entry: TwoGEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.twoG.active, let end = entry.twoG.endsAt {
            active(end: end)
        } else {
            inactive
        }
        // 위 두 분기 모두 동일 배경
    }

    private func active(end: Date) -> some View {
        let elapsed = entry.twoG.startedAt.map { entry.date.timeIntervalSince($0) } ?? 0
        let remaining = end.timeIntervalSince(entry.date)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold))
                Text("2G폰 모드 진행 중").font(.system(size: 13, weight: .heavy))
            }
            .foregroundStyle(WTheme.ink3)
            Spacer(minLength: 0)
            metric("남은 시간", WG.dhm(remaining), WTheme.ink)
            metric("지속 시간", WG.dhm(elapsed), WTheme.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WTheme.paper, for: .widget)
    }

    private var inactive: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.open.fill").font(.system(size: 13, weight: .bold))
                Text("2G폰 모드").font(.system(size: 13, weight: .heavy))
            }
            .foregroundStyle(WTheme.ink3)
            Spacer(minLength: 0)
            Text("꺼짐").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(WTheme.ink)
            Text("앱에서 켜면 남은 시간이 표시돼요")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(WTheme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(WTheme.paper, for: .widget)
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10.5, weight: .bold)).foregroundStyle(WTheme.ink3)
            Text(value).font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
        }
    }
}

struct TwoGWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TwoGWidget", provider: TwoGProvider()) { entry in
            TwoGWidgetView(entry: entry)
        }
        .configurationDisplayName("2G폰 모드")
        .description("2G폰 모드 지속 시간과 남은 시간을 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
