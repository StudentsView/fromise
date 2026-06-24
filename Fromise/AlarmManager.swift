import Foundation
import AVFoundation
import UserNotifications
import SwiftUI
import Combine
import UIKit

// ─────────────────────────────────────────────────────────────
//  AlarmManager — 알람/타이머 핵심
//
//  iOS 제약상 "종료/잠금 상태에서 정확한 시각에 소리"는 로컬 알림만 가능.
//  · 포그라운드: AVAudioPlayer로 mp3 무한 반복 (종료 누를 때까지)
//  · 백그라운드/잠금/종료: 알림을 5초 간격으로 미리 60개 예약
//      → 약 5분간 5초마다 울림 (iOS 대기 알림 64개 한도). 앱 열면 즉시 취소.
//  · 알림음은 caf/wav/aiff(≤30초)만 됨 → 잠금화면용 alarm1.caf … 필요
//    (인앱 재생은 1.mp3 … 그대로 사용)
// ─────────────────────────────────────────────────────────────

struct AlarmRecord: Codable, Identifiable {
    var id = UUID()
    let hour: Int
    let minute: Int
    let setAt: Date
    var label: String { String(format: "%02d:%02d", hour, minute) }
}

@MainActor
final class AlarmManager: NSObject, ObservableObject {
    static let shared = AlarmManager()

    enum Kind: String { case timer, alarm }

    @Published var isRinging = false
    @Published var ringingKind: Kind = .timer
    @Published var history: [AlarmRecord] = []

    private let center = UNUserNotificationCenter.current()
    private var player: AVAudioPlayer?
    private var previewPlayer: AVAudioPlayer?
    private var ringingSoundName: String?     // 현재 울리는 중인 사운드 이름 (인터럽션 후 재생 복구용)
    private var fadeTimer: Timer?
    private let fadeDuration: TimeInterval = 15   // 이 시간(초)에 걸쳐 0 → 최대 볼륨으로 점점 커짐
    private let fadeStartVolume: Float = 0.06     // 너무 작으면 아예 안 들릴 수 있어 살짝 들리는 정도로 시작
    private let batchCount = 60
    private let spacing: TimeInterval = 5
    private let idPrefix = "fromise.alarm."

    // 울린 알람을 포그라운드 복귀 시 감지하기 위한 영속 상태
    private struct Active: Codable { let kind: String; let fireAt: Date; let sound: String; let fadeIn: Bool }
    private var active: Active? {
        get {
            guard let d = UserDefaults.standard.data(forKey: "fromise.activeAlarm"),
                  let a = try? JSONDecoder().decode(Active.self, from: d) else { return nil }
            return a
        }
        set {
            if let v = newValue, let d = try? JSONEncoder().encode(v) {
                UserDefaults.standard.set(d, forKey: "fromise.activeAlarm")
            } else {
                UserDefaults.standard.removeObject(forKey: "fromise.activeAlarm")
            }
        }
    }

