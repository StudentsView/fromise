import SwiftUI

// ─────────────────────────────────────────────────────────────
//  CalendarView.swift — 플래너 홈(월 달력) · 리디자인
//  박스 그리드 제거 → 여백 있는 한 장의 카드. 오늘=잉크 동그라미,
//  내용 있는 날=점, 공부시간=작은 캡션.
// ─────────────────────────────────────────────────────────────

struct PlannerHomeView: View {
    @EnvironmentObject var store: PlannerStore
    @State private var month = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                CalendarMonth(month: $month)
                    .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 26)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("플래너").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { key in
                DaySheetView(key: key).environmentObject(store)
            }
        }
        .onAppear { Task { await PlannerSync.load(into: store) } }
    }
}

struct CalendarMonth: View {
    @EnvironmentObject var store: PlannerStore
    @Binding var month: Date
    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let wd = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(spacing: 16) {
            header
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(wd[i]).font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(i == 0 ? Theme.danger : i == 6 ? Theme.hlSky : Theme.ink3)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 2)
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, key in
                        if key.isEmpty {
                            Color.clear.frame(height: 90)
                        } else {
                            NavigationLink(value: key) { dayCell(key) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.line, lineWidth: 1))
            .shadow(color: Theme.ink.opacity(0.05), radius: 14, y: 6)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 23, weight: .heavy)).foregroundStyle(Theme.ink)
            Spacer()
            Button { month = Date() } label: {
                Text("오늘").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .background(Theme.card)
                    .overlay(Capsule().stroke(Theme.line, lineWidth: 1)).clipShape(Capsule())
            }
            arrow(.back) { shift(-1) }
            arrow(.chevronRight) { shift(1) }
        }
    }

    private func arrow(_ icon: AppIcon, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Icon(icon, size: 14).foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.card)
                .overlay(Circle().stroke(Theme.line, lineWidth: 1)).clipShape(Circle())
        }
    }

    private func dayCell(_ key: String) -> some View {
        let d = PKey.date(key)
        let day = cal.component(.day, from: d)
        let dow = cal.component(.weekday, from: d) - 1
        let isToday = PKey.key(Date()) == key
        let net = store.day(key).netMinutes
        let has = store.hasContent(key)
        return VStack(spacing: 3) {
            ZStack {
                if isToday { Circle().fill(Theme.ink).frame(width: 30, height: 30) }
                Text("\(day)")
                    .font(.system(size: 14.5, weight: isToday ? .heavy : .semibold))
                    .foregroundStyle(isToday ? .white
                                     : (dow == 0 ? Theme.danger : dow == 6 ? Theme.hlSky : Theme.ink))
            }
            .frame(height: 30)
            Circle().fill(has ? Theme.good : .clear).frame(width: 5, height: 5)
            Text(net.map(netText) ?? " ")
                .font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.ink3)
        }
        .frame(maxWidth: .infinity).frame(height: 90)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func netText(_ m: Int) -> String { m % 60 == 0 ? "\(m/60)h" : "\(m/60):" + String(format: "%02d", m % 60) }

    private var cells: [String] {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let offset = cal.component(.weekday, from: first) - 1
        var out = Array(repeating: "", count: offset)
        for day in range {
            if let dd = cal.date(byAdding: .day, value: day - 1, to: first) { out.append(PKey.key(dd)) }
        }
        return out
    }

    private var title: String {
        let c = cal.dateComponents([.year, .month], from: month)
        return "\(c.year ?? 0)년 \(c.month ?? 0)월"
    }
    private func shift(_ n: Int) { if let m = cal.date(byAdding: .month, value: n, to: month) { month = m } }
}
