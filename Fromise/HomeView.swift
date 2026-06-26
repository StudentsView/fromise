import SwiftUI

// ─────────────────────────────────────────────────────────────
//  HomeView.swift — 플래너 중심 홈
//  ① 인사/날짜(닉네임)  ② D-day 히어로  ③ "오늘의 한 장"  ④ 도구 독
// ─────────────────────────────────────────────────────────────

struct HomeView: View {
    var guest: Bool = false
    var onOpen: (RootTabView.Tab) -> Void = { _ in }
    var onOpen2G: () -> Void = {}

    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var planner: PlannerStore
    @State private var showNick = false

    private var todayKey: String { PKey.key(Date()) }
    private var todayDateText: String {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        return "\(c.month ?? 0)월 \(c.day ?? 0)일"
    }
    private var todayDowText: String {
        let w = Calendar.current.component(.weekday, from: Date())
        return ["일", "월", "화", "수", "목", "금", "토"][w - 1] + "요일"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                DDayHero(name: profile.examName, text: profile.dDayText, sub: profile.examDateText)
                    .padding(.horizontal, 20).padding(.top, 14)

                sectionHeader(title: "오늘의 한 장", highlight: "한 장",
                              trailing: "전체 플래너") { onOpen(.planner) }
                TodayPlannerCard(dayKey: todayKey) { onOpen(.planner) }
                    .padding(.horizontal, 20)

                sectionHeader(title: "도구")
                ToolDock(onOpen: onOpen, onOpen2G: onOpen2G)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showNick) { NicknameSheet() }
        .task { await FocusGuard.shared.ensureAuthorization() }   // 메인 진입 시 스크린타임 권한 검사 → 없으면 요청
    }

    private var header: some View {
        Button { if !guest { showNick = true } } label: {   // 게스트는 닉네임 편집 차단(프로필 우회 방지)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text("오늘도 한 장, ").foregroundStyle(Theme.ink2)
                    Text(profile.displayName).foregroundStyle(Theme.ink).bold()
                    Text("님").foregroundStyle(Theme.ink2)
                    if !guest { Icon(.pen, size: 11).foregroundStyle(Theme.ink3).padding(.leading, 5) }
                }
                .font(.system(size: 15, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(todayDateText).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.ink)
                    Text(todayDowText).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink3)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22).padding(.top, 24)
    }

    private func sectionHeader(title: String, highlight: String? = nil,
                               trailing: String? = nil,
                               action: @escaping () -> Void = {}) -> some View {
        HStack {
            sectionTitle(title, highlight: highlight)
            Spacer()
            if let trailing {
                Button(action: action) {
                    HStack(spacing: 2) { Text(trailing); Icon(.chevronRight, size: 11) }
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink3)
                }
            }
        }
        .padding(.horizontal, 26).padding(.top, 26).padding(.bottom, 12)
    }

    @ViewBuilder
    private func sectionTitle(_ title: String, highlight: String?) -> some View {
        if let highlight, let r = title.range(of: highlight) {
            let pre = String(title[title.startIndex..<r.lowerBound])
            let post = String(title[r.upperBound...])
            HStack(spacing: 0) {
                Text(pre).font(.system(size: 18, weight: .heavy))
                HighlightText(text: highlight)
                Text(post).font(.system(size: 18, weight: .heavy))
            }
        } else {
            Text(title).font(.system(size: 18, weight: .heavy))
        }
    }
}

// MARK: - D-day 히어로
struct DDayHero: View {
    var name: String = "수능"
    let text: String
    let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(name)까지")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.62))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(text).font(.system(size: 56, weight: .heavy)).foregroundStyle(.white)
                Text("일 남음").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.hlCheese)
            }
            Text(sub).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.66))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            Theme.ink.overlay(alignment: .topTrailing) {
                Circle()
                    .fill(RadialGradient(colors: [Theme.hlCheese.opacity(0.22), .clear],
                                         center: .center, startRadius: 0, endRadius: 90))
                    .frame(width: 160, height: 160).offset(x: 40, y: -40)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.18), radius: 18, y: 10)
    }
}

// MARK: - 오늘의 한 장
struct TodayPlannerCard: View {
    @EnvironmentObject var store: PlannerStore
    let dayKey: String
    var open: () -> Void = {}

