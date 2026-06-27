import SwiftUI

// ─────────────────────────────────────────────────────────────
//  TwoGModeView.swift — 2G폰 모드 설정/해제 화면
// ─────────────────────────────────────────────────────────────
struct TwoGModeView: View {
    @StateObject private var two = TwoGStore.shared
    @StateObject private var focus = FocusGuard.shared
    @State private var days = 1
    @State private var showFocusSetup = false
    @State private var confirmStart = false
    @State private var codeInput = ""
    @FocusState private var daysFocused: Bool

    private var delayHours: Int { two.unlockCount }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if two.active { activePane } else { setupPane }
            }
            .padding(18)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("2G폰 모드")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFocusSetup) { FocusSetupView(focus: focus) }
        .onAppear { two.restore(); Task { await two.syncFromCloud(); await two.loadStats() } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { daysFocused = false; days = min(365, max(1, days)) }
            }
        }
        .sheet(isPresented: $confirmStart) { confirmSheet }
    }

    // 2G폰 모드 시작 확인 — 하단에서 올라오는 자체 슬라이드 시트
    private var confirmSheet: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 34)).foregroundStyle(Theme.ink)
                .padding(.top, 18)
            Text("2G폰 모드를 시작할까요?")
                .font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.ink)
            Text("시작하면 \(days)일 동안 허용된 앱·사이트 외에는 사용할 수 없어요."
                 + (delayHours > 0 ? " 지금까지 \(delayHours)회 해제해서, 메일 코드는 요청 후 약 \(delayHours)시간 뒤에 도착해요." : ""))
                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    confirmStart = false
                    Task { await two.activate(days: days) }
                } label: {
                    Text("\(days)일 동안 시작")
                        .font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { confirmStart = false } label: {
                    Text("취소")
                        .font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
    }

    // MARK: 설정(비활성)
    private var setupPane: some View {
        VStack(spacing: 16) {
            infoBox
            delayNoticeBox

            // 허용 앱·사이트
            Button { showFocusSetup = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: focus.hasSelection ? "checkmark.shield.fill" : "lock.shield")
                    Text("허용 앱·사이트 지정").font(.system(size: 16, weight: .heavy))
                    Spacer()
                    Text(focus.hasSelection ? "앱 \(focus.allowedAppCount) · 웹 \(focus.allowedWebCount)" : "필요")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink3)
                    Icon(.chevronRight, size: 12, weight: .bold)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 15)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            // 기간 (스테퍼 + 직접 입력)
            VStack(alignment: .leading, spacing: 10) {
                Text("기간").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink3)
                HStack(spacing: 4) {
                    TextField("1", value: $days, format: .number)
                        .keyboardType(.numberPad)
                        .focused($daysFocused)
                        .fixedSize()
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .onChange(of: days) { _, v in if v > 365 { days = 365 } }
                    Text("일").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    if !daysFocused {
                        Image(systemName: "pencil").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    Stepper("", value: $days, in: 1...365).labelsHidden()
                }
                Text("숫자를 눌러 직접 입력할 수 있어요.")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).card(padding: 16, radius: 18)

            if let err = two.lastError {
                Text(err).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button { daysFocused = false; confirmStart = true } label: {
                Group { if two.busy { ProgressView().tint(.white) } else { Text("2G폰 모드 시작") } }
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(focus.hasSelection ? Theme.ink : Theme.ink3)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(two.busy || !focus.hasSelection)
        }
    }

    // MARK: 활성
    private var activePane: some View {
        VStack(spacing: 16) {
            // 남은 시간 카운트다운
            VStack(spacing: 6) {
                Text("2G폰 모드 진행 중").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink3)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(fmtRemain(two.remaining))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit().foregroundStyle(Theme.ink)
                }
                Text("시간이 끝나면 자동으로 해제돼요.").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 22).card()

            // 해제 안내
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "envelope.fill").foregroundStyle(Theme.ink)
                    Text("급할 때 해제하려면").font(.system(size: 15, weight: .heavy)).foregroundStyle(Theme.ink)
                }
                Text("가입한 이메일로 stop2g@fromise.com에 \n제목, 내용 상관없이 아무 이메일이나 보내주세요. \n"
                     + (delayHours > 0 ? "\n지금까지 \(delayHours)회 해제해서 코드는 \(delayHours)시간 뒤에 도착해요. " : ""))
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).card(padding: 16, radius: 18)

            // 코드 입력
            VStack(spacing: 10) {
                TextField("8자리 해제코드", text: $codeInput)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                    .padding(14).background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: codeInput) { _, v in codeInput = String(v.filter(\.isNumber).prefix(8)) }

                if let err = two.lastError {
                    Text(err).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.danger)
                }

                Button {
                    Task { if await two.unlock(code: codeInput) { codeInput = "" } }
                } label: {
                    Group { if two.busy { ProgressView().tint(.white) } else { Text("해제") } }
                        .font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.danger).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(two.busy || codeInput.count != 8)
            }
        }
    }

    private var infoBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("스마트폰도 2G폰처럼 사용할 수 있어요.")
                .font(.system(size: 13.5, weight: .heavy)).foregroundStyle(Theme.ink)
            Text("내가 선택한 앱과 사이트 외에는 사용할 수 없도록 만들어줘요.")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).card(padding: 16, radius: 18)
    }

    // 메일 해제 지연 공지 (시작 전)
    private var delayNoticeBox: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text("중도 해제는 쓸수록 느려져요").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                Text(delayHours > 0
                     ? "지금까지 \(delayHours)회 해제했어요. \n다음 메일 코드는 요청 후 약 \(delayHours)시간 뒤에 도착해요."
                     : "지금은 해제를 요청하면 코드가 바로 와요. \n단, 해제할 때마다 다음 코드 발송이 1시간씩 늦어져요.")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.danger.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func fmtRemain(_ t: TimeInterval) -> String {
        let s = Int(t)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if d > 0 { return "\(d)일 \(h)시간 \(m)분" }
        if h > 0 { return String(format: "%d시간 %02d분 %02d초", h, m, sec) }
        return String(format: "%02d분 %02d초", m, sec)
    }
}
