import SwiftUI

// ─────────────────────────────────────────────────────────────
//  AuthView.swift — 첫 화면 (타이핑 로고 → 시작하기 → 이메일 → 비밀번호)
//  + VerifyView (이메일 인증 안내)
// ─────────────────────────────────────────────────────────────

struct AuthView: View {
    @EnvironmentObject var auth: AuthStore
    enum Stage { case intro, signup, login }
    @State private var stage: Stage = .intro
    @State private var typed = ""
    @State private var ready = false        // 타이핑 끝 → 버튼 등장
    @State private var typedCatchphrase = ""
    @State private var email = ""
    @State private var pw = ""
    @FocusState private var focus: F?
    enum F { case email, pw }

    private let logo = "Fromise"
    private let catchphrase = "지금 이 자리에서부터\n함께할 그날까지"
    private var emailValid: Bool { let e = email.trimmingCharacters(in: .whitespaces); return e.contains("@") && e.contains(".") }
    private var showPw: Bool { stage == .login || emailValid }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            logoBlock
            Spacer()
            Group {
                if stage == .intro {
                    VStack(spacing: 12) { startButton; browseButton }
                } else { formBlock }
            }
            Spacer().frame(height: 36)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .task { await runTyping() }
        .animation(.easeInOut(duration: 0.35), value: stage)
        .animation(.easeInOut(duration: 0.35), value: showPw)
    }

    // 타이핑 로고 +
    private var logoBlock: some View {
        VStack(spacing: 8) { // 요소 간격 조절
            // 1. 메인 로고
            HStack(spacing: 2) {
                Text(typed).font(.system(size: 46, weight: .heavy)).foregroundStyle(Theme.ink)
                Rectangle().fill(Theme.ink).frame(width: 3, height: 40)
                    .opacity(ready ? 0 : 1)
            }
            
            // 2. 캐치프레이즈 (보다 약간 큰 16pt 적용, 가운데 정렬)
            if !typedCatchphrase.isEmpty {
                Text(typedCatchphrase)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink) // 필요에 따라 Theme.ink2 등으로 변경
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 4)
            }
            
            // 3. ver 라벨
            Text("Powered by 대수능.com")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink3)
                .opacity(ready ? 1 : 0)
                .padding(.top, 4)
        }
    }
    private func runTyping() async {
        guard typed.isEmpty else { return }
        
        // 1. "Fromise" 로고 타이핑
        for ch in logo {
            typed.append(ch)
            try? await Task.sleep(nanoseconds: 130_000_000) // 0.13초 간격
        }
        
        try? await Task.sleep(nanoseconds: 200_000_000) // 로고 타이핑 후 잠시 대기
        
        // 2. 캐치프레이즈 타이핑 (빠르게 입력)
        for ch in catchphrase {
            typedCatchphrase.append(ch)
            try? await Task.sleep(nanoseconds: 40_000_000) // 0.04초 간격으로 매우 빠르게
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000) // 캐치프레이즈 완성 후 잠시 대기
        
        // 3. 페이드 인 & 로고 커서 숨김
        withAnimation(.easeOut(duration: 0.6)) {
            ready = true
        }
    }

    // 시작하기
    private var startButton: some View {
        Button {
            withAnimation { stage = .signup }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .email }
        } label: {
            Text("시작하기").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 17)
                .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .opacity(ready ? 1 : 0).offset(y: ready ? 0 : 14)
    }

    // 로그인 없이 둘러보기 (Apple 심사: 비로그인 탐색 허용)
    private var browseButton: some View {
        Button { auth.browseAsGuest() } label: {
            Text("로그인 없이 둘러보기")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .opacity(ready ? 1 : 0).offset(y: ready ? 0 : 14)
    }

    // 이메일 → 비밀번호 폼
    private var formBlock: some View {
        VStack(spacing: 12) {
            inputField("이메일", text: $email, field: .email, secure: false, keyboard: .emailAddress)

            if showPw {
                inputField("비밀번호", text: $pw, field: .pw, secure: true, keyboard: .default)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                if stage == .signup { pwRules.transition(.opacity) }
            }

            if !auth.errorMessage.isEmpty {
                Text(auth.errorMessage).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.danger).frame(maxWidth: .infinity, alignment: .leading)
            }

            submitButton

            Button {
                withAnimation { stage = (stage == .signup) ? .login : .signup }
                auth.errorMessage = ""
            } label: {
                HStack(spacing: 4) {
                    Text(stage == .signup ? "이미 계정이 있다면" : "계정이 없다면").foregroundStyle(Theme.ink3)
                    Text(stage == .signup ? "로그인" : "회원가입").foregroundStyle(Theme.ink).bold()
                }
                .font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.top, 2)
        }
    }

    private var submitButton: some View {
        let canSubmit = stage == .signup ? (emailValid && pwValid) : (emailValid && !pw.isEmpty)
        return Button {
            focus = nil
            Task {
                if stage == .signup { await auth.signUp(email: email, password: pw) }
                else { await auth.login(email: email, password: pw) }
            }
        } label: {
            Group {
                if auth.busy { ProgressView().tint(.white) }
                else { Text(stage == .signup ? "가입하기" : "로그인").font(.system(size: 16, weight: .heavy)) }
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(canSubmit ? Theme.ink : Theme.ink.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(!canSubmit || auth.busy)
        .padding(.top, 4)
    }

    // 비밀번호 규칙
    private func pwChecks(_ p: String) -> (len: Bool, up: Bool, num: Bool, sp: Bool) {
        (p.count >= 8,
         p.contains { $0.isUppercase },
         p.contains { $0.isNumber },
         p.contains { "!@#$%^&*()_-+=[]{};:,.<>?/~".contains($0) })
    }
    private var pwValid: Bool { let c = pwChecks(pw); return c.len && c.up && c.num && c.sp }
    private var pwRules: some View {
        let c = pwChecks(pw)
        return HStack(spacing: 10) {
            ruleChip("8자+", c.len); ruleChip("대문자", c.up); ruleChip("숫자", c.num); ruleChip("특수문자", c.sp)
            Spacer()
        }
    }
    private func ruleChip(_ t: String, _ ok: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
            Text(t)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(ok ? Theme.good : Theme.ink3)
    }

    private func inputField(_ placeholder: String, text: Binding<String>, field: F,
                            secure: Bool, keyboard: UIKeyboardType) -> some View {
        Group {
            if secure { SecureField(placeholder, text: text).focused($focus, equals: field) }
            else { TextField(placeholder, text: text).keyboardType(keyboard).textInputAutocapitalization(.never).focused($focus, equals: field) }
        }
        .font(.system(size: 15, weight: .semibold)).autocorrectionDisabled()
        .padding(14)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(focus == field ? Theme.ink : Theme.line, lineWidth: focus == field ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: focus)
    }
}

// MARK: - 이메일 인증 안내
struct VerifyView: View {
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "envelope.badge")
                .font(.system(size: 44, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(width: 92, height: 92).background(Theme.hlCheese.opacity(0.5)).clipShape(Circle())

            Text("\(auth.pendingEmail) 로\n인증 링크를 보냈어요.")
                .font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center).lineSpacing(3).padding(.top, 22)
            
            Text("메일이 도착하지 않는다면 스팸함을 확인해주세요.")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink2).padding(.top, 16)

            if !auth.errorMessage.isEmpty {
                Text(auth.errorMessage).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.danger).multilineTextAlignment(.center).padding(.top, 14)
            }
            Spacer()
            Button { Task { await auth.continueAfterVerification() } } label: {
                Group {
                    if auth.busy { ProgressView().tint(.white) }
                    else { Text("인증을 마쳤어요").font(.system(size: 16, weight: .heavy)) }
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(auth.busy)
            Button("다른 이메일로 다시 시작") { Task { await auth.signOut() } }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3).padding(.top, 14)
            Spacer().frame(height: 36)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}
