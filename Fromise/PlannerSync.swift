import Foundation
import Supabase
import PencilKit

// ─────────────────────────────────────────────────────────────
//  PlannerSync.swift — 웹(대수능닷컴) user_data 와 동일 구조로 플래너 읽기/쓰기
//  · 읽기: planner.days → 앱 DayData
//  · 쓰기: 앱이 다루는 필드만 갱신, 웹의 events·draw(손글씨)·studylog 는 보존 후 upsert
//  웹 구조: user_data { user_id, planner:{events,days,seeded}, studylog, updated_at }
//          days["YYYY-MM-DD"] = { tasks, checklist, timetable, draw, goal, net }
// ─────────────────────────────────────────────────────────────

// 임의 JSON 보존용
indirect enum JSONv: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONv]), object([String: JSONv])
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONv].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONv].self) { self = .object(o) }
        else { self = .null }
    }
    func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
    var obj: [String: JSONv]? { if case .object(let o) = self { return o }; return nil }
    var arr: [JSONv]? { if case .array(let a) = self { return a }; return nil }
    var str: String? { if case .string(let s) = self { return s }; return nil }
    var num: Double? { if case .number(let n) = self { return n }; return nil }
    var boolV: Bool? { if case .bool(let b) = self { return b }; return nil }
}

private func hexToUInt(_ s: String?) -> UInt? {
    guard let raw = s else { return nil }
    let h = raw.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
    return UInt(h, radix: 16)
}
private func uintToHex(_ u: UInt) -> String { String(format: "#%06X", u) }

enum PlannerSync {
    private struct Row: Decodable { let planner: JSONv?; let studylog: JSONv? }
    private struct SavePayload: Encodable {
        let user_id: String
        let planner: JSONv
        let studylog: JSONv
        let updated_at: String
    }

    // 마지막 로드 시점의 원본 보존 (병합 저장용)
    private static var rawPlanner: JSONv = .object([:])
    private static var rawStudylog: JSONv = .null
    private static var rawDays: [String: JSONv] = [:]
    private static var ready = false
    private static var saveWork: DispatchWorkItem?

    // MARK: 읽기
    static func load(into store: PlannerStore) async {
        guard let uid = supabase.auth.currentUser?.id.uuidString else { return }
        do {
            let rows: [Row] = try await supabase
                .from("user_data").select("planner,studylog")
                .eq("user_id", value: uid).execute().value
            let planner = rows.first?.planner ?? .object([:])
            rawPlanner = planner
            rawStudylog = rows.first?.studylog ?? .null
            rawDays = planner.obj?["days"]?.obj ?? [:]
            var converted: [String: DayData] = [:]
            for (k, dj) in rawDays { converted[k] = dayData(from: dj) }
            await MainActor.run { store.days = converted }
            ready = true
        } catch { ready = true }   // 행 없음/오류 시에도 이후 저장은 허용
    }

    static func clear() {
        saveWork?.cancel(); saveWork = nil
        rawPlanner = .object([:]); rawStudylog = .null; rawDays = [:]; ready = false
    }

    // MARK: 쓰기 (디바운스)
    static func scheduleSave(from store: PlannerStore) {
        saveWork?.cancel()
        let w = DispatchWorkItem {
            Task { @MainActor in
                if SyncQueue.shared.isOnline { Task { await save(from: store) } }
                else { SyncQueue.shared.queuePlanner() }
            }
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    static func save(from store: PlannerStore) async {
        guard ready, let uid = supabase.auth.currentUser?.id.uuidString else { return }
        let days = await MainActor.run { store.days }

        var daysObj: [String: JSONv] = [:]
        for (k, d) in days { daysObj[k] = dayJSON(key: k, d) }
        // 앱에 없지만 원본에만 있던 날짜(=드로잉만 있는 날 등)도 보존
        for (k, raw) in rawDays where daysObj[k] == nil { daysObj[k] = raw }

        var pObj = rawPlanner.obj ?? [:]
        pObj["days"] = .object(daysObj)
        if pObj["events"] == nil { pObj["events"] = .array([]) }
        if pObj["seeded"] == nil { pObj["seeded"] = .bool(true) }
        let plannerJSON = JSONv.object(pObj)

        let payload = SavePayload(user_id: uid, planner: plannerJSON,
                                  studylog: rawStudylog,
                                  updated_at: ISO8601DateFormatter().string(from: Date()))
        do {
            try await supabase.from("user_data").upsert(payload, onConflict: "user_id").execute()
            rawPlanner = plannerJSON; rawDays = daysObj   // 다음 병합 기준 갱신
        } catch { /* 네트워크 오류 — 다음 편집 시 재시도 */ }
    }

    // MARK: 변환
    private static func dayData(from j: JSONv) -> DayData {
        let o = j.obj ?? [:]
        var d = DayData()
        d.tasks = (o["tasks"]?.arr ?? []).map { t in
            let to = t.obj ?? [:]
            return PlannerTask(text: to["text"]?.str ?? "", done: to["done"]?.boolV ?? false, hl: hexToUInt(to["hl"]?.str))
        }
        d.checklist = (o["checklist"]?.arr ?? []).map { c in
            let co = c.obj ?? [:]
            return CheckItem(text: co["text"]?.str ?? "", done: co["done"]?.boolV ?? false)
        }
        d.goalMinutes = o["goal"]?.num.map { Int($0) }
        d.netMinutes = o["net"]?.num.map { Int($0) }
        var tt: [String: UInt] = [:]
        for (k, v) in (o["timetable"]?.obj ?? [:]) { if let u = hexToUInt(v.str) { tt[k] = u } }
        d.timetable = tt
        if !tt.isEmpty { d.netMinutes = tt.count * 10 }   // 칸당 10분 (웹과 동일 규칙)
        // 앱 손글씨 복원 (웹의 draw 와 별개 키)
        if let s = o["draw_ios"]?.str, let data = Data(base64Encoded: s),
           let dr = try? PKDrawing(data: data) {
            d.drawing = dr
        }
        return d
    }

    private static func dayJSON(key: String, _ d: DayData) -> JSONv {
        var o = rawDays[key]?.obj ?? [:]   // draw 등 기존 키 보존
        o["tasks"] = .array(d.tasks.map { t in
            .object([
                "id": .string(t.id.uuidString),
                "text": .string(t.text),
                "done": .bool(t.done),
                "hl": t.hl.map { .string(uintToHex($0)) } ?? .null,
            ])
        })
        o["checklist"] = .array(d.checklist.map { c in
            .object(["id": .string(c.id.uuidString), "text": .string(c.text), "done": .bool(c.done)])
        })
        o["timetable"] = .object(d.timetable.mapValues { .string(uintToHex($0)) })
        o["goal"] = d.goalMinutes.map { .number(Double($0)) } ?? .null
        o["net"] = d.netMinutes.map { .number(Double($0)) } ?? .null
        // 앱 손글씨 저장 (웹의 draw 는 그대로 보존, 별도 키 사용)
        if !d.drawing.strokes.isEmpty {
            o["draw_ios"] = .string(d.drawing.dataRepresentation().base64EncodedString())
        } else {
            o["draw_ios"] = nil
        }
        return .object(o)
    }
}
