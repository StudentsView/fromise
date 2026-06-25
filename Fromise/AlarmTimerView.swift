import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────
//  AlarmTimerView — 타이머(기본) / 알람
// ─────────────────────────────────────────────────────────────

struct AlarmTimerView: View {
    @EnvironmentObject private var alarm: AlarmManager
    @Environment(\.dismiss) private var dismiss
    enum Mode: String, CaseIterable { case timer = "타이머", alarm = "알람" }
    @State private var mode: Mode = .timer
    @AppStorage("alarm.sound") private var sound = "1"
    @AppStorage("alarm.fadeIn") private var fadeIn = true   // 소리 점점 키우기
    // 화면에 보이는 글자(label)와 실제 사운드 파일 이름(key, 1.mp3/2.mp3/3.mp3 · alarm1.caf 등)을 분리.
    // label만 원하는 대로 바꿔도 key는 그대로라 파일을 정상적으로 찾음.
    private let soundChoices: [(label: String, key: String)] = [("아침", "1"), ("알림", "2"), ("축제", "3")]

    // 타이머
    @State private var target = 0                 // 설정 시간(초)
    @State private var endDate: Date?
    @State private var running = false
    @State private var remaining = 0
    @State private var customMin = ""
    @State private var customSec = ""

    // 알람
    @State private var alarmTime = Date()

    private let ticker = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { alarm.stopPreview() }   // 탭 전환 시 미리듣기 정지

