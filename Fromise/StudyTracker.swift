import Foundation
import CoreMotion
import UIKit
import Combine
import Supabase

// ─────────────────────────────────────────────────────────────
//  StudyTracker — "엎어서 바닥에 덮어둔 시간"만 공부 시간으로 적립
//  물리량: ① 중력 방향(gravity.z>0.8 → 화면이 바닥을 향함) ② 근접(가려짐)
//  둘 다 참일 때만 카운트. 들면 멈추고 덮으면 재개.
//  백그라운드: 진입 시각 저장 → 복귀 시 덮여있던 시간 보정(완전 종료 시엔 못 셈).
//  매일 총합을 Supabase study_days(user_id,ymd,seconds)에 upsert.
// ─────────────────────────────────────────────────────────────
@MainActor
final class StudyTracker: ObservableObject {
    static let shared = StudyTracker()

    @Published var running = false      // 세션 진행 중
    @Published var counting = false     // 지금 적립 중(덮임+근접)
    @Published private var base = 0      // 오늘 확정 적립(초)

    private let motion = CMMotionManager()
    private var faceDown = false
    private var near = false
    private var hasProximity = false   // iPad 등 근접센서 없는 기기 대응
    private var segStart: Date?
    private var ticker: Timer?
    private let d = UserDefaults.standard

    private static let ymdFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f }()
    private var ymd: String { Self.ymdFmt.string(from: Date()) }
    /// 화면에 보여줄 오늘 총합(적립 중이면 실시간)
    var todaySeconds: Int { base + (segStart.map { Int(Date().timeIntervalSince($0)) } ?? 0) }

    // MARK: 일별 기록 / 평균
    struct DayStat: Identifiable {
        let date: Date
        let ymd: String
        let seconds: Int       // 공부(집중) 시간
        let twoGSeconds: Int   // 2G폰 모드 지속 시간(평균엔 미반영, 표시만)
        var id: String { ymd }
    }
    /// 최근 days일치 일별 누적 집중시간 (오늘 포함, 최신순)
    func dailyHistory(days: Int = 30) -> [DayStat] {
        let cal = Calendar.current
        var out: [DayStat] = []
        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = Self.ymdFmt.string(from: date)
            let sec = offset == 0 ? todaySeconds : d.integer(forKey: "study.\(key)")
            let twoG = d.integer(forKey: "twoG.\(key)")
            out.append(DayStat(date: date, ymd: key, seconds: sec, twoGSeconds: twoG))
        }
        return out
    }
    /// 최근 n일 하루 평균(초)
    func average(days: Int) -> Int {
        let h = dailyHistory(days: days)
        guard !h.isEmpty else { return 0 }
        return h.reduce(0) { $0 + $1.seconds } / h.count
    }
    var weeklyAverage: Int  { average(days: 7) }
    var monthlyAverage: Int { average(days: 30) }

    private init() {
        base = d.integer(forKey: "study.\(ymd)")
        WidgetBridge.updateStudy(seconds: base)   // 위젯에 초기 오늘 누적 반영
        NotificationCenter.default.addObserver(forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onProximity() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enterBG() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enterFG() }
        }
        FocusGuard.shared.stopShield()   // 콜드스타트: 비정상 종료로 남은 차단 정리
    }

    // MARK: 세션
    func startSession() {
        guard !running else { return }
        base = d.integer(forKey: "study.\(ymd)")   // 날짜 바뀜 대비 재로딩
        running = true
        if !TwoGStore.shared.active {                // 2G 모드 중이면 이미 차단 중 → 중복 적용 없이 기록만
            FocusGuard.shared.startShield()          // (단독 학습 세션) 허용 앱/사이트만 사용(화이트리스트)
        }
        UIApplication.shared.isIdleTimerDisabled = false   // 자동 잠금 허용(배터리)
        UIDevice.current.isProximityMonitoringEnabled = true
        hasProximity = UIDevice.current.isProximityMonitoringEnabled   // 켜졌으면 센서 있음
        near = hasProximity ? UIDevice.current.proximityState : true   // 없으면 face-down만으로 판정
        startMotion()
        startTicker()
        evaluate()
    }
    func stopSession() {
        setCounting(false)
        running = false
        if !TwoGStore.shared.active { FocusGuard.shared.stopShield() }   // 2G 중이면 차단 유지
        UIDevice.current.isProximityMonitoringEnabled = false
        motion.stopDeviceMotionUpdates()
        stopTicker()
        save()
        WidgetBridge.updateStudy(seconds: base)
    }

    // MARK: 센서
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.3
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let g = m?.gravity else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.faceDown = g.z > 0.8
                self.evaluate()
            }
        }
    }
    private func onProximity() { near = UIDevice.current.proximityState; evaluate() }

    private func evaluate() { setCounting(running && faceDown && near) }
    private func setCounting(_ on: Bool) {
        if on, segStart == nil { segStart = Date(); counting = true; screenOff(); stopTicker() }   // 화면 꺼짐 → 타이머 정지(배터리)
        else if !on, let s = segStart {
            base += max(0, Int(Date().timeIntervalSince(s)))
            d.set(base, forKey: "study.\(ymd)")
            WidgetBridge.updateStudy(seconds: base)   // 위젯에 오늘 누적 반영
            segStart = nil; counting = false; screenOn(); if running { startTicker() }
        }
    }

    // MARK: UI 갱신 타이머 — 화면이 켜져 보일 때만 돌려 배터리 절약
    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    // MARK: 화면 일시 끄기 — 덮여 기록 중에는 밝기를 0으로(들어올리면 복구)
    private var savedBrightness: CGFloat?
    private func screenOff() {
        if savedBrightness == nil { savedBrightness = UIScreen.main.brightness }
        UIScreen.main.brightness = 0
    }
    private func screenOn() {
        if let b = savedBrightness { UIScreen.main.brightness = b; savedBrightness = nil }
    }

    // MARK: 포그라운드에서만 기록
    //  앱을 켜 둔 채 엎어둔 동안만 적립. 홈으로 나가거나 화면을 잠그면(백그라운드) 즉시 중단.
    //  (face-down으로 화면이 꺼지는 건 백그라운드 전환이 아니라 계속 기록됨)
    private func enterBG() {
        setCounting(false)          // 진행 중 세그먼트를 여기까지만 적립하고 멈춤
        stopTicker()                // 백그라운드 → 타이머 정지(배터리)
        if running { save() }       // 잠금/종료 대비 저장 — 백그라운드 시간은 적립하지 않음
        WidgetBridge.updateStudy(seconds: base)   // 백그라운드 진입 시 위젯 최신화
    }
    private func enterFG() {
        guard running else { return }
        near = hasProximity ? UIDevice.current.proximityState : true
        startTicker()               // 복귀 → UI 갱신 재개(곧 덮이면 setCounting이 다시 멈춤)
        evaluate()                  // 복귀 후 다시 엎어둔 상태면 그때부터 재개
    }

    // MARK: Supabase 저장 (오늘 총합 upsert)
    private func save() {
        let total = base, day = ymd
        guard let uid = supabase.auth.currentUser?.id else { return }
        struct Row: Encodable { let user_id: String; let ymd: String; let seconds: Int }
        Task {
            _ = try? await supabase.from("study_days")
                .upsert(Row(user_id: uid.uuidString, ymd: day, seconds: total), onConflict: "user_id,ymd")
                .execute()
        }
    }
}
