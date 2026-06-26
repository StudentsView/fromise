import SwiftUI
import Combine
import Supabase
import AuthenticationServices
import CryptoKit
import Security

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
    @Published var email = ""              // 화면 표시용 — 항상 최신 세션의 이메일
    @Published var guest = false           // 비로그인 '둘러보기' 모드
    @Published var isAppleOnlyAccount = false  // Apple로만 가입된 계정(비밀번호 없음) → 비번 변경 숨김 등
    private var pendingPassword = ""
    private var authTask: Task<Void, Never>?
    private let versionKey = "fromise_last_build_version"

    init() {
        // 동기적으로 즉시 알 수 있는 값 먼저 채움(깜빡임 방지)
        if let s = supabase.auth.currentSession {
            phase = .signedIn
            email = s.user.email ?? ""
            refreshAccountKind()
        }
        observeAuthState()
        Task { await bootstrap() }
    }

    deinit { authTask?.cancel() }

    // 앱 시작 시: 업데이트면 재인증, 아니면 일반 세션 복원
    private func bootstrap() async {
        if consumeVersionChange() {
            await reauthenticateAfterUpdate()
        } else {
            await restoreSession()
        }
    }

    /// 저장된 세션을 비동기로 정확히 복원(만료 시 자동 토큰 갱신).
    /// 앱 업데이트 직후 currentUser가 아직 메모리에 올라오지 않아
    /// 이메일이 '—'로 보이던 문제를 해결.
    func restoreSession() async {
        do {
            let session = try await supabase.auth.session   // 만료 시 자동 refresh
            email = session.user.email ?? email
            refreshAccountKind()
            phase = .signedIn
        } catch {
            // 세션이 없거나 갱신 실패 → 깨끗하게 로그아웃 상태로
            if phase == .signedIn { await signOut() } else { phase = .signedOut }
        }
    }

    /// 업데이트 직후: 저장된 세션의 토큰을 강제 갱신해 사용자 정보를 새로 받아옴.
    /// 갱신이 안 되면 자동 로그아웃하여 재로그인을 유도.
    private func reauthenticateAfterUpdate() async {
        guard supabase.auth.currentSession != nil else { phase = .signedOut; return }
        do {
            let session = try await supabase.auth.refreshSession()
            email = session.user.email ?? ""
            refreshAccountKind()
            phase = .signedIn
            if email.isEmpty { await signOut() }   // 그래도 비면 깨끗이 로그아웃
        } catch {
            await signOut()
        }
    }

    /// 빌드 버전이 바뀌었는지(=업데이트) 확인하고 기록. 최초 설치는 false.
    private func consumeVersionChange() -> Bool {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        let tag = "\(v)(\(b))"
        let last = UserDefaults.standard.string(forKey: versionKey)
        UserDefaults.standard.set(tag, forKey: versionKey)
        return last != nil && last != tag   // 이전 기록이 있고 달라졌을 때만 = 업데이트
    }

    // 세션 변화를 구독해 이메일/단계를 항상 동기화
    private func observeAuthState() {
        authTask = Task { [weak self] in
            for await change in supabase.auth.authStateChanges {
                guard let self else { return }
                switch change.event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let s = change.session {
                        self.email = s.user.email ?? self.email
                        self.guest = false
                        self.refreshAccountKind()
                        self.phase = .signedIn
                    }
                case .signedOut:
                    self.email = ""
                    self.isAppleOnlyAccount = false
                    self.phase = .signedOut
                default:
                    break
                }
            }
        }
    }

    // 회원가입 → 이메일 인증 대기
    func signUp(email: String, password: String) async {
        busy = true; errorMessage = ""
        do {
            let res = try await supabase.auth.signUp(email: email, password: password)
            // Supabase는 이메일 열거 공격 방지를 위해, 이미 가입된 이메일로 가입을 시도해도
            // 에러 대신 '신원(identities)이 빈' 가짜 유저를 돌려준다(인증 완료/미완료 무관).
            // → identities 가 비어 있으면 이미 존재하는 계정이므로 경고를 띄우고 중단.
            if res.session == nil, let ids = res.user.identities, ids.isEmpty {
                errorMessage = "이미 가입된 이메일이에요. 로그인해 주세요."
                busy = false
                return
            }
            pendingEmail = email; pendingPassword = password; self.email = email
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
            self.email = email
            phase = .signedIn
        } catch { errorMessage = friendly(error) }
        busy = false
    }

    func signOut() async {
        try? await supabase.auth.signOut()
        pendingEmail = ""; pendingPassword = ""; errorMessage = ""; email = ""
        isAppleOnlyAccount = false
        phase = .signedOut
    }

    // MARK: Apple로 로그인 (Supabase 네이티브 OIDC)
    //  재전송 공격 방지를 위해 nonce를 쓴다.
    //  · 해시(sha256)한 nonce → Apple 요청에 넣고
    //  · 원본 nonce → Supabase signInWithIdToken 에 넘긴다 (Supabase가 토큰의 nonce 해시와 대조).
    private var appleRawNonce: String?

    /// Apple 요청에 넣을 '해시된 nonce'를 돌려주고, 원본 nonce는 내부에 보관한다.
    /// (SignInWithAppleButton 의 request.nonce 에 대입)
    func makeAppleNonce() -> String {
        let raw = Self.randomNonceString()
        appleRawNonce = raw
        return Self.sha256(raw)
    }

    /// Apple 자격증명 + 보관해 둔 원본 nonce 로 Supabase 세션 생성.
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        busy = true; errorMessage = ""
        defer { busy = false }
        guard let rawNonce = appleRawNonce else {
            errorMessage = "로그인 정보를 다시 준비할게요. 한 번 더 눌러주세요."; return
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            errorMessage = "Apple 로그인 토큰을 받지 못했어요. 다시 시도해 주세요."; return
        }
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce))
            // Apple은 이메일을 최초 1회만 제공 → 세션 이메일(없으면 최초 제공분)로 채움.
            // 애플 아이디 자체가 이메일이라 이 값이 피드백 자동입력에도 그대로 쓰인다.
            self.email = session.user.email ?? credential.email ?? self.email
            self.guest = false
            refreshAccountKind()
            phase = .signedIn
        } catch {
            errorMessage = friendly(error)
        }
        appleRawNonce = nil
    }

    /// 암호학적으로 안전한 무작위 nonce 문자열
    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            if SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms) != errSecSuccess {
                // 실패 시에도 막히지 않도록 폴백(이론상 도달 거의 안 함)
                randoms = randoms.map { _ in UInt8.random(in: 0...255) }
            }
            for r in randoms where remaining > 0 {
                if r < charset.count { result.append(charset[Int(r)]); remaining -= 1 }
            }
        }
        return result
    }
    /// nonce의 SHA256 16진 문자열
    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // 비로그인 둘러보기 시작 (로그인 화면 대신 앱을 미리 탐색)
    func browseAsGuest() { guest = true }

    // 둘러보기 종료 → 로그인/회원가입 첫 화면으로 복귀
    func exitGuest() { guest = false; errorMessage = "" }

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
            email = ""
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

    /// 현재 계정이 'Apple 전용'(이메일/비밀번호 신원이 없음)인지 판별해 플래그 갱신.
    /// identities + app_metadata.providers/provider 를 모두 보고 판단.
    /// → Apple 전용이면 비밀번호가 없으므로 이메일+비밀번호 로그인은 애초에 불가하고(Supabase가 거부),
    ///   여기에 더해 비밀번호 변경 UI를 숨겨 비번이 생기지 않도록 한다.
    private func refreshAccountKind() {
        guard let user = supabase.auth.currentUser else { isAppleOnlyAccount = false; return }
        var provs = Set<String>()
        if let ids = user.identities { ids.forEach { provs.insert($0.provider) } }
        if case let .array(arr)? = user.appMetadata["providers"] {
            arr.forEach { if case let .string(s) = $0 { provs.insert(s) } }
        }
        if case let .string(p)? = user.appMetadata["provider"] { provs.insert(p) }
        isAppleOnlyAccount = provs.contains("apple") && !provs.contains("email")
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
