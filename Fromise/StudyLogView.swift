import SwiftUI
import UIKit
import FamilyControls

struct StudyLogView: View {
    @StateObject private var tracker = StudyTracker.shared
    @StateObject private var focus = FocusGuard.shared
    @StateObject private var two = TwoGStore.shared
    @EnvironmentObject private var profile: ProfileStore
    @State private var showHistory = false
    @State private var showFocusSetup = false

    private func hm(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h)시간 \(m)분" }
        if m > 0 { return "\(m)분 \(sec)초" }
        return "\(sec)초"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 오늘 총합
                    VStack(spacing: 6) {
                        Text("오늘 공부 시간").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink3)
                        Text(hm(tracker.todaySeconds))
                            .font(.system(size: 46, weight: .heavy, design: .rounded))
                            .monospacedDigit().foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24).card()

                    // 상태
                    HStack(spacing: 8) {
                        Circle().fill(statusColor).frame(width: 9, height: 9)
                        Text(statusText).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink2)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // 사용 방법 박스
                    usageBox

                    // 기록 확인 (안내사항과 시작 버튼 사이)
                    Button { showHistory = true } label: {
                        HStack(spacing: 8) {
                            Icon(.log, size: 16, weight: .bold)
                            Text("기록 확인").font(.system(size: 16, weight: .heavy))
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ink, lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // 시작 / 중단
                    if tracker.running {
                        Button { tracker.stopSession() } label: { big("공부 중단", Theme.danger) }.buttonStyle(.plain)
                    } else {
                        Button { tracker.startSession() } label: { big("공부 시작", Theme.ink) }.buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("학습 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFocusSetup = true } label: {
                        Image(systemName: focus.hasSelection ? "lock.shield.fill" : "lock.shield")
                            .foregroundStyle(two.active ? Theme.ink3 : Theme.ink)
                    }
                    .disabled(two.active)   // 2G 진행 중에는 스크린타임 설정 제한
                }
            }
            .sheet(isPresented: $showHistory) {
                StudyHistoryView(nickname: profile.displayName, tracker: tracker)
            }
            .sheet(isPresented: $showFocusSetup) {
                FocusSetupView(focus: focus)
            }
        }
    }

    // MARK: 사용 방법 박스
    private var usageBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Icon(.clock, size: 15, weight: .bold).foregroundStyle(Theme.ink)
                Text("사용 방법").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.ink)
            }
            usageRow("1", "스마트폰 화면이 바닥을 향하도록 엎어두세요.")
            usageRow("2", "기록 중에는 화면을 꺼 둘 예정이에요.")
            usageRow("3", "폰을 들어 올리거나 앱 밖으로 나가면 기록이 멈춰요.")
            usageRow("4", "오른쪽 위 버튼을 눌러 허용할 앱을 선택할 수 있어요.")
            usageRow("5", "공부 기록을 확인하거나 공유할 수 있어요.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).card(padding: 16, radius: 18)
    }
    private func usageRow(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink)
                .frame(width: 20, height: 20)
                .background(Theme.hlCheese).clipShape(Circle())
            Text(t)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var statusText: String {
        if !tracker.running { return "공부 시작을 눌러 주세요" }
        return tracker.counting ? "기록 중 — 휴대폰을 덮어둔 상태예요" : "일시정지 — 화면이 위를 향해 있어요"
    }
    private var statusColor: Color {
        if !tracker.running { return Theme.ink3 }
        return tracker.counting ? Theme.good : Theme.danger
    }
    private func big(_ t: String, _ bg: Color) -> some View {
        Text(t).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// ─────────────────────────────────────────────────────────────
//  기록 확인 — 일별 누적 집중시간 + 주간/월간 평균, 카드 공유 진입
// ─────────────────────────────────────────────────────────────
struct StudyHistoryView: View {
    let nickname: String
    @ObservedObject var tracker: StudyTracker
    @Environment(\.dismiss) private var dismiss
    @State private var shareDay: StudyTracker.DayStat?

    private func hm(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(m)분"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 평균 요약
                    HStack(spacing: 12) {
                        avgChip("주간 평균", tracker.weeklyAverage)
                        avgChip("월간 평균", tracker.monthlyAverage)
                    }

                    let days = tracker.dailyHistory(days: 30).filter { $0.seconds > 0 || $0.twoGSeconds > 0 }
                    if days.isEmpty {
                        Text("아직 기록된 집중 시간이 없어요.")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3)
                            .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(days.enumerated()), id: \.element.id) { idx, day in
                                Button { shareDay = day } label: { dayRow(day) }.buttonStyle(.plain)
                                if idx < days.count - 1 { Divider().background(Theme.line) }
                            }
                        }
                        .card(padding: 6, radius: 18)
                        Text("날짜를 누르면 자랑용 이미지를 만들 수 있어요.")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink3)
                    }
                }
                .padding(18)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("집중 시간 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .sheet(item: $shareDay) { day in
                StudyShareSheet(nickname: nickname, day: day)
            }
        }
    }

    private func avgChip(_ title: String, _ seconds: Int) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.ink3)
            Text(hm(seconds)).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).card(padding: 10, radius: 16)
    }

    private func dayRow(_ day: StudyTracker.DayStat) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayLabel(day.date)).font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(weekday(day.date)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(hm(day.seconds)).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink2)
                if day.twoGSeconds > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
                        Text("2G \(twoGText(day.twoGSeconds))").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Theme.ink3)
                }
            }
            Icon(.chevronRight, size: 12, weight: .bold).foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 12).padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func twoGText(_ s: Int) -> String {
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)일 \(h)시간" }
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(m)분"
    }
    private func dayLabel(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        return "\(c.month ?? 0)월 \(c.day ?? 0)일"
    }
    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "EEEE"
        return f.string(from: d)
    }
}

