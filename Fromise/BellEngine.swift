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

struct ListeningExternal: Identifiable {
    let id = UUID()
    let name: String
    let url: String    // Safari에서 열 다운로드 페이지
}

@MainActor
final class BellEngine: ObservableObject {
    // 표시 상태
    @Published var simTime: Date = Date()
    @Published var started = false
    @Published var running = false
    @Published var activeIndex = 0
    @Published var muted = UserDefaults.standard.bool(forKey: "bell.muted")
    @Published var liveMode = false   // 실제 시각에 맞춰 자동 진행
    @Published var listeningName: String? = nil   // 선택된 듣기평가 음원 이름
    @Published private(set) var bannerText = ""    // 구간 전환 안내 문구
    @Published private(set) var bannerToken = 0    // 값이 바뀌면 뷰가 오버레이를 띄움

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
    let listeningExternals: [ListeningExternal] = [
        .init(name: "시대인재 서바이벌 프로 3월", url: "https://www.sdijc.com/mypage/materials/7"),
        .init(name: "시대인재 서바이벌 프로 4월", url: "https://www.sdijc.com/mypage/materials/12"),
        .init(name: "시대인재 서바이벌 프로 5월", url: "https://www.sdijc.com/mypage/materials/17"),
        .init(name: "대성 더프리미엄 3월", url: "https://m.dsdo.co.kr/pages/board/post-detail.html?boardType=data&categoryNo=24&articleNo=4212"),
        .init(name: "대성 더프리미엄 4월", url: "https://m.dsdo.co.kr/pages/board/post-detail.html?boardType=data&categoryNo=24&articleNo=4220"),
        .init(name: "대성 더프리미엄 5월", url: "https://m.dsdo.co.kr/pages/board/post-detail.html?boardType=data&categoryNo=24&articleNo=4221"),
    ]

    private var startDates: [Date] = []
    private var endDates: [Date?] = []
    private var baseSim = Date()
    private var baseWall = Date()
    private var lastIdx = -1
    private var player: AVPlayer?
    private var audioAnchor: Date?   // 현재 오디오의 0초에 해당하는 simTime

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
        if c < startDates[0].timeIntervalSince1970 { return -1 }   // 시작 전 = 대기
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
    var isWaiting: Bool { activeIndex < 0 }
    var current: BellSegment { schedule[max(0, activeIndex)] }
    var displayName: String { isWaiting ? "" : current.name }
    var progress: Double {
        guard let s0 = startDates.first?.timeIntervalSince1970,
              let eN = startDates.last?.timeIntervalSince1970, eN > s0 else { return 0 }
        let t = min(max(simTime.timeIntervalSince1970, s0), eN)
        return (t - s0) / (eN - s0)
    }
    var statusText: String {
        if isWaiting { return "시작 대기" }
        switch current.phase {
        case .exam: return "시험 중"
        case .prep: return current.name.contains("입실") ? "입실" : "준비"
        case .free: return current.name
        }
    }
    var nextCountdown: String? {
        guard running else { return nil }
        if isWaiting {
            let rem = startDates[0].timeIntervalSince(simTime)
            guard rem > 0 else { return nil }
            return "\(schedule[0].name)까지 " + Self.fmtDur(rem)
        }
        guard activeIndex >= 0, activeIndex + 1 < schedule.count, let end = endDates[activeIndex] else { return nil }
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
        liveMode = false
        setupSession()
        started = true; running = true; rebase()
        lastIdx = idx(at: simTime); activeIndex = lastIdx
        syncListeningFired()
        play(lastIdx)
        fireBanner(lastIdx)
    }
    func reset() {
        liveMode = false
        running = false; started = false
        simTime = startDates.first ?? Date()
        lastIdx = idx(at: simTime); activeIndex = lastIdx
        listeningFired = false
        stopAudio()
    }
    func jump(to i: Int) {
        guard i >= 0, i < schedule.count else { return }
        liveMode = false
        setupSession()
        simTime = startDates[i]; running = true; started = true; rebase()
        lastIdx = i; activeIndex = i
        syncListeningFired()
        stopAudio()
        if i == englishListeningIndex, listeningURL != nil { listeningFired = true; playListening() }
        else { play(i) }
        fireBanner(i)
    }

