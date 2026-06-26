import SwiftUI

// ─────────────────────────────────────────────────────────────
//  AccountView.swift — 계정 관리 (비밀번호 변경 · 로그아웃 · 작별하기)
//  설정 ▸ 이메일 행(>)에서 진입.
// ─────────────────────────────────────────────────────────────

struct AccountView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var showPw = false
    @State private var confirmOut = false
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 이메일
                VStack(alignment: .leading, spacing: 10) {
                    Text("로그인 계정").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink3)
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink2).frame(width: 22)
                        Text(auth.email.isEmpty ? "—" : auth.email)
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                    }
                }
                .card()

                // 비밀번호 변경 — Apple로만 가입한 계정은 비밀번호가 없으므로 숨김
                if auth.isAppleOnlyAccount {
                    HStack(spacing: 12) {
                        Image(systemName: "applelogo").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink2).frame(width: 22)
                        Text("Apple로 로그인된 계정이에요").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink2)
                        Spacer()
                    }
                    .card()
                } else {
                    Button { showPw = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ink2).frame(width: 22)
                            Text("비밀번호 변경").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink3)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                }

                // 로그아웃
                Button { confirmOut = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 14, weight: .semibold))
                        Text("로그아웃").font(.system(size: 15, weight: .heavy))
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                // 작별하기 ("작별"만 탈퇴 트리거 · 부드러운 톤)
                HStack(spacing: 0) {
                    Text("Fromise와 ").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink3)
                    Button { showDelete = true } label: {
                        Text("작별").font(.system(size: 11.5, weight: .heavy)).foregroundStyle(Theme.ink2).underline()
                    }
                    .buttonStyle(.plain)
                    Text("하기").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            }
            .padding(18)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("계정 관리")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPw) { PasswordChangeSheet() }
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
        .alert("로그아웃 할까요?", isPresented: $confirmOut) {
            Button("취소", role: .cancel) {}
            Button("로그아웃", role: .destructive) { Task { await auth.signOut() } }
        } message: {
            Text("다시 로그인하면 정보가 그대로 복원돼요.")
        }
    }
}

// MARK: - 작별하기(회원탈퇴) 시트 — 하단 80% 슬라이드
struct DeleteAccountSheet: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var pw = ""
    @State private var confirmText = ""
    @State private var busy = false
    @State private var err = ""

    private let phrase = "Good Bye, Fromise"
    // Apple 전용 계정은 비밀번호가 없으므로 확인 문구만으로 탈퇴 가능
    private var canDelete: Bool { (auth.isAppleOnlyAccount || !pw.isEmpty) && confirmText == phrase }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 경고 (상단)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("정말 작별하시겠어요?")
                        }
                        .font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.danger)
                        Text("탈퇴하면 모든 학습 기록과 플래너가 영구 삭제되며, 계정과 데이터는 다시 복구할 수 없어요.")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // 비밀번호 — Apple 전용 계정은 비밀번호가 없으므로 생략
                    if !auth.isAppleOnlyAccount {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("현재 비밀번호").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink3)
                            SecureField("비밀번호", text: $pw)
                                .font(.system(size: 15, weight: .semibold)).autocorrectionDisabled()
                                .padding(13).background(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    // 확인 문구
                    VStack(alignment: .leading, spacing: 7) {
                        Text("확인 문구").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink3)
                        Text("아래 칸에 \(phrase) 를 그대로 입력해 주세요.")
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink2)
                        TextField(phrase, text: $confirmText)
                            .font(.system(size: 15, weight: .semibold)).autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(13).background(Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(confirmText == phrase ? Theme.good : Theme.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if !err.isEmpty {
                        Text(err).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.danger)
                    }
                }
                .padding(22)
            }

            // 하단 고정 확인 버튼
            Button(action: delete) {
                Group {
                    if busy { ProgressView().tint(.white) }
                    else { Text("탈퇴하기").font(.system(size: 16, weight: .heavy)) }
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(canDelete ? Theme.danger : Theme.danger.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canDelete || busy)
            .padding(.horizontal, 22).padding(.bottom, 18)
        }
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.fraction(0.8)])
        .presentationDragIndicator(.visible)
    }

    private func delete() {
        busy = true; err = ""
        Task {
            // 이메일 계정만 비밀번호 확인. Apple 전용 계정은 비밀번호가 없어 확인 문구로 대체.
            if !auth.isAppleOnlyAccount {
                let ok = await auth.verifyPassword(pw)
                if !ok { err = "비밀번호가 올바르지 않아요."; busy = false; return }
            }
            if let e = await auth.deleteAccount() { err = e; busy = false; return }
            // 성공 → auth.phase = .signedOut → RootFlow가 최초 화면으로 전환
            dismiss()
        }
    }
}

// MARK: - 비밀번호 변경 시트
struct PasswordChangeSheet: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var pw = ""
    @State private var confirm = ""
    @State private var err = ""
    @State private var busy = false

    private func checks(_ p: String) -> (len: Bool, up: Bool, num: Bool, sp: Bool) {
        (p.count >= 8, p.contains { $0.isUppercase }, p.contains { $0.isNumber },
         p.contains { "!@#$%^&*()_-+=[]{};:,.<>?/~".contains($0) })
    }
    private var valid: Bool { let c = checks(pw); return c.len && c.up && c.num && c.sp && pw == confirm }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("새 비밀번호").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                Text("대문자, 숫자, 특수문자 포함 8자 이상")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)

                field("새 비밀번호", $pw)
                field("새 비밀번호 확인", $confirm)

                let c = checks(pw)
                HStack(spacing: 10) {
                    chip("8자+", c.len); chip("대문자", c.up); chip("숫자", c.num); chip("특수문자", c.sp)
                    Spacer()
                }
                if !confirm.isEmpty && pw != confirm {
                    Text("비밀번호가 일치하지 않아요.").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.danger)
                }
                if !err.isEmpty {
                    Text(err).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.danger)
                }

                Button {
                    busy = true; err = ""
                    Task {
                        if let e = await auth.changePassword(pw) { err = e; busy = false }
                        else { dismiss() }
                    }
                } label: {
                    Group {
                        if busy { ProgressView().tint(.white) }
                        else { Text("변경하기").font(.system(size: 16, weight: .heavy)) }
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(valid ? Theme.ink : Theme.ink.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!valid || busy)
                Spacer()
            }
            .padding(22)
            .background(Theme.paper.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.height(420)])
    }

    private func field(_ ph: String, _ t: Binding<String>) -> some View {
        SecureField(ph, text: t)
            .font(.system(size: 15, weight: .semibold)).autocorrectionDisabled()
            .padding(13).background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func chip(_ t: String, _ ok: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
            Text(t)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(ok ? Theme.good : Theme.ink3)
    }
}
