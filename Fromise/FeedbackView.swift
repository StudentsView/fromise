import SwiftUI
import PhotosUI

// ─────────────────────────────────────────────────────────────
//  FeedbackView.swift — Beta 피드백 (하단 슬라이드) + 전송 서비스
//  · 회신 이메일 + 내용 + 사진 첨부
//  · Supabase Edge Function(send-feedback) → Resend로 자동 발송
//    feedback@daesuneung.com → support-beta@daesuneung.com
//  · 메일 하단에 "답장 받을 이메일"이 더해져 발송됨(함수에서 처리)
// ─────────────────────────────────────────────────────────────

// 사용자 코드(기기 영속) — 회원가입 시 서버 배정으로 교체 가능
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
    /// 예: 20260620 + 사용자코드 + a
    static func make(suffix: String = "a") -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date()) + UserCode.current + suffix
    }
}

enum FeedbackService {
    static let endpoint = "https://qrzzhabqwqyluzisrewl.supabase.co/functions/v1/send-feedback"
    static let anonKey  = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFyenpoYWJxd3F5bHV6aXNyZXdsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDYyNjksImV4cCI6MjA5NjE4MjI2OX0.maOa6mMBxrRzvhX1475OwmLwwxyi4uiaCPx-_-c9d1Y"

    static func send(replyEmail: String, message: String, imageBase64: String?, ticket: String) async -> Bool {
        guard let url = URL(string: endpoint) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "replyEmail": replyEmail,
            "message": message,
            "ticket": ticket,
            "image": imageBase64 ?? ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
}

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var message = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var busy = false
    @State private var err = ""

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
            .navigationTitle("Beta 피드백")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: photoItem) { item in
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
        let ticket = TicketCode.make()
        Task {
            let ok = await FeedbackService.send(replyEmail: email, message: message, imageBase64: b64, ticket: ticket)
            busy = false
            if ok { dismiss() } else { err = "전송에 실패했어요. 잠시 후 다시 시도해 주세요." }
        }
    }
}
