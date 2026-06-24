import SwiftUI

// ─────────────────────────────────────────────────────────────
//  OnboardingView.swift — 인증 후 3단계 (모두 필수 입력)
//  ① 닉네임  ② 생년월일  ③ D-Day
//  · 2008년생 이상 → 목표일 2026-11-19 고정 + "nn년생의 수능은 mm일 남았습니다."
//  · 그 외        → 직접 목표일 설정
// ─────────────────────────────────────────────────────────────

struct OnboardingView: View {
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var auth: AuthStore

    @State private var step = 0
    @State private var nickname = ""
    @State private var birth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var exam = ProfileStore.defaultExam
    @FocusState private var nickFocus: Bool

    private var birthYear: Int { Calendar.current.component(.year, from: birth) }
    private var isSuneungCohort: Bool { birthYear <= 2008 }        // 2008년생 이하
    private var nickReady: Bool { !nickname.trimmingCharacters(in: .whitespaces).isEmpty }
    /// 최종 목표일: 2008년생 이상은 수능일 고정, 그 외는 직접 선택
    private var finalExam: Date { isSuneungCohort ? ProfileStore.defaultExam : exam }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i <= step ? Theme.ink : Theme.line).frame(height: 4)
                }
            }
            .padding(.horizontal, 28).padding(.top, 22)
            .animation(.easeInOut(duration: 0.35), value: step)

            TabView(selection: $step) {
                stepNickname.tag(0)
                stepBirth.tag(1)
                stepDday.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            navBar
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { nickFocus = true } }
    }

    // ① 닉네임
    private var stepNickname: some View {
        stepShell(icon: "person.fill", title: "어떻게 불러드릴까요?",
                  subtitle: "입력한 이름으로 인사해 드릴게요.") {
            VStack(spacing: 16) {
                TextField("닉네임", text: $nickname)
                    .focused($nickFocus)
                    .font(.system(size: 18, weight: .bold)).multilineTextAlignment(.center)
                    .padding(15).background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .submitLabel(.next).onSubmit { if nickReady { go(1) } }
                HStack(spacing: 0) {
                    Text("오늘도 한 장, ").foregroundStyle(Theme.ink2)
                    Text(nickReady ? nickname : "수험생").foregroundStyle(Theme.ink).bold()
                    Text("님").foregroundStyle(Theme.ink2)
                }
                .font(.system(size: 14, weight: .semibold))
            }
        }
    }

    // ② 생년월일 (필수 — 휠은 항상 값이 있음)
    private var stepBirth: some View {
        stepShell(icon: "calendar", title: "생년월일을 알려주세요",
                  subtitle: "수능까지 남은 날을 정확히 계산할게요.") {
            DatePicker("", selection: $birth, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden()
                .environment(\.locale, Locale(identifier: "ko_KR"))
        }
    }

    // ③ D-Day
    private var stepDday: some View {
        stepShell(icon: "flag.checkered", title: "목표일을 정해요",
                  subtitle: isSuneungCohort ? "언제든지 설정에서 변경하실 수 있어요." : "목표일을 직접 골라주세요.") {
            VStack(spacing: 16) {
                if isSuneungCohort {
                    VStack(spacing: 6) {
                        Text(suneungMessage)
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                        Text(dday(finalExam))
                            .font(.system(size: 44, weight: .heavy)).foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                    }
                    .padding(.vertical, 22).frame(maxWidth: .infinity)
                    .background(Theme.hlCheese.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    DatePicker("", selection: $exam, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden()
                        .environment(\.locale, Locale(identifier: "ko_KR"))
                    Text(dday(exam))
                        .font(.system(size: 36, weight: .heavy)).foregroundStyle(Theme.ink)
                        .contentTransition(.numericText()).animation(.easeInOut, value: exam)
                }
            }
        }
    }

    private var suneungMessage: String {
        let nn = String(format: "%02d", birthYear % 100)
        let n = daysUntil(finalExam)
        return "\(nn)년생의 수능은 \(max(n, 0))일 남았습니다"
    }
    private func daysUntil(_ d: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
    }
    private func dday(_ d: Date) -> String {
        let n = daysUntil(d)
        return n > 0 ? "D-\(n)" : n == 0 ? "D-DAY" : "D+\(-n)"
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button { go(step - 1) } label: {
                    Text("이전").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 96).padding(.vertical, 15)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            Button { step < 2 ? go(step + 1) : finish() } label: {
                Text(step < 2 ? "다음" : "시작하기")
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background((step == 0 && !nickReady) ? Theme.ink.opacity(0.35) : Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(step == 0 && !nickReady)
        }
        .padding(.horizontal, 28).padding(.bottom, 16).padding(.top, 4)
    }

    private func go(_ to: Int) {
        nickFocus = false
        withAnimation(.easeInOut(duration: 0.4)) { step = to }
    }
    private func finish() {
        let name = nickname.trimmingCharacters(in: .whitespaces)
        profile.nickname = name
        profile.birthDate = birth
        profile.examDate = finalExam
        Task { await auth.saveProfile(nickname: name, birth: birth, exam: finalExam) }
        withAnimation(.easeInOut(duration: 0.45)) { profile.onboarded = true }
    }

    private func stepShell<C: View>(icon: String, title: String, subtitle: String,
                                    @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 22) {
            Spacer().frame(height: 6)
            Image(systemName: icon)
                .font(.system(size: 38, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(width: 80, height: 80).background(Theme.hlCheese.opacity(0.5)).clipShape(Circle())
            VStack(spacing: 8) {
                Text(title).font(.system(size: 23, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink2)
            }
            .multilineTextAlignment(.center)
            content()
            Spacer()
        }
        .padding(.horizontal, 28).padding(.top, 20)
        .frame(maxWidth: .infinity)
    }
}
