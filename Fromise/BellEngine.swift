import SwiftUI
import Combine
import AVFoundation

// ─────────────────────────────────────────────────────────────
//  BellEngine.swift — 모의 수능 타종 엔진
//  · 08:10부터 실시간으로 진행, 구간 전환 시 해당 종소리 방송 재생
//  · 오디오는 웹과 동일 경로에서 스트리밍 (번들에 같은 파일이 있으면 우선)
//  · 무음 모드에서도 울리도록 AVAudioSession .playback 사용
// ─────────────────────────────────────────────────────────────

struct BellSegment: Identifiable {
    let id = UUID()
    let name: String
    let start: String        // "HH:mm"
    let end: String?         // nil = 마지막 시점
    let isRange: Bool        // true면 "start~end"로 표기
    let phase: Phase
    let audio: String?       // 확장자 제외 파일명, nil = 종소리 없음(듣기 등)

    enum Phase { case free, prep, exam }

    var subject: String? {
        for s in ["국어", "수학", "영어", "한국사", "탐구"] where name.contains(s) { return s }
        return nil
    }
}

enum BellPalette {
    static func subject(_ s: String?) -> Color {
        switch s {
        case "국어":   return Color(hex: 0x8FB84B)
        case "수학":   return Color(hex: 0xE86FA0)
        case "영어":   return Color(hex: 0x3FB8AE)
        case "한국사": return Color(hex: 0x7B5BB8)
        case "탐구":   return Color(hex: 0x4A6FD0)
        default:       return Theme.ink3
        }
    }
}

struct ListeningPreset: Identifiable {
    let id = UUID()
    let name: String
    let file: String   // listening/xx.mp3 의 파일명 (확장자 포함)
}

@MainActor
final class BellEngine: ObservableObject {
    // 표시 상태
    @Published var simTime: Date = Date()
    @Published var started = false
    @Published var running = false
    @Published var activeIndex = 0
    @Published var muted = false
    @Published var listeningName: String? = nil   // 선택된 듣기평가 음원 이름

    static let audioBase     = "https://daesuneung.com/audio/"
    static let listeningBase = "https://daesuneung.com/listening/"

    let schedule: [BellSegment] = BellEngine.makeSchedule()
    let listeningPresets: [ListeningPreset] = [
        .init(name: "24년 6월 평가원",     file: "24-06.mp3"),
        .init(name: "24년 9월 평가원",     file: "24-09.mp3"),
        .init(name: "24년 11월 수능",      file: "24-11.mp3"),
        .init(name: "25년 6월 평가원",     file: "25-06.mp3"),
        .init(name: "25년 9월 평가원",     file: "25-09.mp3"),
        .init(name: "25년 11월 수능",      file: "25-11.mp3"),
        .init(name: "26년 3월 서울 교육청", file: "26-03.mp3"),
        .init(name: "26년 5월 경기 교육청", file: "26-05.mp3"),
        .init(name: "26년 6월 평가원",     file: "26-06.mp3"),
    ]

    private var startDates: [Date] = []
    private var endDates: [Date?] = []
    private var baseSim = Date()
    private var basePerf: CFTimeInterval = 0
    private var lastIdx = -1
    private var player: AVPlayer?

    private var listeningURL: URL?
    private var listeningFired = false
    private let listeningFireTime = "13:07"

    init() {
        rebuildDates()
        simTime = startDates.first ?? Date()
        lastIdx = idx(at: simTime)
        activeIndex = lastIdx
    }

    // MARK: 시간 계산
    private func todayAt(_ hhmm: String) -> Date {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = p.first ?? 0; c.minute = p.count > 1 ? p[1] : 0; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }
    private func rebuildDates() {
        startDates = schedule.map { todayAt($0.start) }
        endDates   = schedule.map { $0.end.map(todayAt) }
    }
    private func idx(at d: Date) -> Int {
        let c = d.timeIntervalSince1970
        if c < startDates[0].timeIntervalSince1970 { return 0 }
        for i in schedule.indices {
            let s = startDates[i].timeIntervalSince1970
            let e = endDates[i]?.timeIntervalSince1970 ?? .infinity
            if c >= s && c < e { return i }
        }
        return schedule.count - 1
    }