    private var day: DayData { store.day(dayKey) }
    private var realTasks: [PlannerTask] { day.tasks.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var doneCount: Int { realTasks.filter { $0.done }.count }
    private func mins(_ m: Int?) -> String {
        guard let m, m > 0 else { return "0" }
        return m % 60 == 0 ? "\(m/60)시간" : "\(m/60)시간 \(m%60)분"
    }
    private var subtitle: String {
        let a = day.achievement
        if realTasks.isEmpty { return "오늘 계획을 적어볼까요?" }
        if a >= 100 { return "오늘 목표 달성! 멋져요" }
        if a >= 50 { return "조금만 더 하면 오늘 목표 달성!" }
        return "오늘도 한 장, 시작해볼까요?"
    }
    private func toggle(_ task: PlannerTask) {
        var d = store.day(dayKey)
        if let i = d.tasks.firstIndex(where: { $0.id == task.id }) {
            d.tasks[i].done.toggle(); store.days[dayKey] = d
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ProgressRing(percent: day.achievement)
                VStack(alignment: .leading, spacing: 3) {
                    Text(realTasks.isEmpty ? "오늘 계획이 비어 있어요" : "오늘 계획 \(realTasks.count)개 중 \(doneCount)개 완료")
                        .font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink2)
                    HStack(spacing: 0) {
                        Text("공부 ").foregroundStyle(Theme.ink3)
                        Text(mins(day.netMinutes)).foregroundStyle(Theme.good).bold()
                        Text(" / 목표 \(mins(day.goalMinutes))").foregroundStyle(Theme.ink3)
                    }
                    .font(.system(size: 12.5, weight: .bold)).padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            if !realTasks.isEmpty {
                VStack(spacing: 9) {
                    ForEach(realTasks.prefix(3)) { task in
                        HStack(spacing: 10) {
                            Button { toggle(task) } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(task.done ? Theme.good : .clear)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(task.done ? Theme.good : Theme.line, lineWidth: 1.5))
                                        .frame(width: 22, height: 22)
                                    if task.done { Icon(.check, size: 11, weight: .bold).foregroundStyle(.white) }
                                }
                            }
                            .buttonStyle(.plain)
                            Text(task.text)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(task.done ? Theme.ink3 : Theme.ink)
                                .strikethrough(task.done, color: Theme.ink3)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture { open() }
    }
}

// MARK: - 달성률 링
struct ProgressRing: View {
    let percent: Int
    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 8)
            Circle().trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(Theme.good, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.55), value: percent)
            Text("\(percent)%").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.55), value: percent)
        }
        .frame(width: 64, height: 64)
    }
}

// MARK: - 도구 독
struct ToolDock: View {
    var onOpen: (RootTabView.Tab) -> Void = { _ in }
    var onOpen2G: () -> Void = {}
    // 시계(알람/타이머) 기능 — 코드는 그대로 두고 메인에서 잠시 비활성화.
    // 다시 켜려면 이 줄과 아래 smallTool(.clock ...) · .sheet(...AlarmTimerView()) 주석을 해제.
    // @State private var showClock = false

    var body: some View {
        VStack(spacing: 12) {
            Button { onOpen(.bell) } label: {
                HStack(spacing: 14) {
                    iconChip(.bell, bg: Theme.hlCheese)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("오늘 모의고사 모드").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.ink)
                        Text("실제 수능 시간표와 방송으로 실전 감각 유지")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink2)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    Text("켜기").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .background(Theme.paper)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .card(padding: 18, radius: 22)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                // 시계가 있던 자리에 2G폰 모드 배치 (시계는 비활성화) → 설정 탭의 2G폰 모드 화면으로 이동
                // smallTool(.clock, bg: Theme.hlSky, name: "시계", desc: "이어폰 알람과 타이머") { showClock = true }
                smallTool(.lock, bg: Theme.hlSky, name: "2G폰 모드", desc: "5G → 2G 다운그레이드") { onOpen2G() }
                smallTool(.log, bg: Theme.hlMint, name: "기록", desc: "스마트폰 미사용 시간 기록") { onOpen(.log) }
            }
        }
        // .sheet(isPresented: $showClock) { AlarmTimerView() }   // 시계 기능 비활성화(코드 유지)
    }

    private func smallTool(_ icon: AppIcon, bg: Color, name: String, desc: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                iconChip(icon, bg: bg)
                Text(name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(desc).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .card(padding: 18, radius: 22)
        }
        .buttonStyle(.plain)
    }

    private func iconChip(_ icon: AppIcon, bg: Color) -> some View {
        Icon(icon, size: 21).foregroundStyle(Theme.ink)
            .frame(width: 42, height: 42).background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
