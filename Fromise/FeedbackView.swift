import SwiftUI
import PhotosUI
import Supabase

// ─────────────────────────────────────────────────────────────
//  FeedbackView.swift — 피드백 (하단 슬라이드) + 전송 서비스
//  · 회신 이메일 + 내용 + 사진 첨부
//  · Supabase Edge Function(send-feedback) → Resend로 자동 발송
//  · 메일 하단에 "답장 받을 이메일"이 더해져 발송됨(함수에서 처리)
// ─────────────────────────────────────────────────────────────

// 로컬 폴백 코드(게스트/오프라인 시) — 서버 코드가 우선
enum UserCode {
    static var current: String {
        let key = "fromise.userCode"
        if let c = UserDefaults.standard.string(forKey: key) { return c }
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let c = String((0..<5).map { _ in chars.randomElement()! })
        UserDefaults.standard.set(c, forKey: key)
        return c
    }
}

enum TicketCode {
    /// 폴백 티켓: yyyyMMdd + 로컬코드 + a (서버 연결 실패 시에만 사용)
    static func make(suffix: String = "a") -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date()) + UserCode.current + suffix
    }
}

enum TicketService {
    static let base    = "https://qrzzhabqwqyluzisrewl.supabase.co/functions/v1/"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFyenpoYWJxd3F5bHV6aXNyZXdsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDYyNjksImV4cCI6MjA5NjE4MjI2OX0.maOa6mMBxrRzvhX1475OwmLwwxyi4uiaCPx-_-c9d1Y"

    /// 로그인 시 사용자 토큰, 아니면 anon
    static func authHeader() async -> String {
        let token = try? await supabase.auth.session.accessToken
        return "Bearer \(token ?? anonKey)"
    }

    /// 서버에서 티켓 발급 (실패 시 로컬 폴백)
    static func next(kind: String) async -> String {
        guard let url = URL(string: base + "new-ticket") else { return TicketCode.make() }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(await authHeader(), forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["kind": kind])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["ticket"] as? String else { return TicketCode.make() }
        return t
    }
}

enum FeedbackService {
    /// nil = 성공, 그 외 = 실패 사유(화면에 표시)
    static func send(replyEmail: String, message: String, imageBase64: String?) async -> String? {
        guard let url = URL(string: TicketService.base + "send-feedback") else { return "주소 오류" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(await TicketService.authHeader(), forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "replyEmail": replyEmail,
            "message": message,
            "image": imageBase64 ?? ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if code == 200 { return nil }
            let detail = String(data: data, encoding: .utf8) ?? ""
            return "[\(code)] \(detail.prefix(300))"
        } catch {
            return "네트워크: \(error.localizedDescription)"
        }
    }
}

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultEmail: String
    @State private var email: String
    @State private var message = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var busy = false
    @State private var err = ""

    init(defaultEmail: String = "") {
        self.defaultEmail = defaultEmail
        _email = State(initialValue: defaultEmail)
    }

    private var valid: Bool {
        email.contains("@") && email.contains(".") &&
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("발견한 버그나 개선 의견을 보내주세요. 입력하신 메일로 답장드려요.")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink2)

                    field("답장 받을 이메일")
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 15, weight: .semibold)).padding(13)
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    field("내용")
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("무엇이든 자유롭게 적어주세요.")
                                .font(.system(size: 15, weight: .regular)).foregroundStyle(Theme.ink3)
                                .padding(.horizontal, 14).padding(.vertical, 14)
                        }
                        TextEditor(text: $message)
                            .font(.system(size: 15, weight: .regular))
                            .frame(minHeight: 130).padding(8).scrollContentBackground(.hidden)
                    }
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    field("사진 첨부 (선택)")
                    if let d = imageData, let ui = UIImage(data: d) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: ui).resizable().scaledToFill()
                                .frame(height: 160).frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button { imageData = nil; photoItem = nil } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 22))
                                    .foregroundStyle(.white).shadow(radius: 3).padding(8)
                            }.buttonStyle(.plain)
                        }
                    } else {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle").font(.system(size: 15, weight: .semibold))
                                Text("사진 선택").font(.system(size: 14, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(Theme.ink2)
                            .padding(.horizontal, 14).padding(.vertical, 13)
                            .background(Theme.paper)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    if !err.isEmpty {
                        Text(err).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.danger)
                    }

                    Button(action: submit) {
                        Group {
                            if busy { ProgressView().tint(.white) }
                            else { Text("보내기").font(.system(size: 16, weight: .heavy)) }
                        }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(valid ? Theme.ink : Theme.ink.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled(!valid || busy).padding(.top, 4)
                }
                .padding(18)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Fromise 피드백")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { if let d = try? await item.loadTransferable(type: Data.self) { imageData = d } }
        }
    }

    private func field(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink3)
    }

    private func submit() {
        busy = true; err = ""
        let b64 = imageData?.base64EncodedString()
        Task {
            let problem = await FeedbackService.send(replyEmail: email, message: message, imageBase64: b64)
            busy = false
            if let problem { err = problem } else { dismiss() }
        }
    }
}
