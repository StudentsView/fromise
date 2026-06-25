import SwiftUI

// ─────────────────────────────────────────────────────────────
//  SettingsView.swift — 간단 설정 (계정 · 프로필)
//  로그아웃은 계정관리(AccountView) 안으로 이동.
// ─────────────────────────────────────────────────────────────

struct SettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var profile: ProfileStore
    @StateObject private var two = TwoGStore.shared
    @State private var showNick = false
    @State private var showFeedback = false
    @State private var showBirth = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 계정
                    card("계정") {
                        NavigationLink { AccountView() } label: {
                            row("이메일", value: auth.email.isEmpty ? "—" : auth.email, chevron: true)
                        }.buttonStyle(.plain)
                    }
                    // 프로필
                    card("프로필") {
                        Button { showNick = true } label: {
                            row("닉네임", value: profile.displayName, chevron: true)
                        }.buttonStyle(.plain)
                        divider
                        if auth.birthLocked {
                            row("생년월일", value: profile.birthDate.map(dateText) ?? "—")
                        } else {
                            Button { showBirth = true } label: {
                                row("생년월일", value: (profile.birthDate.map(dateText) ?? "설정"), chevron: true)
                            }.buttonStyle(.plain)
                        }
                        divider
                        NavigationLink { DDayEditView() } label: {
                            row("D-Day", value: "\(profile.examName) · \(profile.dDayText)", chevron: true)
                        }.buttonStyle(.plain)
                    }

                    // 집중
                    card("집중") {
                        NavigationLink { TwoGModeView() } label: {
                            row("2G폰 모드", value: two.active ? "진행 중" : "꺼짐", chevron: true)
                        }.buttonStyle(.plain)
                    }

                    // 지원
                    card("지원") {
                        Button { showFeedback = true } label: {
                            row("Fromise 피드백", value: "", chevron: true)
                        }.buttonStyle(.plain)
                        divider
                        Button { openInquiry() } label: {
                            row("문의하기", value: "support@fromise.com", chevron: true)
                        }.buttonStyle(.plain)
                    }

                    Text("지금 이 자리에서부터\n함께할 그날까지")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.ink3.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .padding(18)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showNick) { NicknameSheet() }
        .sheet(isPresented: $showFeedback) { FeedbackSheet(defaultEmail: auth.email) }
        .sheet(isPresented: $showBirth) { BirthEditSheet() }
    }

    private func openInquiry() {
        Task {
            let ticket = await TicketService.next(kind: "inquiry")
            let subject = "[대수능닷컴 문의] #\(ticket)"
            let enc = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
            if let url = URL(string: "mailto:support@fromise.com?subject=\(enc)") {
                await MainActor.run { openURL(url) }
            }
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ inner: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink3)
                .padding(.bottom, 10)
            VStack(spacing: 0) { inner() }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, value: String, chevron: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink2)
            Spacer()
            Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                .lineLimit(1).truncationMode(.tail)
            if chevron { Icon(.chevronRight, size: 12).foregroundStyle(Theme.ink3).padding(.leading, 4) }
        }
        .padding(.vertical, 11)
    }
    private var divider: some View { Rectangle().fill(Theme.line).frame(height: 1) }

    private func dateText(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)년 \(c.month ?? 0)월 \(c.day ?? 0)일"
    }
}

// 생년월일 1회 설정 시트 (저장 후 변경 불가)
struct BirthEditSheet: View {
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var date = Calendar.current.date(from: DateComponents(year: 2007, month: 1, day: 1)) ?? Date()
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("생년월일을 설정해주세요").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                    Text("생년월일은 1회만 수정 가능해요. 정확히 입력해주세요.")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.wheel).labelsHidden()
                        .frame(maxWidth: .infinity).frame(height: 200)   // 휠이 눌려 잘리지 않도록 높이 확보
                    if !err.isEmpty {
                        Text(err).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.danger)
                    }
                    Button(action: save) {
                        Group { if busy { ProgressView().tint(.white) } else { Text("저장") } }
                            .font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.plain).disabled(busy)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("생년월일").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        // iPad(정규 너비) 폼시트는 .medium이 휠을 잘라 → 더 큰 detent로 펼침
        .presentationDetents(hSize == .regular ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
    private func save() {
        if auth.birthLocked { err = "이미 설정된 생년월일이라 변경할 수 없어요."; return }
        profile.birthDate = date
        SyncQueue.shared.queueBirth(date)
        dismiss()
    }
}