    /// 실시간 모드 토글 — 켜면 현재 실제 시각에 맞춰 자동 진행
    func setLive(_ on: Bool) {
        if on {
            liveMode = true
            setupSession()
            started = true; running = true
            simTime = Date(); rebase()
            lastIdx = idx(at: simTime); activeIndex = lastIdx
            syncListeningFired()
            stopAudio()
            if lastIdx >= 0 { fireBanner(lastIdx) }   // 대기(시작 전)면 아무것도 표시 안 함
        } else {
            reset()
        }
    }
    func toggleMute() {
        muted.toggle()
        UserDefaults.standard.set(muted, forKey: "bell.muted")
        player?.volume = muted ? 0 : 1   // 재생은 그대로, 볼륨만 0↔1
    }

    private func rebase() { baseSim = simTime; baseWall = Date() }

    /// 뷰의 타이머에서 0.25초마다 호출
    func tick() {
        guard running else { return }
        let elapsed = Date().timeIntervalSince(baseWall)
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

    /// 앱이 다시 활성화될 때 — 현재 시각으로 갱신하고, 그 위치에 맞춰 재개(초과분 건너뜀)
    func handleForeground() {
        guard running else { return }
        let elapsed = Date().timeIntervalSince(baseWall)
        simTime = baseSim.addingTimeInterval(elapsed)
        recompute()                     // 백그라운드 동안 구간이 넘어갔으면 새 안내음으로 교체
        setupSession()
        if let p = player { seekAligned(p) }
    }
    private func recompute() {
        let n = idx(at: simTime)
        if n != lastIdx {
            lastIdx = n; activeIndex = n
            if n >= 0 {
                fireBanner(n)
                if running { play(n) }   // 음소거여도 재생(볼륨 0), 끄면 다시 들림
            }
        }
    }

    private func bannerString(_ i: Int) -> String {
        guard i >= 0 else { return "" }
        let seg = schedule[i]
        if i == schedule.count - 1 { return "시험 종료" }
        if seg.isRange && seg.phase == .exam && !seg.name.contains("듣기") { return seg.name + " 시작" }
        return seg.name
    }
    private func fireBanner(_ i: Int) { bannerText = bannerString(i); bannerToken &+= 1 }

    // MARK: 듣기평가
    var englishListeningIndex: Int { schedule.firstIndex { $0.name.contains("영어 듣기") } ?? 14 }
    func setListening(_ p: ListeningPreset) {
        let base = (p.file as NSString).deletingPathExtension
        let bundle = Bundle.main.url(forResource: base, withExtension: "mp3", subdirectory: "listening")
                  ?? Bundle.main.url(forResource: base, withExtension: "mp3")
        listeningURL = bundle ?? URL(string: Self.listeningBase + p.file)   // 번들에 있으면 웹 안 씀
        listeningName = p.name
        listeningFired = false
    }
    /// 파일 앱에서 고른 MP3 → 앱 내부로 복사해 사용
    func setCustomListening(_ picked: URL) {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("listening_custom.mp3")
        try? FileManager.default.removeItem(at: dst)
        do {
            try FileManager.default.copyItem(at: picked, to: dst)
            listeningURL = dst
            listeningName = picked.deletingPathExtension().lastPathComponent
            listeningFired = false
        } catch { }
    }
    func clearListening() { listeningURL = nil; listeningName = nil; listeningFired = false }
    private func syncListeningFired() {
        listeningFired = simTime >= todayAt(listeningFireTime)
    }
    private func checkListening() {
        guard listeningURL != nil, !listeningFired, running else { return }
        if simTime >= todayAt(listeningFireTime) { listeningFired = true; playListening() }
    }
    private func playListening() {
        guard let u = listeningURL else { return }
        playURL(u, anchor: todayAt(listeningFireTime))
    }

    // MARK: 오디오
    private func setupSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [])
        try? s.setActive(true)
    }
    private func bundleURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "audio")
    }
    private func play(_ i: Int) {
        guard let name = schedule[i].audio else { return }
        guard simTime >= startDates[i].addingTimeInterval(-1) else { return }  // 구간 시작 전이면 재생 안 함
        let anchor = startDates[i]   // 이 안내음의 0초 = 구간 시작 시각
        if let b = bundleURL(name) { playURL(b, anchor: anchor) }
        else if let r = URL(string: Self.audioBase + name + ".mp3") { playURL(r, anchor: anchor) }
    }
    private func playURL(_ u: URL, anchor: Date) {
        setupSession()
        audioAnchor = anchor
        let p = AVPlayer(playerItem: AVPlayerItem(url: u))
        p.automaticallyWaitsToMinimizeStalling = false
        p.volume = muted ? 0 : 1
        player = p
        seekAligned(p)            // 현재 시각 − 시작 시각 만큼 건너뛰고 재생
    }
    /// 현재 simTime 기준으로 음원 위치를 맞추고 재생(초과분은 자동으로 건너뜀)
    private func seekAligned(_ p: AVPlayer) {
        guard let anchor = audioAnchor else { p.play(); return }
        let offset = max(0, simTime.timeIntervalSince(anchor))
        let t = CMTime(seconds: offset, preferredTimescale: 600)
        p.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { _ in p.play() }
    }
    private func stopAudio() { player?.pause(); player = nil; audioAnchor = nil }

    // MARK: 스케줄 정의 (웹 HTML과 동일)
    static func makeSchedule() -> [BellSegment] {
        [
            .init(name: "수험생 입실 완료",   start: "08:10", end: "08:25", isRange: false, phase: .free, audio: "01_student-entry"),
            .init(name: "국어 예비령",        start: "08:25", end: "08:35", isRange: false, phase: .prep, audio: "02_korean-pre"),
            .init(name: "국어 준비령",        start: "08:35", end: "08:40", isRange: false, phase: .prep, audio: "03_korean-ready"),
            .init(name: "국어",              start: "08:40", end: "09:50", isRange: true,  phase: .exam, audio: "04_korean-start"),
            .init(name: "국어 종료 10분 전",  start: "09:50", end: "10:00", isRange: false, phase: .exam, audio: "05_korean-10min"),
            .init(name: "국어 종료",          start: "10:00", end: "10:20", isRange: false, phase: .free, audio: "06_korean-end"),
            .init(name: "수학 예비령",        start: "10:20", end: "10:25", isRange: false, phase: .prep, audio: "07_math-pre"),
            .init(name: "수학 준비령",        start: "10:25", end: "10:30", isRange: false, phase: .prep, audio: "08_math-ready"),
            .init(name: "수학",              start: "10:30", end: "12:00", isRange: true,  phase: .exam, audio: "09_math-start"),
            .init(name: "수학 종료 10분 전",  start: "12:00", end: "12:10", isRange: false, phase: .exam, audio: "10_math-10min"),
            .init(name: "수학 종료 / 중식",   start: "12:10", end: "12:55", isRange: false, phase: .free, audio: "11_math-end"),
            .init(name: "감독관 입실",        start: "12:55", end: "13:00", isRange: false, phase: .prep, audio: "12_english-pre"),
            .init(name: "영어 예비령",        start: "13:00", end: "13:05", isRange: false, phase: .prep, audio: "13_english-ready"),
            .init(name: "영어 준비령",        start: "13:05", end: "13:07", isRange: false, phase: .prep, audio: "14_english-start"),
            .init(name: "영어 듣기 시작",     start: "13:07", end: "14:10", isRange: true,  phase: .exam, audio: nil),
            .init(name: "영어 종료 10분 전",  start: "14:10", end: "14:20", isRange: false, phase: .exam, audio: "15_english-10min"),
            .init(name: "영어 종료",          start: "14:20", end: "14:40", isRange: false, phase: .free, audio: "16_english-end"),
            .init(name: "한국사 예비령",      start: "14:40", end: "14:45", isRange: false, phase: .prep, audio: "17_history-pre"),
            .init(name: "한국사 준비령",      start: "14:45", end: "14:50", isRange: false, phase: .prep, audio: "18_history-ready"),
            .init(name: "한국사",            start: "14:50", end: "15:15", isRange: true,  phase: .exam, audio: "19_history-start"),
            .init(name: "한국사 종료 5분 전", start: "15:15", end: "15:20", isRange: false, phase: .exam, audio: "20_history-5min"),
            .init(name: "한국사 종료",        start: "15:20", end: "15:30", isRange: false, phase: .free, audio: "21_history-end"),
            .init(name: "탐구 준비령",        start: "15:30", end: "15:35", isRange: false, phase: .prep, audio: "22_inquiry-ready"),
            .init(name: "탐구 제1선택",       start: "15:35", end: "16:00", isRange: true,  phase: .exam, audio: "23_inquiry1-start"),
            .init(name: "탐구1 종료 5분 전",  start: "16:00", end: "16:05", isRange: false, phase: .exam, audio: "24_inquiry1-5min"),
            .init(name: "탐구1 종료",         start: "16:05", end: "16:07", isRange: false, phase: .free, audio: "25_inquiry1-end"),
            .init(name: "탐구 제2선택",       start: "16:07", end: "16:32", isRange: true,  phase: .exam, audio: "26_inquiry2-start"),
            .init(name: "탐구2 종료 5분 전",  start: "16:32", end: "16:37", isRange: false, phase: .exam, audio: "27_inquiry2-5min"),
            .init(name: "탐구2 종료",         start: "16:37", end: nil,     isRange: false, phase: .free, audio: "28_inquiry2-end"),
        ]
    }
}
