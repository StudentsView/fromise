import Foundation
import Network

// ─────────────────────────────────────────────────────────────
//  SyncQueue — 연결이 안정적일 때만 Supabase에 업로드
//  · 오프라인/불안정: 값은 기기에 영속 보관(앱 꺼도 유지), 업로드는 보류
//  · 온라인 복귀: 자동 flush. 업로드 실패 시 큐에 그대로 남겨 재시도(Degraded Mode)
// ─────────────────────────────────────────────────────────────
@MainActor
final class SyncQueue: ObservableObject {
    static let shared = SyncQueue()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let mq = DispatchQueue(label: "fromise.netmon")
    private let d = UserDefaults.standard

    // 현재 세션 기준 업로드 동작 (RootFlow에서 로그인 시 주입)
    var uploadNickname: ((String) async -> Bool)?
    var uploadBirth: ((Date) async -> Bool)?
    var uploadPlanner: (() async -> Bool)?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in self?.setOnline(ok) }
        }
        monitor.start(queue: mq)
    }

    private func setOnline(_ ok: Bool) {
        let was = isOnline
        isOnline = ok
        if ok && !was { Task { await flush() } }   // 연결 복귀 → 자동 업로드
    }

    // MARK: 큐 적재 (값은 영속)
    func queueNickname(_ n: String) { d.set(n, forKey: "sync.nick");  Task { await flush() } }
    func queueBirth(_ date: Date)   { d.set(date, forKey: "sync.birth"); Task { await flush() } }
    func queuePlanner()             { d.set(true, forKey: "sync.planner"); Task { await flush() } }

    // MARK: 업로드 시도 (성공한 항목만 큐에서 제거)
    func flush() async {
        guard isOnline else { return }
        if let n = d.string(forKey: "sync.nick") {
            if await uploadNickname?(n) == true { d.removeObject(forKey: "sync.nick") }
        }
        if let b = d.object(forKey: "sync.birth") as? Date {
            if await uploadBirth?(b) == true { d.removeObject(forKey: "sync.birth") }
        }
        if d.bool(forKey: "sync.planner") {
            if await uploadPlanner?() == true { d.removeObject(forKey: "sync.planner") }
        }
    }
}