                    switch mode {
                    case .timer: timerSection
                    case .alarm: alarmSection
                    }
                }
                .padding(18)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("알람 · 타이머")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .onReceive(ticker) { _ in tick() }
        .onDisappear { alarm.stopPreview() }
    }

    // MARK: 타이머
    private var timerSection: some View {
        VStack(spacing: 16) {
            Text(fmt(running ? remaining : target))
                .font(.system(size: 60, weight: .light, design: .rounded))
                .monospacedDigit().foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 8)

            // 빠른 추가
            let quick: [(String, Int)] = [("+5분",300),("+10분",600),("+15분",900),("+20분",1200),("+30분",1800),("+1시간",3600)]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(quick, id: \.0) { q in
                    Button {
                        if !running { target += q.1 }
                        alarm.stopPreview()
                    } label: {
                        Text(q.0).font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled(running)
                }
            }

            // 커스텀 입력
            HStack(spacing: 8) {
                numField("분", $customMin)
                numField("초", $customSec)
                Button {
                    let m = Int(customMin) ?? 0, s = Int(customSec) ?? 0
                    if m + s > 0 { target = m * 60 + s; customMin = ""; customSec = "" }
                    alarm.stopPreview()
                } label: {
                    Text("설정").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.paper)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain).disabled(running)
            }

            soundPicker

            HStack(spacing: 10) {
                if running {
                    Button { stopTimer() } label: { bigBtn("정지", Theme.danger) }.buttonStyle(.plain)
                } else {
                    Button { startTimer() } label: { bigBtn("시작", Theme.ink) }
                        .buttonStyle(.plain).disabled(target == 0)
                }
                Button { target = 0; stopTimer() } label: { bigBtnOutline("리셋") }.buttonStyle(.plain)
            }
        }
    }

    // MARK: 알람
    private var alarmSection: some View {
        VStack(spacing: 16) {
            DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden()
                .frame(maxWidth: .infinity)

            soundPicker

            Button { setAlarm() } label: { bigBtn("알람 설정", Theme.ink) }.buttonStyle(.plain)

            if !alarm.history.isEmpty {
                HStack {
                    Text("최근 알람").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink3)
                    Spacer()
                    Button("기록 지우기") { alarm.clearHistory(); alarm.stopPreview() }
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink3)
                }
                VStack(spacing: 6) {
                    ForEach(alarm.history) { rec in
                        Button { applyHistory(rec) } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .semibold))
                                Text(rec.label).font(.system(size: 16, weight: .heavy)).monospacedDigit()
                                Spacer()
                                Text("다시 설정").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink3)
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("이어폰을 연결하면 주변을 방해하지 않아요.")
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center).padding(.top, 4)
        }
    }

    // MARK: 공통 조각
    private var soundPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("소리").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink3)
                ForEach(soundChoices, id: \.key) { choice in
                    Button {
                        if alarm.previewingSound == choice.key {
                            alarm.stopPreview()   // 같은 버튼을 다시 누르면 미리듣기 정지
                        } else {
                            sound = choice.key
                            alarm.previewSound(choice.key)
                        }
                    } label: {
                        Text(choice.label).font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(sound == choice.key ? Theme.paper : Theme.ink2)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(sound == choice.key ? Theme.ink : Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: sound == choice.key ? 0 : 1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            Toggle(isOn: $fadeIn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("소리 점점 키우기").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                    Text("작게 시작해서 서서히 커져요").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.ink))
            .onChange(of: fadeIn) { alarm.stopPreview() }   // 토글 조작 시 미리듣기 정지
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    private func numField(_ ph: String, _ text: Binding<String>) -> some View {
        // 외장 키보드나 붙여넣기로 숫자가 아닌 문자가 들어와도 항상 숫자만 남도록 바인딩 자체를 필터링
        let numericOnly = Binding<String>(
            get: { text.wrappedValue },
            set: { text.wrappedValue = $0.filter(\.isNumber) }
        )
        return TextField(ph, text: numericOnly)
            .keyboardType(.numberPad).multilineTextAlignment(.center)
            .font(.system(size: 16, weight: .bold)).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .onChange(of: text.wrappedValue) { alarm.stopPreview() }   // 입력창 조작 시 미리듣기 정지
    }
    private func bigBtn(_ t: String, _ bg: Color) -> some View {
        Text(t).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    private func bigBtnOutline(_ t: String) -> some View {
        Text(t).font(.system(size: 16, weight: .heavy)).foregroundStyle(Theme.ink2)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: 로직
    private func tick() {
        if running, let end = endDate {
            let r = Int(ceil(end.timeIntervalSinceNow))
            remaining = max(0, r)
            if r <= 0 {
                running = false; endDate = nil
                alarm.fireNow(kind: .timer, sound: sound, fadeIn: fadeIn)
            }
        }
    }
    private func startTimer() {
        guard target > 0 else { return }
        alarm.stopPreview()   // 시작하면 미리듣기는 정지
        let end = Date().addingTimeInterval(TimeInterval(target))
        endDate = end; remaining = target; running = true
        alarm.schedule(kind: .timer, fireDate: end, sound: sound, fadeIn: fadeIn)
    }
    private func stopTimer() {
        running = false; endDate = nil
        alarm.cancelNotifications()
        alarm.stopPreview()
    }
    private func setAlarm() {
        alarm.stopPreview()   // 시작하면 미리듣기는 정지
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: alarmTime)
        var fire = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) ?? Date().addingTimeInterval(60)
        if fire.timeIntervalSinceNow < 1 { fire = fire.addingTimeInterval(86400) }
        alarm.schedule(kind: .alarm, fireDate: fire, sound: sound, fadeIn: fadeIn)
        alarm.addHistory(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
    }
    private func applyHistory(_ rec: AlarmRecord) {
        alarm.stopPreview()
        var c = DateComponents(); c.hour = rec.hour; c.minute = rec.minute
        if let d = Calendar.current.date(from: c) { alarmTime = d }
    }

    private func fmt(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

// MARK: 전역 울림 오버레이 (앱 어디서든 종료 가능)
struct RingingOverlay: View {
    @EnvironmentObject private var alarm: AlarmManager
    @State private var shown = false
    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.55 : 0).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 54, weight: .bold)).foregroundStyle(.white)
                Text(alarm.ringingKind == .timer ? "타이머를 확인해주세요!" : "알람을 확인해주세요!")
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                Text("종료 버튼을 눌러 \(alarm.ringingKind == .timer ? "타이머" : "알람")를 꺼 주세요!")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                Button { dismissRinging() } label: {
                    Text("종료").font(.system(size: 18, weight: .heavy)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(.white).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain).padding(.horizontal, 40).padding(.top, 8)
            }
            .padding(36)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { shown = true } }
    }
    private func dismissRinging() {
        withAnimation(.easeOut(duration: 0.2)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { alarm.stop() }
    }
}

import UIKit

// 모든 시트/탭보다 위에 뜨는 별도 윈도우로 울림 오버레이 표시
final class RingingWindow {
    static let shared = RingingWindow()
    private var window: UIWindow?

    @MainActor
    func show(_ on: Bool, alarm: AlarmManager) {
        if on {
            guard window == nil,
                  let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
                    ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
            else { return }
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 1            // 시트보다 위
            w.backgroundColor = .clear
            w.rootViewController = UIHostingController(
                rootView: RingingOverlay().environmentObject(alarm))
            w.rootViewController?.view.backgroundColor = .clear
            w.makeKeyAndVisible()
            window = w
        } else {
            window?.isHidden = true
            window = nil
        }
    }
}