    // MARK: 파생 표시값
    var timeText: String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: simTime)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
    var current: BellSegment { schedule[activeIndex] }
    var progress: Double {
        guard let s0 = startDates.first?.timeIntervalSince1970,
              let eN = startDates.last?.timeIntervalSince1970, eN > s0 else { return 0 }
        let t = min(max(simTime.timeIntervalSince1970, s0), eN)
        return (t - s0) / (eN - s0)
    }
    var statusText: String {
        switch current.phase {
        case .exam: return "시험 중"
        case .prep: return current.name.contains("입실") ? "입실" : "준비"
        case .free: return current.name
        }
    }
    var nextCountdown: String? {
        guard running, activeIndex + 1 < schedule.count, let end = endDates[activeIndex] else { return nil }
        let rem = end.timeIntervalSince(simTime)
        guard rem > 0 else { return nil }
        return "\(schedule[activeIndex + 1].name)까지 " + Self.fmtDur(rem)
    }
    func rangeText(_ i: Int) -> String {
        let seg = schedule[i]
        return (seg.isRange && seg.end != nil) ? "\(seg.start) ~ \(seg.end!)" : seg.start
    }
    static func fmtDur(_ s: TimeInterval) -> String {
        let t = max(0, Int(ceil(s)))
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%02d:%02d", m, sec)
    }

    // MARK: 제어
    func start() {
        guard !started else { return }
        setupSession()
        started = true; running = true; rebase()
        lastIdx = idx(at: simTime); activeIndex = lastIdx
        syncListeningFired()
        play(lastIdx)
    }
    func reset() {
        running = false; started = false
        simTime = startDates.first ?? Date()
        lastIdx = idx(at: simTime); activeIndex = lastIdx
        listeningFired = false
        stopAudio()
    }
    func jump(to i: Int) {
        guard i >= 0, i < schedule.count else { return }
        setupSession()
        simTime = startDates[i]; running = true; started = true; rebase()
        lastIdx = i; activeIndex = i
        syncListeningFired()
        stopAudio()
        if i == englishListeningIndex, listeningURL != nil { listeningFired = true; playListening() }
        else { play(i) }
    }
    func toggleMute() { muted.toggle(); if muted { stopAudio() } }

    private func rebase() { baseSim = simTime; basePerf = CACurrentMediaTime() }

    /// 뷰의 타이머에서 0.25초마다 호출
    func tick() {
        guard running else { return }
        let elapsed = CACurrentMediaTime() - basePerf
        guard let finalT = startDates.last?.timeIntervalSince1970 else { return }
        let cand = baseSim.addingTimeInterval(elapsed)
        if cand.timeIntervalSince1970 >= finalT {
            simTime = startDates.last!; running = false
            recompute(); return
        }
        simTime = cand
        recompute()
        checkListening()
    }
    private func recompute() {
        let n = idx(at: simTime)
        if n != lastIdx {
            lastIdx = n; activeIndex = n
            if running && !muted { play(n) }
        }
    }

    // MARK: 듣기평가
    var englishListeningIndex: Int { schedule.firstIndex { $0.name.contains("영어 듣기") } ?? 14 }
    func setListening(_ p: ListeningPreset) {
        listeningURL = URL(string: Self.listeningBase + p.file)
        listeningName = p.name
        listeningFired = false
    }
    func clearListening() { listeningURL = nil; listeningName = nil; listeningFired = false }
    private func syncListeningFired() {
        // 점프/시작 시점이 13:07 이후면 이미 지난 것으로 간주
        listeningFired = simTime >= todayAt(listeningFireTime)
    }
    private func checkListening() {
        guard let _ = listeningURL, !listeningFired, running, !muted else { return }
        if simTime >= todayAt(listeningFireTime) { listeningFired = true; playListening() }
    }
    private func playListening() {
        guard let u = listeningURL else { return }
        player = AVPlayer(url: u); player?.play()
    }

    // MARK: 오디오
    private func setupSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [])
        try? s.setActive(true)
    }
    private func play(_ i: Int) {
        guard !muted, let name = schedule[i].audio else { return }
        let url = Bundle.main.url(forResource: name, withExtension: "mp3")
               ?? URL(string: Self.audioBase + name + ".mp3")
        guard let u = url else { return }
        player = AVPlayer(url: u); player?.play()
    }
    private func stopAudio() { player?.pause(); player = nil }

    // MARK: 스케줄 정의 (웹 HTML과 동일)
    static func makeSchedule() -> [BellSegment] {
        [
            .init(name: "수험생 입실 완료",   start: "08:10", end: "08:25", isRange: false, phase: .free, audio: "01_student-entry"),
            .init(name: "국어 예비령",        start: "08:25", end: "08:35", isRange: false, phase: .prep, audio: "02_korean-pre"),
            .init(name: "국어 준비령",        start: "08:35", end: "08:40", isRange: false, phase: .prep, audio: "03_korean-ready"),
            .init(name: "국어",              start: "08:40", end: "10:00", isRange: true,  phase: .exam, audio: "04_korean-start"),
            .init(name: "국어 종료 10분 전",  start: "09:50", end: "10:00", isRange: false, phase: .exam, audio: "05_korean-10min"),
            .init(name: "국어 종료",          start: "10:00", end: "10:20", isRange: false, phase: .free, audio: "06_korean-end"),
            .init(name: "수학 예비령",        start: "10:20", end: "10:25", isRange: false, phase: .prep, audio: "07_math-pre"),
            .init(name: "수학 준비령",        start: "10:25", end: "10:30", isRange: false, phase: .prep, audio: "08_math-ready"),
            .init(name: "수학",              start: "10:30", end: "12:10", isRange: true,  phase: .exam, audio: "09_math-start"),
            .init(name: "수학 종료 10분 전",  start: "12:00", end: "12:10", isRange: false, phase: .exam, audio: "10_math-10min"),
            .init(name: "수학 종료 / 중식",   start: "12:10", end: "12:55", isRange: false, phase: .free, audio: "11_math-end"),
            .init(name: "감독관 입실",        start: "12:55", end: "13:00", isRange: false, phase: .prep, audio: "12_english-pre"),
            .init(name: "영어 예비령",        start: "13:00", end: "13:05", isRange: false, phase: .prep, audio: "13_english-ready"),
            .init(name: "영어 준비령",        start: "13:05", end: "13:07", isRange: false, phase: .prep, audio: "14_english-start"),
            .init(name: "영어 듣기 시작",     start: "13:07", end: "14:20", isRange: true,  phase: .exam, audio: nil),
            .init(name: "영어 종료 10분 전",  start: "14:10", end: "14:20", isRange: false, phase: .exam, audio: "15_english-10min"),
            .init(name: "영어 종료",          start: "14:20", end: "14:40", isRange: false, phase: .free, audio: "16_english-end"),
            .init(name: "한국사 예비령",      start: "14:40", end: "14:45", isRange: false, phase: .prep, audio: "17_history-pre"),
            .init(name: "한국사 준비령",      start: "14:45", end: "14:50", isRange: false, phase: .prep, audio: "18_history-ready"),
            .init(name: "한국사",            start: "14:50", end: "15:20", isRange: true,  phase: .exam, audio: "19_history-start"),
            .init(name: "한국사 종료 5분 전", start: "15:15", end: "15:20", isRange: false, phase: .exam, audio: "20_history-5min"),
            .init(name: "한국사 종료",        start: "15:20", end: "15:30", isRange: false, phase: .free, audio: "21_history-end"),
            .init(name: "탐구 준비령",        start: "15:30", end: "15:35", isRange: false, phase: .prep, audio: "22_inquiry-ready"),
            .init(name: "탐구 제1선택",       start: "15:35", end: "16:05", isRange: true,  phase: .exam, audio: "23_inquiry1-start"),
            .init(name: "탐구1 종료 5분 전",  start: "16:00", end: "16:05", isRange: false, phase: .exam, audio: "24_inquiry1-5min"),
            .init(name: "탐구1 종료",         start: "16:05", end: "16:07", isRange: false, phase: .free, audio: "25_inquiry1-end"),
            .init(name: "탐구 제2선택",       start: "16:07", end: "16:37", isRange: true,  phase: .exam, audio: "26_inquiry2-start"),
            .init(name: "탐구2 종료 5분 전",  start: "16:32", end: "16:37", isRange: false, phase: .exam, audio: "27_inquiry2-5min"),
            .init(name: "탐구2 종료",         start: "16:37", end: nil,     isRange: false, phase: .free, audio: "28_inquiry2-end"),
        ]
    }
}
