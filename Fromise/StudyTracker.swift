import Foundation
import CoreMotion
import UIKit
import Combine

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
    private var segStart: Date?
    private var ticker: Timer?
    private let d = UserDefaults.standard

    private var ymd: String { let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f.string(from: Date()) }
    /// 화면에 보여줄 오늘 총합(적립 중이면 실시간)
    var todaySeconds: Int { base + (segStart.map { Int(Date().timeIntervalSince($0)) } ?? 0) }

    private init() {
        base = d.integer(forKey: "study.\(ymd)")
        NotificationCenter.default.addObserver(forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onProximity() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.enterBG() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.enterFG() }
        }
    }

    // MARK: 세션
    func startSession() {
        guard !running else { return }
        base = d.integer(forKey: "study.\(ymd)")   // 날짜 바뀜 대비 재로딩
        running = true
        UIDevice.current.isProximityMonitoringEnabled = true
        near = UIDevice.current.proximityState
        startMotion()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        evaluate()
    }
    func stopSession() {
        setCounting(false)
        running = false
        UIDevice.current.isProximityMonitoringEnabled = false
        motion.stopDeviceMotionUpdates()
        ticker?.invalidate(); ticker = nil
        save()
    }

    // MARK: 센서
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.3
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let g = m?.gravity else { return }
            Task { @MainActor in
                guard let self else { return }
                self.faceDown = g.z > 0.8
                self.evaluate()
            }
        }
    }
    private func onProximity() { near = UIDevice.current.proximityState; evaluate() }

    private func evaluate() { setCounting(running && faceDown && near) }
    private func setCounting(_ on: Bool) {
        if on, segStart == nil { segStart = Date(); counting = true }
        else if !on, let s = segStart {
            base += max(0, Int(Date().timeIntervalSince(s)))
            d.set(base, forKey: "study.\(ymd)")
            segStart = nil; counting = false
        }
    }

    // MARK: 백그라운드 보정
    private func enterBG() {
        let wasCounting = (segStart != nil)
        setCounting(false)
        d.set(wasCounting, forKey: "study.bgCounting")
        d.set(Date().timeIntervalSince1970, forKey: "study.bgAt")
        if running { save() }   // 잠금/종료 대비 저장
    }
    private func enterFG() {
        guard running else { return }
        if d.bool(forKey: "study.bgCounting"), let t = d.object(forKey: "study.bgAt") as? Double {
            base += max(0, Int(Date().timeIntervalSince1970 - t))
            d.set(base, forKey: "study.\(ymd)")
        }
        d.set(false, forKey: "study.bgCounting")
        near = UIDevice.current.proximityState
        evaluate()
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
