import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────
//  ProfileStore.swift — 사용자 프로필(닉네임 · 생년월일 · 목표일)
//  기기(UserDefaults) 저장 + 로그인 시 Supabase user_metadata와 동기화.
// ─────────────────────────────────────────────────────────────

final class ProfileStore: ObservableObject {
    @Published var nickname: String { didSet { save() } }
    @Published var birthDate: Date? { didSet { save() } }
    @Published var examDate:  Date? { didSet { save() } }   // D-Day 목표일
    @Published var examName:  String { didSet { save() } }  // D-Day 이름 (예: "2027 수능")
    @Published var onboarded: Bool  { didSet { save() } }

    private let d = UserDefaults.standard
    init() {
        nickname  = d.string(forKey: "fromise_nickname") ?? ""
        onboarded = d.bool(forKey: "fromise_onboarded")
        birthDate = d.object(forKey: "fromise_birth") as? Date
        examDate  = d.object(forKey: "fromise_exam")  as? Date
        examName  = d.string(forKey: "fromise_examname") ?? "2027 수능"
    }
    private func save() {
        d.set(nickname,  forKey: "fromise_nickname")
        d.set(onboarded, forKey: "fromise_onboarded")
        d.set(birthDate, forKey: "fromise_birth")
        d.set(examDate,  forKey: "fromise_exam")
        d.set(examName,  forKey: "fromise_examname")
    }

    /// 로그인 시 Supabase 계정 메타데이터를 반영 (닉네임 있으면 온보딩 완료로 간주)
    func applyMetadata(nickname: String?, birth: Date?, exam: Date?) {
        if let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty {
            self.nickname = nickname
            self.birthDate = birth
            self.examDate = exam
            self.onboarded = true
        } else {
            reset()   // 새 계정 → 온보딩 필요
        }
    }
    /// 로그아웃 시 기기 데이터 초기화 (계정 간 정보 섞임 방지)
    func reset() {
        nickname = ""; birthDate = nil; examDate = nil; onboarded = false; examName = "2027 수능"
    }

    var displayName: String { let n = nickname.trimmingCharacters(in: .whitespaces); return n.isEmpty ? "수험생" : n }
    var hasNickname: Bool { !nickname.trimmingCharacters(in: .whitespaces).isEmpty }

    /// 기본 목표일 = 2027 수능(2027-11-19)
    static var defaultExam: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19)) ?? Date() }
    /// 재수 목표일 = 2028 수능(2027-11-18)
    static var reexamDate: Date { Calendar.current.date(from: DateComponents(year: 2027, month: 11, day: 18)) ?? Date() }
    var targetExam: Date { examDate ?? Self.defaultExam }
    /// 현재 목표일이 2028 수능(재수)인지
    var isReexam: Bool {
        let cal = Calendar.current
        return cal.isDate(targetExam, equalTo: Self.reexamDate, toGranularity: .day)
    }

    var dDay: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: targetExam)).day ?? 0
    }
    var dDayText: String { dDay > 0 ? "D-\(dDay)" : dDay == 0 ? "D-DAY" : "D+\(-dDay)" }
    var examDateText: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: targetExam)
        return "\(c.year ?? 0)년 \(c.month ?? 0)월 \(c.day ?? 0)일이 목표예요"
    }
}

// MARK: - 닉네임 편집 시트 (홈 인사말 탭 → 편집)
struct NicknameSheet: View {
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("어떻게 불러드릴까요?").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.ink)
                Text("홈 화면 인사말에 표시돼요. 언제든 바꿀 수 있어요.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
                TextField("닉네임", text: $draft)
                    .font(.system(size: 16, weight: .semibold)).padding(14)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .submitLabel(.done).onSubmit(save)
                Button(action: save) {
                    Text("저장").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(14)
                        .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Spacer()
            }
            .padding(22).background(Theme.paper.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .onAppear { draft = profile.nickname }
        .presentationDetents([.height(300)])
    }
    private func save() {
        let n = draft.trimmingCharacters(in: .whitespaces)
        profile.nickname = n
        SyncQueue.shared.queueNickname(n)
        dismiss()
    }
}
