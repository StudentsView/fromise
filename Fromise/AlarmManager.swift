import Foundation
import AVFoundation
import UserNotifications
import SwiftUI
import Combine
import UIKit

// ─────────────────────────────────────────────────────────────
//  AlarmManager — 알람/타이머 핵심
//
//  방해금지(집중)모드 + 무음 + 잠금 상태에서도 울리게 하는 3중 방어:
//
//  1) 백그라운드 오디오 keep-alive (핵심 — "꼬끼오 알람" 방식)
//     · 알람 예약 시점부터 안 들리는 무음 오디오를 .playback 으로 무한 재생해
//       앱을 백그라운드에서 살려둔다. .playback 은 무음 스위치를 무시하고,
//       실제 오디오 재생이라 방해금지모드와도 무관 → 무음+DND 둘 다 뚫림.
//     · 백그라운드에서 앱이 깨어 있으므로 타이머로 정확한 시각에 실제 알람음으로 전환.
//     · 한계: 앱을 완전히 강제 종료(스와이프로 닫음)하면 동작 안 함(모든 알람앱 공통).
//
//  2) Critical Alerts(긴급 경고) 로컬 알림 — Apple 승인 시 활성
//     · interruptionLevel=.critical + criticalSoundNamed 로 DND·무음·강제종료를 모두 뚫음.
//     · 엔타이틀먼트 승인 전에는 일반 알림으로 자동 폴백된다.
//
//  3) 일반 로컬 알림 백업 — 5초 간격 60개(약 5분). 강제종료 대비. (DND/무음엔 막힐 수 있음)
//
//  · 인앱/keep-alive 재생은 1.mp3 …, 잠금화면 알림음은 caf(≤30초) alarm1.caf … 사용.
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
    private var keepAlivePlayer: AVAudioPlayer?   // 백그라운드 생존용 무음 오디오 (예약~울림 동안 재생)
    private var fireTimer: Timer?                  // 백그라운드에서 정확한 시각에 실제 알람음으로 전환
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
        // Critical Alerts 승인 후 옵션에 .criticalAlert 추가할 것.
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        loadHistory()
        // 화면이 보이기 직전에 미리 울림 윈도우를 올림 (복귀 시 즉시 표시)
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.appBecameActive() }
        }
        // 전화/다른 앱 소리 등으로 재생이 끊겼다가 끝나면, 울리는 중이었다면 다시 이어서 재생
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            // Notification(비Sendable)을 Task로 넘기지 않도록 인터럽션 종료 여부를 여기서 먼저 판별
            guard let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeRaw) == .ended
            else { return }
            Task { @MainActor [weak self] in self?.handleAudioInterruptionEnded() }
        }
    }

    private func handleAudioInterruptionEnded() {
        if isRinging, let name = ringingSoundName {
            playLoop(name, fadeIn: false)   // 계속 울리는 중이어야 하면 재생 재개 (페이드는 다시 하지 않음)
        } else if keepAlivePlayer != nil {
            // 알람 대기 중 끊겼다 끝난 경우 → 무음 keep-alive 재개해 앱이 백그라운드에서 다시 살아나도록
            try? AVAudioSession.sharedInstance().setActive(true)
            keepAlivePlayer?.play()
        }
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
            // Critical Alerts 승인 후: c.interruptionLevel = .critical (DND/무음 우회)
            let trig = UNTimeIntervalNotificationTrigger(timeInterval: t, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(idPrefix)\(k)", content: c, trigger: trig))
        }

        // 백그라운드/잠금에서도 무음·DND를 뚫고 울리도록: 예약 시점부터 무음 오디오로 앱을 살려두고,
        // 정확한 시각에 실제 알람음으로 전환한다. (강제종료된 경우엔 위의 Critical 알림이 대비)
        startKeepAlive()
        scheduleFireTimer(at: fireDate, kind: kind, sound: sound, fadeIn: fadeIn)
    }

    private func notifSound(_ name: String) -> UNNotificationSound {
        // 잠금화면 알림음: alarm1.caf / alarm2.caf / alarm3.caf (번들 루트, ≤30초)
        // Critical Alerts 승인 후: 아래를 criticalSoundNamed(_:withAudioVolume:) 로 바꾸면 무음/볼륨 무시하고 최대 음량 재생.
        UNNotificationSound(named: UNNotificationSoundName("alarm\(name).caf"))
    }

    // MARK: 백그라운드 keep-alive (무음 오디오로 앱 생존 → 무음·DND 우회)
    /// 안 들리는 무음 오디오를 .playback 으로 무한 재생해 백그라운드/잠금에서도 앱이 죽지 않게 한다.
    private func startKeepAlive() {
        guard keepAlivePlayer == nil, let url = silentClipURL() else { return }
        let s = AVAudioSession.sharedInstance()
        // 알람 대기 동안은 다른 앱 오디오(음악 등)를 막지 않도록 mixWithOthers. 실제 울릴 땐 단독 재생으로 전환.
        try? s.setCategory(.playback, options: [.mixWithOthers])
        try? s.setActive(true)
        keepAlivePlayer = try? AVAudioPlayer(contentsOf: url)
        keepAlivePlayer?.numberOfLoops = -1
        keepAlivePlayer?.volume = 0
        keepAlivePlayer?.prepareToPlay()
        keepAlivePlayer?.play()
    }
    private func stopKeepAlive() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        fireTimer?.invalidate(); fireTimer = nil
    }
    /// 백그라운드 오디오로 앱이 깨어 있는 동안, 알람 시각에 맞춰 실제 알람음으로 전환.
    private func scheduleFireTimer(at fireDate: Date, kind: Kind, sound: String, fadeIn: Bool) {
        fireTimer?.invalidate(); fireTimer = nil
        let delay = fireDate.timeIntervalSinceNow
        guard delay > 0 else { fireNow(kind: kind, sound: sound, fadeIn: fadeIn); return }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fireNow(kind: kind, sound: sound, fadeIn: fadeIn) }
        }
        // 백그라운드에서도 RunLoop 가 돌도록 common 모드에 등록
        RunLoop.main.add(t, forMode: .common)
        fireTimer = t
    }
    /// 1초짜리 무음 WAV 를 임시 폴더에 한 번만 생성해 재사용(번들 리소스 추가 불필요).
    private func silentClipURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fromise.silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sampleRate = 8000, seconds = 1
        let dataSize = sampleRate * seconds * 2   // 16-bit mono
        var d = Data()
        func put32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); put32(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(1)
        put32(UInt32(sampleRate)); put32(UInt32(sampleRate * 2)); put16(2); put16(16)
        d.append(contentsOf: Array("data".utf8)); put32(UInt32(dataSize))
        d.append(Data(count: dataSize))   // 전부 0 = 무음
        try? d.write(to: url)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 예약/대기 중인 모든 것을 완전히 취소(정지 버튼·종료·새 예약 시).
    /// ※ 발화 후 "울리는 중"에는 호출하지 않는다 — 호출하면 5초 간격 백업 알림까지 지워져 백그라운드 울림이 끊긴다.
    func cancelNotifications() {
        let ids = (0..<batchCount).map { "\(idPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.setBadgeCount(0)
        stopKeepAlive()
        active = nil   // 더 이상 대기/활성 알람 없음 (정지 시 stale 상태로 남아 나중에 헛울리는 것 방지)
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

    /// 즉시 울림. 무음 keep-alive/발화 타이머만 정리하고, 5초 간격 백업 알림은 그대로 둔다.
    /// → 앱이 백그라운드/잠금/강제종료 상태여도 알림이 5초마다 계속 울려 사용자를 깨운다(종료 버튼을 누를 때까지).
    func fireNow(kind: Kind, sound: String, fadeIn: Bool = true) {
        guard !isRinging else { return }
        stopKeepAlive()
        startRinging(kind: kind, sound: sound, fadeIn: fadeIn)
    }

    /// 앱이 다시 활성화될 때 — 이미 울린 알람이 있으면 인앱 울림으로 인계.
    /// ※ 백업 알림은 취소하지 않는다. 또 이미 울리는 중이면 소리를 절대 다시 시작하지 않는다
    ///   (앱으로 돌아오기만 해도 소리가 꺼지거나 페이드가 처음부터 다시 시작되던 문제 방지 — 종료 버튼으로만 멈춤).
    func appBecameActive() {
        guard let a = active, Date() >= a.fireAt else { return }
        if isRinging {
            RingingWindow.shared.show(true, alarm: self)   // 화면만 다시 보장
            if player?.isPlaying != true, let name = ringingSoundName {
                playLoop(name, fadeIn: false)              // 혹시 백그라운드에서 재생이 끊겼다면 이어서 재생
            }
            return
        }
        // 알림으로만 울리고 있다가 처음 앱에 들어온 경우 → 인앱 울림으로 전환.
        // 이미 울린 알람이라 페이드 없이 곧장 최대 음량으로(들어오자마자 작아지는 느낌 방지).
        stopKeepAlive()
        startRinging(kind: Kind(rawValue: a.kind) ?? .timer, sound: a.sound, fadeIn: false)
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
    private var fadeStep = 0
    private func startFade() {
        let steps = 30
        let interval = fadeDuration / Double(steps)
        fadeStep = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player, self.isRinging else {
                    self?.fadeTimer?.invalidate(); self?.fadeTimer = nil; return
                }
                self.fadeStep += 1
                let progress = Double(self.fadeStep) / Double(steps)
                p.volume = Float(min(1, Double(self.fadeStartVolume) + progress * Double(1 - self.fadeStartVolume)))
                if self.fadeStep >= steps {
                    p.volume = 1
                    self.fadeTimer?.invalidate()
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
