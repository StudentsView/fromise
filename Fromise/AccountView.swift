import SwiftUI

// ─────────────────────────────────────────────────────────────
//  AccountView.swift — 계정 관리 (비밀번호 변경 · 회원탈퇴)
//  설정 ▸ 이메일 행(>)에서 진입.
// ─────────────────────────────────────────────────────────────

struct AccountView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var showPw = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteErr = ""

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

                // 비밀번호 변경
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

                if !deleteErr.isEmpty {
                    Text(deleteErr).font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.danger).frame(maxWidth: .infinity, alignment: .leading)
                }

                // 회원탈퇴
                Button { confirmDelete = true } label: {
                    HStack(spacing: 8) {
                        if deleting { ProgressView().tint(Theme.danger) }
                        else {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .semibold))
                            Text("회원탈퇴").font(.system(size: 15, weight: .heavy))
                        }
                    }
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.danger.opacity(0.45), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(deleting)
                .padding(.top, 6)

                Text("탈퇴하면 모든 학습 기록과 플래너가 영구 삭제되며 되돌릴 수 없어요.")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink3)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
            }
            .padding(18)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("계정 관리")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPw) { PasswordChangeSheet() }
        .alert("정말 탈퇴할까요?", isPresented: $confirmDelete) {
            Button("취소", role: .cancel) {}
            Button("탈퇴", role: .destructive) {
                deleting = true; deleteErr = ""
                Task {
                    if let e = await auth.deleteAccount() { deleteErr = e }
                    deleting = false
                }
            }
        } message: {
            Text("모든 학습 기록과 플래너가 영구 삭제되며 되돌릴 수 없어요.")
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
                Text("대문자·숫자·특수문자 포함 8자 이상")
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
