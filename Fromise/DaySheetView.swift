import SwiftUI
import PencilKit

// ─────────────────────────────────────────────────────────────
//  DaySheetView.swift — 하루 한 장 · 클린 리디자인 (카드 기반)
//  기능 동일: 입력/그리기, 달성률(자동), 목표·공부시간, 할 일, 체크리스트,
//  타임테이블, 펜슬 캔버스(긋는 중 스크롤 잠금 + 텍스트 차단).
// ─────────────────────────────────────────────────────────────

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private let HL_NAMES = ["노랑", "연두", "주홍", "보라", "분홍", "하늘"]

struct DaySheetView: View {
    let key: String
    @EnvironmentObject var store: PlannerStore

    @State private var mode: PlannerMode = .type
    @State private var drawTool: DrawTool = .pen
    @State private var hlHex: UInt = HL_HEX[0]
    @State private var isDrawing = false
    @State private var contentH: CGFloat = 1
    // 타임테이블: 드래그로 "선택"만 → 팔레트에서 색을 골라야 칠해짐 (오조작 방지 · 웹과 동일)
    @State private var ttSelStart: Int? = nil           // 드래그 시작 셀 인덱스(row*6+col)
    @State private var ttSelected: Set<String> = []     // 현재 선택된 셀 키들("row_col")
    @State private var showPalette = false              // 색 팔레트(팝오버) 표시 여부
    @State private var paletteAnchor: UnitPoint = .center  // 손 뗀 위치 기준 팝오버 앵커
    @State private var ttCustomColor: Color = Color(hex: HL_HEX[0])  // 직접 선택 색
    @State private var penOnly = false   // 손가락 그리기 기본 허용 (iPhone은 항상 false)
    @State private var clearToken = 0     // 전체 지우기 강제 동기화용
    @State private var showClearAlert = false
    // 도구별 두께 단계(0=얇게,1=보통,2=굵게) — 도구 전환 시 각자 기억
    @State private var penLevel = 1
    @State private var hlLevel = 1
    @State private var eraserLevel = 1

