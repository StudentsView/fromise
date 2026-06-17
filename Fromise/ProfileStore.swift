import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────
//  ProfileStore.swift — 사용자 프로필(닉네임)
//  지금은 기기(UserDefaults)에 저장. Part 6에서 Supabase 회원가입 시
//  options.data.nickname → user_metadata 로 올리고, 로그인 시 내려받아 동기화.
// ─────────────────────────────────────────────────────────────

final class ProfileStore: ObservableObject {
    @Published var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: Self.key) }
    }

    private static let key = "fromise_nickname"

    init() {
        nickname = UserDefaults.standard.string(forKey: Self.key) ?? ""
    }

    /// 빈 닉네임이면 "수험생"으로 대체
    var displayName: String {
        let n = nickname.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "수험생" : n
    }
    var hasNickname: Bool { !nickname.trimmingCharacters(in: .whitespaces).isEmpty }
}

// MARK: - 닉네임 입력 시트
struct NicknameSheet: View {
    @EnvironmentObject var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("어떻게 불러드릴까요?")
                    .font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                Text("홈 화면 인사말에 표시돼요. 언제든 바꿀 수 있어요.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)

                TextField("닉네임 (예: 준)", text: $draft)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(14)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .submitLabel(.done)
                    .onSubmit(save)

                Button(action: save) {
                    Text("저장").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(14)
                        .background(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Spacer()
            }
            .padding(22)
            .background(Theme.paper.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .onAppear { draft = profile.nickname }
        .presentationDetents([.height(300)])
    }

    private func save() {
        profile.nickname = draft.trimmingCharacters(in: .whitespaces)
        dismiss()
    }
}