    func configure() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        loadHistory()
        // 화면이 보이기 직전에 미리 울림 윈도우를 올림 (복귀 시 즉시 표시)
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appBecameActive() }
        }
        // 전화/다른 앱 소리 등으로 재생이 끊겼다가 끝나면, 울리는 중이었다면 다시 이어서 재생
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleAudioInterruption(note) }
        }
    }

    private func handleAudioInterruption(_ note: Notification) {
        guard isRinging, let name = ringingSoundName,
              let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
              type == .ended
        else { return }
        playLoop(name, fadeIn: false)   // 인터럽션이 끝났는데도 계속 울리는 중이어야 하면 재생 재개 (페이드는 다시 하지 않음)
    }

    // MARK: 예약
    /// fireDate에 울리고 5초 간격으로 batchCount회 반복 예약
    func schedule(kind: Kind, fireDate: Date, sound: String, fadeIn: Bool = true) {
        cancelNotifications()
        active = Active(kind: kind.rawValue, fireAt: fireDate, sound: sound, fadeIn: fadeIn)

        let title = kind == .timer ? "타이머를 확인해주세요!" : "알람을 확인해주세요!"
        let body  = kind == .timer ? "Fromise를 열어서 타이머를 꺼 주세요!" : "Fromise를 열어서 알람을 꺼 주세요!"
        let snd = notifSound(sound)
        let base = fireDate.timeIntervalSinceNow

        for k in 0..<batchCount {
            let t = base + Double(k) * spacing
            guard t > 0 else { continue }
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.sound = snd
            c.userInfo = ["kind": kind.rawValue]
            let trig = UNTimeIntervalNotificationTrigger(timeInterval: t, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(idPrefix)\(k)", content: c, trigger: trig))
        }
    }

    private func notifSound(_ name: String) -> UNNotificationSound {
        // 잠금화면 알림음: alarm1.caf / alarm2.caf / alarm3.caf (번들 루트, ≤30초)
        UNNotificationSound(named: UNNotificationSoundName("alarm\(name).caf"))
    }

    func cancelNotifications() {
        let ids = (0..<batchCount).map { "\(idPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.setBadgeCount(0)
    }

    /// 사용자가 "종료"
    func stop() {
        isRinging = false
        stopSound()
        fadeTimer?.invalidate(); fadeTimer = nil
        ringingSoundName = nil
        cancelNotifications()
        active = nil
        RingingWindow.shared.show(false, alarm: self)
    }

    /// 즉시 울림(포그라운드에서 시간이 다 됐을 때)
    func fireNow(kind: Kind, sound: String, fadeIn: Bool = true) {
        guard !isRinging else { return }
        cancelNotifications()
        startRinging(kind: kind, sound: sound, fadeIn: fadeIn)
    }

    /// 앱이 다시 활성화될 때 — 이미 울린 알람이 있으면 인앱 울림 + 나머지 알림 취소
    func appBecameActive() {
        guard let a = active else { return }
        if Date() >= a.fireAt {
            cancelNotifications()
            startRinging(kind: Kind(rawValue: a.kind) ?? .timer, sound: a.sound, fadeIn: a.fadeIn)
        }
    }

    // MARK: 인앱 울림
    private func startRinging(kind: Kind, sound: String, fadeIn: Bool) {
        ringingKind = kind
        isRinging = true
        RingingWindow.shared.show(true, alarm: self)   // 즉시 최상단 표시
        playLoop(sound, fadeIn: fadeIn)
    }
    /// fadeIn이 true면 작은 소리로 시작해서 fadeDuration에 걸쳐 점점 커짐.
    /// (잠금화면 알림음(caf)에는 적용 안 됨 — iOS 시스템 사운드라 볼륨 제어가 불가능한 제약)
    private func playLoop(_ name: String, fadeIn: Bool) {
        ringingSoundName = name
        fadeTimer?.invalidate(); fadeTimer = nil
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, options: [])
        try? s.setActive(true)
        let url = Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "alarm")
        guard let url else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self                 // 끝까지 다 돌고도 멈추면 delegate에서 다시 이어 재생
        player?.numberOfLoops = -1               // 무한 반복
        player?.prepareToPlay()
        if fadeIn {
            player?.volume = fadeStartVolume
            player?.play()
            startFade()
        } else {
            player?.volume = 1
            player?.play()
        }
    }
    /// fadeStartVolume → 1.0 까지 fadeDuration에 걸쳐 선형으로 키움
    private func startFade() {
        let steps = 30
        let interval = fadeDuration / Double(steps)
        var step = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, let p = self.player, self.isRinging else { timer.invalidate(); return }
                step += 1
                let progress = Double(step) / Double(steps)
                p.volume = Float(min(1, Double(self.fadeStartVolume) + progress * Double(1 - self.fadeStartVolume)))
                if step >= steps {
                    p.volume = 1
                    timer.invalidate()
                    self.fadeTimer = nil
                }
            }
        }
    }
    private func stopSound() {
        player?.stop()
        player = nil
        fadeTimer?.invalidate(); fadeTimer = nil
    }

    // MARK: 미리듣기 (소리 1/2/3 버튼 선택 시)
    @Published var previewingSound: String?   // 현재 미리듣기 중인 사운드 이름 (nil이면 재생 중 아님) — 같은 버튼 다시 탭하면 토글로 끄기 위해 View에서 참조

    /// 알람음 미리듣기 재생. 다른 미리듣기가 재생 중이면 먼저 멈추고 새로 시작.
    func previewSound(_ name: String) {
        stopPreview()
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, options: [.mixWithOthers])
        try? s.setActive(true)
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "alarm")
        else { return }
        previewPlayer = try? AVAudioPlayer(contentsOf: url)
        previewPlayer?.delegate = self     // 끝까지 다 들으면 previewingSound도 자동으로 풀려서 버튼 강조가 꺼짐
        previewPlayer?.prepareToPlay()
        previewPlayer?.play()
        previewingSound = name
    }
    /// 미리듣기 정지 (버튼 다시 탭 / 알람·타이머 시작 / 탭 전환 / 화면 닫힘 시 호출)
    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewingSound = nil
    }

    // MARK: 기록
    func addHistory(hour: Int, minute: Int) {
        history.insert(AlarmRecord(hour: hour, minute: minute, setAt: Date()), at: 0)
        if history.count > 30 { history = Array(history.prefix(30)) }
        saveHistory()
    }
    func clearHistory() { history = []; saveHistory() }
    private func saveHistory() {
        if let d = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(d, forKey: "fromise.alarmHistory")
        }
    }
    private func loadHistory() {
        if let d = UserDefaults.standard.data(forKey: "fromise.alarmHistory"),
           let h = try? JSONDecoder().decode([AlarmRecord].self, from: d) {
            history = h
        }
    }
}

extension AlarmManager: AVAudioPlayerDelegate {
    // numberOfLoops = -1 이라 보통 호출되지 않지만, 디코드 오류 등 예외 상황으로 재생이 끊긴 경우를 대비해
    // 종료를 누르기 전까지는 계속 다시 이어 재생되도록 함 (복구 재생이므로 페이드는 다시 하지 않음)
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if player === self.previewPlayer {
                // 미리듣기가 끝까지 다 재생됨 → 버튼 강조 해제
                self.previewPlayer = nil
                self.previewingSound = nil
                return
            }
            guard self.isRinging, let name = self.ringingSoundName else { return }
            self.playLoop(name, fadeIn: false)
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if player === self.previewPlayer {
                self.previewPlayer = nil
                self.previewingSound = nil
                return
            }
            guard self.isRinging, let name = self.ringingSoundName else { return }
            self.playLoop(name, fadeIn: false)
        }
    }
}

extension AlarmManager: UNUserNotificationCenterDelegate {
    // 포그라운드에서 알림 발생 → 인앱 울림으로 전환, 시스템 배너/소리 억제
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let kindRaw = notification.request.content.userInfo["kind"] as? String ?? "timer"
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.fireNow(kind: Kind(rawValue: kindRaw) ?? .timer, sound: self.activeSound ?? "1", fadeIn: self.activeFadeIn ?? true)
        }
        completionHandler([])
    }
    // 알림 탭으로 앱 열림 → 인앱 울림
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor [weak self] in self?.appBecameActive() }
        completionHandler()
    }

    private var activeSound: String? { active?.sound }
    private var activeFadeIn: Bool? { active?.fadeIn }
}