// ─────────────────────────────────────────────────────────────
//  공유 시트 — 1:1 카드 미리보기 + 사진 저장 / SNS 공유
// ─────────────────────────────────────────────────────────────
struct StudyShareSheet: View {
    let nickname: String
    let day: StudyTracker.DayStat
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

    private var card: StudyShareCard { StudyShareCard(nickname: nickname, date: day.date, seconds: day.seconds) }

    @MainActor private func render() -> UIImage? {
        let renderer = ImageRenderer(content: card.frame(width: 360, height: 360))
        renderer.scale = 3   // 360 × 3 = 1080 (1:1)
        return renderer.uiImage
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                card
                    .scaleEffect(320.0 / 360.0)
                    .frame(width: 320, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.line, lineWidth: 1))
                    .shadow(color: Theme.ink.opacity(0.10), radius: 16, y: 8)

                if let img = render() {
                    HStack(spacing: 12) {
                        Button {
                            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                            saved = true
                        } label: {
                            Label(saved ? "저장됨" : "사진에 저장", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                                .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(saved ? Theme.good : Theme.ink)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        ShareLink(item: Image(uiImage: img),
                                  preview: SharePreview("\(nickname)의 집중 시간", image: Image(uiImage: img))) {
                            Label("공유", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ink, lineWidth: 1.5))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("자랑하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

// ─────────────────────────────────────────────────────────────
//  StudyShareCard — SNS용 1:1 정사각 카드
// ─────────────────────────────────────────────────────────────
struct StudyShareCard: View {
    let nickname: String
    let date: Date
    let seconds: Int

    private var hms: String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    private var dateText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "yyyy년 M월 d일 (E)"
        return f.string(from: date)
    }

    var body: some View {
        ZStack {
            // 종이 배경
            LinearGradient(colors: [Theme.card, Theme.paper],
                           startPoint: .top, endPoint: .bottom)

            // 중앙 상단 + 정중앙 시간
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(dateText)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink3)
                    Text("\(nickname)의 집중 시간")
                        .font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink)
                }
                .padding(.top, 34)

                Spacer()

                Text(hms)
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .monospacedDigit().foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.horizontal, 16)

                Spacer()
            }

            // 우측 하단 — 로고 + 캐치프레이즈 + 앱 이름
            VStack(alignment: .trailing, spacing: 0) {
                Spacer()
                HStack(alignment: .bottom, spacing: 8) {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("지금 이 자리에서\n함께할 그날까지")
                            .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Theme.ink3)
                            .multilineTextAlignment(.trailing).lineSpacing(1)
                        Text("Fromise")
                            .font(.system(size: 14, weight: .black, design: .rounded)).foregroundStyle(Theme.ink)
                    }
                    AppLogoMark(size: 30)
                }
                .padding(.trailing, 18).padding(.bottom, 18)
            }
        }
        .frame(width: 360, height: 360)
    }
}

// 앱 아이콘(없으면 'F' 대체 마크)
struct AppLogoMark: View {
    var size: CGFloat
    var body: some View {
        Group {
            if let ui = Self.appIcon() {
                Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Theme.ink)
                    .overlay(
                        Text("F").font(.system(size: size * 0.6, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.paper)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
    static func appIcon() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }
}

// ─────────────────────────────────────────────────────────────
//  허용 앱·사이트 설정 — 권한 + FamilyActivityPicker (화이트리스트)
// ─────────────────────────────────────────────────────────────
struct FocusSetupView: View {
    @ObservedObject var focus: FocusGuard
    @StateObject private var two = TwoGStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pickerShown = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("여기서 고른 앱과 사이트만 사용할 수 있어요.")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !focus.authorized {
                        // 권한 요청
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 7) {
                                Image(systemName: "lock.shield").foregroundStyle(Theme.ink)
                                Text("스크린타임 권한이 필요해요").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.ink)
                            }
                            Text("스마트폰을 잠그려면 스크린타임 권한을 한 번 허용해 주세요.")
                                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { Task { await focus.requestAuthorization() } } label: {
                                Text("권한 허용").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                                    .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).card(padding: 16, radius: 18)
                    } else {
                        if two.active {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.danger)
                                Text("2G폰 모드가 진행 중이라 허용 목록을 바꿀 수 없어요. 모드가 끝난 뒤 수정해 주세요.")
                                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Theme.danger.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.danger.opacity(0.25), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        // 허용 목록 지정 (2G 진행 중에는 잠금)
                        Button { pickerShown = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: two.active ? "lock.fill" : "checklist")
                                Text("허용 앱·사이트 지정").font(.system(size: 16, weight: .heavy))
                                Spacer()
                                Icon(.chevronRight, size: 12, weight: .bold)
                            }
                            .foregroundStyle(two.active ? Theme.ink3 : Theme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 15)
                            .background(Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(two.active ? Theme.line : Theme.ink, lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(two.active)

                        // 현황
                        HStack(spacing: 12) {
                            countChip("허용 앱", focus.allowedAppCount)
                            countChip("허용 사이트", focus.allowedWebCount)
                        }

                        if !focus.hasSelection {
                            Text("허용 목록을 추가해주세요. 적어도 보호자와 연락은 해야 하잖아요!")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("허용 앱·사이트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .familyActivityPicker(isPresented: $pickerShown, selection: $focus.selection)
            .onAppear { focus.refreshAuthorization() }
        }
    }

    private func countChip(_ title: String, _ n: Int) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.ink3)
            Text("\(n)개").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).card(padding: 10, radius: 16)
    }
}
