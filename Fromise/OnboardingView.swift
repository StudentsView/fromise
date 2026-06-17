import SwiftUI

// ─────────────────────────────────────────────────────────────
//  OnboardingView.swift — 회원가입 후 3단계
//  ① 닉네임  ② 생년월일  ③ D-Day  → 완료 시 메인
// ─────────────────────────────────────────────────────────────

struct OnboardingView: View {
    @EnvironmentObject var profile: ProfileStore

    @State private var step = 0
    @State private var nickname = ""
    @State private var birth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var exam = ProfileStore.defaultExam
    @FocusState private var nickFocus: Bool

    private var nickReady: Bool { !nickname.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // 진행 바
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i <= step ? Theme.ink : Theme.line)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 28).padding(.top, 22)
            .animation(.easeInOut(duration: 0.35), value: step)

            // 단계 (페이지 슬라이드)
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

    // ── 단계 1: 닉네임 ──
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

    // ── 단계 2: 생년월일 ──
    private var stepBirth: some View {
        stepShell(icon: "calendar", title: "생년월일을 알려주세요",
                  subtitle: "나중에 더 맞춤한 정보를 준비할게요.") {
            DatePicker("", selection: $birth, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden()
                .environment(\.locale, Locale(identifier: "ko_KR"))
        }
    }

    // ── 단계 3: D-Day ──
    private var stepDday: some View {
        stepShell(icon: "flag.checkered", title: "목표일을 정해요",
                  subtitle: "홈에서 남은 날을 매일 계산해 드릴게요.") {
            VStack(spacing: 18) {
                DatePicker("", selection: $exam, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden()
                    .environment(\.locale, Locale(identifier: "ko_KR"))
                VStack(spacing: 4) {
                    Text(ddayPreview)
                        .font(.system(size: 40, weight: .heavy)).foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text("남았어요").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink3)
                }
                .padding(.vertical, 18).frame(maxWidth: .infinity)
                .background(Theme.hlCheese.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .animation(.easeInOut(duration: 0.3), value: exam)
            }
        }
    }

    private var ddayPreview: String {
        let cal = Calendar.current
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: exam)).day ?? 0
        return n > 0 ? "D-\(n)" : n == 0 ? "D-DAY" : "D+\(-n)"
    }

    // ── 하단 버튼 ──
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
                    .contentTransition(.opacity)
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
        profile.nickname = nickname.trimmingCharacters(in: .whitespaces)
        profile.birthDate = birth
        profile.examDate = exam
        withAnimation(.easeInOut(duration: 0.45)) { profile.onboarded = true }   // RootFlow → 메인
    }

    // 단계 공용 레이아웃
    private func stepShell<C: View>(icon: String, title: String, subtitle: String,
                                    @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 22) {
            Spacer().frame(height: 6)
            Image(systemName: icon)
                .font(.system(size: 38, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(width: 80, height: 80)
                .background(Theme.hlCheese.opacity(0.5)).clipShape(Circle())
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
