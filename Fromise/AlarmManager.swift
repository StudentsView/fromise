import Foundation
import AVFoundation
import UserNotifications
import SwiftUI

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
    private let batchCount = 60
    private let spacing: TimeInterval = 5
    private let idPrefix = "fromise.alarm."

    // 울린 알람을 포그라운드 복귀 시 감지하기 위한 영속 상태
    private struct Active: Codable { let kind: String; let fireAt: Date; let sound: String }
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
    }

    // MARK: 예약
    /// fireDate에 울리고 5초 간격으로 batchCount회 반복 예약
    func schedule(kind: Kind, fireDate: Date, sound: String) {
        cancelNotifications()
        active = Active(kind: kind.rawValue, fireAt: fireDate, sound: sound)

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
        cancelNotifications()
        active = nil
    }

    /// 즉시 울림(포그라운드에서 시간이 다 됐을 때)
    func fireNow(kind: Kind, sound: String) {
        guard !isRinging else { return }
        cancelNotifications()
        startRinging(kind: kind, sound: sound)
    }

    /// 앱이 다시 활성화될 때 — 이미 울린 알람이 있으면 인앱 울림 + 나머지 알림 취소
    func appBecameActive() {
        guard let a = active else { return }
        if Date() >= a.fireAt {
            cancelNotifications()
            startRinging(kind: Kind(rawValue: a.kind) ?? .timer, sound: a.sound)
        }
    }

    // MARK: 인앱 울림
    private func startRinging(kind: Kind, sound: String) {
        ringingKind = kind
        isRinging = true
        playLoop(sound)
    }
    private func playLoop(_ name: String) {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, options: [])
        try? s.setActive(true)
        let url = Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "alarm")
        guard let url else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.play()
    }
    private func stopSound() { player?.stop(); player = nil }

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

extension AlarmManager: UNUserNotificationCenterDelegate {
    // 포그라운드에서 알림 발생 → 인앱 울림으로 전환, 시스템 배너/소리 억제
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let kindRaw = notification.request.content.userInfo["kind"] as? String ?? "timer"
        Task { @MainActor in
            self.fireNow(kind: Kind(rawValue: kindRaw) ?? .timer, sound: self.activeSound ?? "1")
        }
        completionHandler([])
    }
    // 알림 탭으로 앱 열림 → 인앱 울림
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.appBecameActive() }
        completionHandler()
    }

    private var activeSound: String? { active?.sound }
}