    private let penWidths:    [CGFloat] = [2, 4, 7]
    private let hlWidths:     [CGFloat] = [12, 20, 30]
    private let eraserWidths: [CGFloat] = [15, 30, 55]

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var day: Binding<DayData> { store.binding(key) }
    private var activeColor: Color { drawTool == .highlighter ? Color(hex: hlHex) : Color(hex: 0x222222) }
    private var activePKTool: PKTool {
        pkTool(for: drawTool, color: activeColor,
               penWidth: penWidths[penLevel], hlWidth: hlWidths[hlLevel],
               eraserWidth: eraserWidths[eraserLevel])
    }
    private var thicknessLevel: Int {
        switch drawTool { case .pen: return penLevel; case .highlighter: return hlLevel; case .eraser: return eraserLevel }
    }
    private var thicknessBinding: Binding<Int> {
        Binding(get: { thicknessLevel }, set: { v in
            switch drawTool { case .pen: penLevel = v; case .highlighter: hlLevel = v; case .eraser: eraserLevel = v }
        })
    }
    private func clearDrawing() {
        day.wrappedValue.drawing = PKDrawing()
        clearToken &+= 1            // 캔버스 강제 비우기
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                ZStack(alignment: .topLeading) {
                    content
                        .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
                        .allowsHitTesting(mode == .type)
                    PencilCanvas(drawing: day.drawing, isDrawing: $isDrawing,
                                 tool: activePKTool,
                                 isActive: mode == .draw, penOnly: isPad && penOnly,
                                 clearToken: clearToken)
                        .frame(height: max(contentH, 1))
                        .allowsHitTesting(mode == .draw)
                }
            }
            .scrollDisabled(mode == .draw && (!(isPad && penOnly) || isDrawing))
            .onPreferenceChange(HeightKey.self) { contentH = $0 }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(titleText).navigationBarTitleDisplayMode(.inline)
        .alert("그림을 모두 지울까요?", isPresented: $showClearAlert) {
            Button("취소", role: .cancel) {}
            Button("지우기", role: .destructive) { clearDrawing() }
        } message: {
            Text("이 날짜에 그린 그림이 모두 삭제돼요.")
        }
    }

    // MARK: 상단 도구막대
    private var toolbar: some View {
        VStack(spacing: 10) {
            Picker("", selection: $mode) {
                Text("입력").tag(PlannerMode.type)
                Text("그리기").tag(PlannerMode.draw)
            }
            .pickerStyle(.segmented)

            if mode == .draw {
                HStack(spacing: 8) {
                    toolBtn(.pen, .pen); highlighterBtn; toolBtn(.eraser, .eraser)
                    thicknessMenu
                    Spacer()
                    if isPad {
                        Button { penOnly.toggle() } label: {
                            Text(penOnly ? "Apple Pencil ON" : "Apple Pencil OFF")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(penOnly ? .white : Theme.ink2)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(penOnly ? Theme.ink : Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: penOnly ? 0 : 1))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    Button { showClearAlert = true } label: {
                        Text("전체 지우기").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.danger)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.paper)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }
    private func toolBtn(_ t: DrawTool, _ icon: AppIcon) -> some View {
        Button { drawTool = t } label: {
            Icon(icon, size: 16).foregroundStyle(drawTool == t ? .white : Theme.ink)
                .frame(width: 36, height: 30)
                .background(drawTool == t ? Theme.ink : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
    // 형광펜: 한 번 탭=선택, 선택된 상태에서 다시 탭=색 팔레트 드롭다운.
    // 아이콘 색은 현재 선택된 형광펜 색으로 표시.
    @ViewBuilder
    private var highlighterBtn: some View {
        let selected = drawTool == .highlighter
        let icon = Icon(.highlighter, size: 16)
            .foregroundStyle(selected ? Color(hex: hlHex) : Theme.ink)   // 미선택 시 검정 유지(가독성)
            .frame(width: 36, height: 30)
            .background(selected ? Theme.ink : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        if selected {
            Menu {
                Picker("형광펜 색", selection: $hlHex) {
                    ForEach(Array(HL_HEX.enumerated()), id: \.offset) { i, hex in
                        Text(HL_NAMES[i]).tag(hex)
                    }
                }
            } label: { icon }
        } else {
            Button { drawTool = .highlighter } label: { icon }
        }
    }
    // 두께 점 버튼 → 탭하면 두께 3단계 드롭다운 (현재 도구에 적용)
    private var thicknessMenu: some View {
        Menu {
            Picker("두께", selection: thicknessBinding) {
                Text("얇게").tag(0)
                Text("보통").tag(1)
                Text("굵게").tag(2)
            }
        } label: {
            Circle().fill(Theme.ink)
                .frame(width: CGFloat(5 + thicknessLevel * 4), height: CGFloat(5 + thicknessLevel * 4))
                .frame(width: 36, height: 30)
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
    // MARK: 본문 (카드들)
    private var content: some View {
        VStack(spacing: 14) {
            summaryCard
            tasksCard
            checklistCard
            timetableCard
            Color.clear.frame(height: 28)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // 달성률 + 목표·공부시간
    private var summaryCard: some View {
        let pct = store.day(key).achievement
        return HStack(spacing: 16) {
            ProgressRing(percent: pct)
            VStack(alignment: .leading, spacing: 10) {
                Text("오늘 달성률").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.ink)
                HStack(spacing: 12) {
                    timeField("목표", get: { store.day(key).goalMinutes }, set: { day.wrappedValue.goalMinutes = $0 })
                    netDisplay
                }
                .fixedSize(horizontal: true, vertical: false)   // 목표/공부 가로 유지(세로 줄바꿈 방지)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 18, radius: 20)
    }
    /// 순공시간 — 타임테이블 색칠로 자동 계산(입력 불가). 한 칸 = 10분
    private var netDisplay: some View {
        let mins = store.day(key).netMinutes ?? 0
        return HStack(spacing: 4) {
            Text("공부").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.ink3)
            Text("\(mins/60)h \(mins%60)m")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("자동").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.good)
        }
    }
    private func timeField(_ name: String, get: @escaping () -> Int?, set: @escaping (Int?) -> Void) -> some View {
        let mins = get() ?? 0
        let hB = Binding<Int>(get: { mins / 60 }, set: { let t = $0 * 60 + mins % 60; set(t == 0 ? nil : t) })
        let mB = Binding<Int>(get: { mins % 60 }, set: { let t = mins / 60 * 60 + $0; set(t == 0 ? nil : t) })
        return HStack(spacing: 4) {
            Text(name).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.ink3).lineLimit(1)
            numChip(hB); Text("h").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink3)
            numChip(mB); Text("m").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink3)
        }
    }
    private func numChip(_ b: Binding<Int>) -> some View {
        TextField("0", value: b, format: .number)
            .keyboardType(.numberPad).multilineTextAlignment(.center)
            .font(.system(size: 14, weight: .bold)).frame(width: 26).padding(.vertical, 4)
            .background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // 할 일
    private var tasksCard: some View {
        sectionCard("오늘 할 일") {
            VStack(spacing: 6) {
                ForEach(day.tasks) { $task in
                    HStack(spacing: 9) {
                        checkBox(task.done) { $task.done.wrappedValue.toggle() }
                        TextField("공부할 내용", text: $task.text)
                            .font(.system(size: 14, weight: .semibold))
                            .strikethrough(task.done, color: Theme.ink3)
                            .foregroundStyle(task.done ? Theme.ink3 : Theme.ink)
                            .padding(.vertical, 3).padding(.horizontal, 5)
                            .background(task.hl.map { Color(hex: $0).opacity(0.5) } ?? .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Menu {
                            ForEach(Array(HL_HEX.enumerated()), id: \.offset) { i, hex in
                                Button(HL_NAMES[i]) { $task.hl.wrappedValue = hex }
                            }
                            Button("지움", role: .destructive) { $task.hl.wrappedValue = nil }
                        } label: {
                            Icon(.highlighter, size: 13).foregroundStyle(Theme.ink3).frame(width: 26, height: 26)
                        }
                        delBtn { day.wrappedValue.tasks.removeAll { $0.id == task.id } }
                    }
                }
                addRow("할 일 추가") { day.wrappedValue.tasks.append(PlannerTask()) }
            }
        }
    }

    // 체크리스트
    private var checklistCard: some View {
        sectionCard("체크리스트") {
            VStack(spacing: 6) {
                ForEach(day.checklist) { $item in
                    HStack(spacing: 9) {
                        checkBox(item.done) { $item.done.wrappedValue.toggle() }
                        TextField("할 일", text: $item.text)
                            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                        delBtn { day.wrappedValue.checklist.removeAll { $0.id == item.id } }
                    }
                }
                addRow("체크 항목 추가") { day.wrappedValue.checklist.append(CheckItem()) }
            }
        }
    }

    // 타임테이블 (06시~, 22행 × 6칸) — 드래그로 "선택" 후 팔레트에서 색을 골라 칠하기
    private var timetableCard: some View {
        sectionCard("타임 테이블") {
            VStack(spacing: 10) {
                if mode == .type {
                    HStack(spacing: 6) {
                        Icon(.highlighter, size: 12).foregroundStyle(Theme.ink3)
                        Text("드래그해서 색을 칠하면 순공시간이 올라가요.")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink3)
                        Spacer()
                    }
                }
                GeometryReader { geo in
                    let labelW: CGFloat = 26
                    let rowH: CGFloat = 24
                    let cellW = max((geo.size.width - labelW) / 6, 1)
                    VStack(spacing: 0) {
                        ForEach(0..<22, id: \.self) { r in
                            HStack(spacing: 0) {
                                Text("\(((6 + r + 11) % 12) + 1)")
                                    .font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.ink3)
                                    .frame(width: labelW, height: rowH)
                                ForEach(0..<6, id: \.self) { col in
                                    let ck = "\(r)_\(col)"
                                    let painted = store.day(key).timetable[ck]
                                    let isSel = ttSelected.contains(ck)
                                    Rectangle()
                                        .fill(painted.map { Color(hex: $0) } ?? Color.clear)
                                        .frame(maxWidth: .infinity).frame(height: rowH)
                                        .overlay(isSel ? Theme.select.opacity(0.20) : Color.clear)
                                        .overlay(Rectangle().stroke(isSel ? Theme.select : Theme.line.opacity(0.5),
                                                                    lineWidth: isSel ? 1.5 : 0.5))
                                        .animation(.easeOut(duration: 0.1), value: isSel)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in updateSelection(v.location, labelW: labelW, cellW: cellW, rowH: rowH) }
                            .onEnded { v in endSelection(v.location, size: geo.size) }
                    )
                }
                .frame(height: 24 * 22)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                .popover(isPresented: $showPalette, attachmentAnchor: .point(paletteAnchor), arrowEdge: .top) {
                    timetablePalette.presentationCompactAdaptation(.popover)
                }
                .onChange(of: showPalette) { _, shown in
                    if !shown { ttSelected = []; ttSelStart = nil }   // 팝오버 닫히면 선택 해제
                }
            }
        }
    }

    // 색 팔레트 (웹 팝오버와 동일 구성: 6색 + 직접 선택 + 지움)
    private var timetablePalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("선택한 시간에 칠할 색")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.ink3)
            HStack(spacing: 10) {
                ForEach(Array(HL_HEX.enumerated()), id: \.offset) { _, hex in
                    Button { applyTTColor(hex) } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    ColorPicker("", selection: $ttCustomColor, supportsOpacity: false).labelsHidden()
                    Text("직접 선택").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 8)
                Button { applyTTColor(nil) } label: {
                    Text("지움").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 264)
        .onChange(of: ttCustomColor) { _, c in applyTTColor(hex(from: c)) }
    }

    /// 드래그 위치 → 셀 인덱스 범위로 "선택"만 함 (웹의 .sel 토글과 동일, 색칠 X)
    private func updateSelection(_ loc: CGPoint, labelW: CGFloat, cellW: CGFloat, rowH: CGFloat) {
        if showPalette { return }   // 팔레트 떠 있는 동안엔 무시
        let x = loc.x - labelW
        let col = Int(x / cellW), row = Int(loc.y / rowH)
        guard x >= 0, (0..<6).contains(col), (0..<22).contains(row) else { return }
        let idx = row * 6 + col
        if ttSelStart == nil { ttSelStart = idx }
        let lo = min(ttSelStart!, idx), hi = max(ttSelStart!, idx)
        var sel = Set<String>(); sel.reserveCapacity(hi - lo + 1)
        for i in lo...hi { sel.insert("\(i / 6)_\(i % 6)") }
        ttSelected = sel
    }

    /// 드래그 끝 → 선택이 있으면 손 뗀 위치에 색 팔레트를 띄움
    private func endSelection(_ loc: CGPoint, size: CGSize) {
        ttSelStart = nil
        guard !ttSelected.isEmpty else { return }
        let gx = min(max(loc.x, 0), size.width)
        let gy = min(max(loc.y, 0), size.height)
        paletteAnchor = UnitPoint(x: size.width  > 0 ? gx / size.width  : 0.5,
                                  y: size.height > 0 ? gy / size.height : 0.5)
        showPalette = true
    }

    /// 선택된 셀들에 색 적용(nil이면 지우기) → 순공시간 자동 반영 후 팔레트 닫기
    private func applyTTColor(_ hex: UInt?) {
        guard !ttSelected.isEmpty else { showPalette = false; return }
        var d = day.wrappedValue
        for ck in ttSelected {
            if let hex { d.timetable[ck] = hex } else { d.timetable[ck] = nil }
        }
        d.netMinutes = d.timetable.count > 0 ? d.timetable.count * 10 : nil   // 칸당 10분
        day.wrappedValue = d
        showPalette = false   // onChange(showPalette)에서 선택 해제됨
    }

    /// SwiftUI Color → 0xRRGGBB
    private func hex(from color: Color) -> UInt {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        let R = UInt((max(0, min(1, r)) * 255).rounded())
        let G = UInt((max(0, min(1, g)) * 255).rounded())
        let B = UInt((max(0, min(1, b)) * 255).rounded())
        return (R << 16) | (G << 8) | B
    }

    // MARK: 공용 조각
    private func sectionCard<C: View>(_ title: String, @ViewBuilder _ inner: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
            inner()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, radius: 20)
    }
    private func checkBox(_ on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(on ? Theme.good : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Theme.good : Theme.line, lineWidth: 1.5))
                    .frame(width: 20, height: 20)
                if on { Icon(.check, size: 11, weight: .bold).foregroundStyle(.white) }
            }
        }.buttonStyle(.plain)
    }
    private func delBtn(_ tap: @escaping () -> Void) -> some View {
        Button(action: tap) { Text("✕").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink3).frame(width: 22, height: 22) }
            .buttonStyle(.plain)
    }
    private func addRow(_ title: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                Icon(.plus, size: 11).foregroundStyle(Theme.ink3)
                Text(title).font(.system(size: 12.5, weight: .bold)).foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity).padding(9)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
        .buttonStyle(.plain).padding(.top, 4)
    }

    private var titleText: String {
        let c = Calendar.current.dateComponents([.month, .day, .weekday], from: PKey.date(key))
        let wk = ["일","월","화","수","목","금","토"][(c.weekday ?? 1) - 1]
        return "\(c.month ?? 0)월 \(c.day ?? 0)일 (\(wk))"
    }
}
