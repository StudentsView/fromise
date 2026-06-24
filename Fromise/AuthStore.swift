import SwiftUI
import Combine
import Supabase

// ─────────────────────────────────────────────────────────────
//  AuthStore.swift — Supabase 인증
//  흐름: signedOut → (회원가입) verifying(메일 인증) → signedIn
//        또는 (로그인) → signedIn
//  ※ supabase-swift 버전에 따라 일부 함수명이 다를 수 있어요.
// ─────────────────────────────────────────────────────────────

@MainActor
final class AuthStore: ObservableObject {
    enum Phase: Equatable { case signedOut, verifying, signedIn }

    @Published var phase: Phase = .signedOut
    @Published var errorMessage = ""
    @Published var busy = false
    @Published var pendingEmail = ""
    private var pendingPassword = ""

    init() {
        if supabase.auth.currentSession != nil { phase = .signedIn }
    }

    // 회원가입 → 이메일 인증 대기
    func signUp(email: String, password: String) async {
        busy = true; errorMessage = ""
        do {
            let res = try await supabase.auth.signUp(email: email, password: password)
            pendingEmail = email; pendingPassword = password
            phase = (res.session != nil) ? .signedIn : .verifying
        } catch { errorMessage = friendly(error) }
        busy = false
    }

    // 인증 메일 클릭 후 "계속하기" — 로그인 재시도로 세션 확보
    func continueAfterVerification() async {
        busy = true; errorMessage = ""
        do {
            _ = try await supabase.auth.signIn(email: pendingEmail, password: pendingPassword)
            phase = .signedIn
        } catch {
            errorMessage = "아직 인증 전이에요. 메일의 링크를 누른 뒤 다시 눌러주세요."
        }
        busy = false
    }

    // 로그인
    func login(email: String, password: String) async {
        busy = true; errorMessage = ""
        do {
            _ = try await supabase.auth.signIn(email: email, password: password)
            phase = .signedIn
        } catch { errorMessage = friendly(error) }
        busy = false
    }

    func signOut() async {
        try? await supabase.auth.signOut()
        pendingEmail = ""; pendingPassword = ""; errorMessage = ""
        phase = .signedOut
    }

    // 닉네임·생년월일·목표일을 계정 메타데이터에 저장
    func saveProfile(nickname: String, birth: Date, exam: Date) async {
        let iso = ISO8601DateFormatter()
        _ = try? await supabase.auth.update(user: UserAttributes(data: [
            "nickname": .string(nickname),
            "birth": .string(iso.string(from: birth)),
            "exam": .string(iso.string(from: exam)),
        ]))
    }

    // 닉네임만 Supabase user_metadata에 반영(병합)
    func updateNickname(_ nickname: String) async -> Bool {
        do {
            try await supabase.auth.update(user: UserAttributes(data: ["nickname": .string(nickname)]))
            return true
        } catch { return false }
    }

    // 설정에서 생일을 1회 수정했는지(가입 시 입력과 별개)
    var birthLocked: Bool {
        guard let md = supabase.auth.currentUser?.userMetadata else { return false }
        if case .bool(true)? = md["birth_edited"] { return true }
        return false
    }
    func setBirthOnce(_ date: Date) async -> Bool {
        if birthLocked { return true }
        let iso = ISO8601DateFormatter()
        do {
            try await supabase.auth.update(user: UserAttributes(data: [
                "birth": .string(iso.string(from: date)),
                "birth_edited": .bool(true)
            ]))
            return true
        } catch { return false }
    }

    // 현재 로그인한 계정 이메일
    var email: String { supabase.auth.currentUser?.email ?? pendingEmail }

    // 계정 메타데이터에서 닉네임/생년월일/목표일 읽기
    func currentMeta() -> (nickname: String?, birth: Date?, exam: Date?) {
        guard let md = supabase.auth.currentUser?.userMetadata else { return (nil, nil, nil) }
        let iso = ISO8601DateFormatter()
        func str(_ k: String) -> String? { if case let .string(v)? = md[k] { return v }; return nil }
        return (str("nickname"),
                str("birth").flatMap { iso.date(from: $0) },
                str("exam").flatMap { iso.date(from: $0) })
    }

    // 비밀번호 변경
    func changePassword(_ newPassword: String) async -> String? {
        do {
            try await supabase.auth.update(user: UserAttributes(password: newPassword))
            return nil
        } catch { return friendly(error) }
    }

    // 회원탈퇴 — 웹과 동일하게 Edge Function(delete-user) 호출
    func deleteAccount() async -> String? {
        do {
            let token = try await supabase.auth.session.accessToken
            var req = URLRequest(url: URL(string: "https://qrzzhabqwqyluzisrewl.supabase.co/functions/v1/delete-user")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return "탈퇴 처리에 실패했어요. 잠시 후 다시 시도해 주세요."
            }
            try? await supabase.auth.signOut()
            phase = .signedOut
            return nil
        } catch {
            return "탈퇴 처리에 실패했어요. 다시 로그인 후 시도해 주세요."
        }
    }

    // 탈퇴/민감작업 전 비밀번호 확인 (재로그인으로 검증)
    func verifyPassword(_ password: String) async -> Bool {
        do { _ = try await supabase.auth.signIn(email: email, password: password); return true }
        catch { return false }
    }

    private func friendly(_ e: Error) -> String {
        let m = e.localizedDescription.lowercased()
        if m.contains("already") || m.contains("registered") { return "이미 가입된 이메일이에요. 로그인해 주세요." }
        if m.contains("invalid") && m.contains("credential") { return "이메일 또는 비밀번호가 올바르지 않아요." }
        if m.contains("invalid login") { return "이메일 또는 비밀번호가 올바르지 않아요." }
        if m.contains("not confirmed") || m.contains("confirm") { return "이메일 인증이 필요해요. 메일의 링크를 눌러주세요." }
        if m.contains("network") || m.contains("offline") { return "네트워크 연결을 확인해 주세요." }
        return "처리 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요."
    }
}
