import SwiftUI

// ─────────────────────────────────────────────────────────────
//  DDayEditView.swift — D-Day 이름·날짜 편집 + 재수 토글
//  설정 ▸ D-Day(>) 에서 진입.
// ─────────────────────────────────────────────────────────────

struct DDayEditView: View {
    @EnvironmentObject var profile: ProfileStore
    @State private var name = ""
    @State private var date = ProfileStore.defaultExam

    private func dday(_ d: Date) -> String {
        let cal = Calendar.current
        let n = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        return n > 0 ? "D-\(n)" : n == 0 ? "D-DAY" : "D+\(-n)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 미리보기
                VStack(spacing: 4) {
                    Text(name.isEmpty ? "D-Day" : name)
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink2)
                    Text(dday(date))
                        .font(.system(size: 40, weight: .heavy)).foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                }
                .padding(.vertical, 22).frame(maxWidth: .infinity)
                .background(Theme.hlCheese.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .animation(.easeInOut(duration: 0.3), value: date)

                // 이름
                VStack(alignment: .leading, spacing: 8) {
                    Text("D-Day 이름").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink3)
                    TextField("예: 2027 수능", text: $name)
                        .font(.system(size: 16, weight: .bold))
                        .padding(13).background(Theme.paper)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: name) { profile.examName = $1 }
                }
                .card()

                // 날짜
                VStack(alignment: .leading, spacing: 8) {
                    Text("목표일").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink3)
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.compact).labelsHidden()
                        .environment(\.locale, Locale(identifier: "ko_KR"))
                        .onChange(of: date) { profile.examDate = $1 }

                    // 재수 토글
                    HStack(spacing: 8) {
                        if profile.isReexam {
                            Text("올해 수능에 최선을 다 해보겠습니다!")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
                            Button("클릭") { setExam(ProfileStore.defaultExam, "2027 수능") }
                                .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                        } else {
                            Text("재수가 확정되었습니까?")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
                            Button("여기를 클릭") { setExam(ProfileStore.reexamDate, "2028 수능") }
                                .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                        }
                        Spacer()
                    }
                    .padding(.top, 6)
                }
                .card()

                Spacer()
            }
            .padding(18)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("D-Day 설정")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = profile.examName; date = profile.targetExam }
    }

    private func setExam(_ d: Date, _ nm: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            date = d; name = nm
            profile.examDate = d; profile.examName = nm
        }
    }
}
