import SwiftUI

// ─────────────────────────────────────────────────────────────
//  CalendarView.swift — 플래너 홈(월 달력). 날짜 탭 → 하루 한 장.
// ─────────────────────────────────────────────────────────────

struct PlannerHomeView: View {
    @EnvironmentObject var store: PlannerStore
    @State private var month: Date = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                CalendarMonth(month: $month)
                    .padding(16)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("플래너")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { key in
                DaySheetView(key: key).environmentObject(store)
            }
        }
    }
}

struct CalendarMonth: View {
    @EnvironmentObject var store: PlannerStore
    @Binding var month: Date
    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(spacing: 14) {
            nav
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdays[i])
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(i == 0 ? Theme.danger : i == 6 ? Theme.hlSky : Theme.ink3)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, key in
                    if key.isEmpty {
                        Color.clear.frame(height: 84)
                    } else {
                        NavigationLink(value: key) { cell(key) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var nav: some View {
        HStack(spacing: 14) {
            Button { shift(-1) } label: { Icon(.back, size: 16).foregroundStyle(Theme.ink) }
            Text(title).font(.system(size: 18, weight: .heavy)).frame(minWidth: 150)
            Button { shift(1) } label: { Icon(.chevronRight, size: 16).foregroundStyle(Theme.ink) }
            Button { month = Date() } label: {
                Text("오늘").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.card)
                    .overlay(Capsule().stroke(Theme.line, lineWidth: 1)).clipShape(Capsule())
            }
        }
    }

    private func cell(_ key: String) -> some View {
        let d = PKey.date(key)
        let day = cal.component(.day, from: d)
        let dow = cal.component(.weekday, from: d) - 1   // 0=일
        let isToday = PKey.key(Date()) == key
        let net = store.day(key).netMinutes
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(day)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(dow == 0 ? Theme.danger : dow == 6 ? Theme.hlSky : Theme.ink)
                Spacer(minLength: 0)
                if let net { Text(netText(net)).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.good) }
            }
            Spacer(minLength: 0)
            if store.hasContent(key) {
                Circle().fill(Theme.good).frame(width: 7, height: 7)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(Theme.card.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isToday ? Theme.ink : Theme.line, lineWidth: isToday ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func netText(_ m: Int) -> String { m % 60 == 0 ? "\(m/60)h" : "\(m/60):" + String(format: "%02d", m % 60) }

    // 빈칸("") + 날짜키 배열
    private var cells: [String] {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let offset = cal.component(.weekday, from: first) - 1
        var out = Array(repeating: "", count: offset)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: first) { out.append(PKey.key(d)) }
        }
        return out
    }

    private var title: String {
        let c = cal.dateComponents([.year, .month], from: month)
        return "\(c.year ?? 0)년 \(c.month ?? 0)월"
    }
    private func shift(_ n: Int) { if let m = cal.date(byAdding: .month, value: n, to: month) { month = m } }
}
