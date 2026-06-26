import SwiftUI
import Combine
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────
//  BellView.swift — 모의 수능 타종 (홈/플래너와 같은 종이·잉크 톤)
// ─────────────────────────────────────────────────────────────

struct BellView: View {
    @StateObject private var engine = BellEngine()
    @State private var showEnd = false
    @State private var jump: JumpTarget?
    @State private var showListening = false
    @AppStorage("bell.analog") private var analog = false
    @State private var bannerVisible = false
    @State private var bannerMsg = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var fullscreen = false
    @AppStorage("bell.dark") private var dark = false

    private var skin: BellSkin { dark ? .dark : .light }

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                ZStack(alignment: .bottom) {
                    if landscape {
                        heroLandscape(geo: geo)
                    } else {
                        VStack(spacing: 0) {
                            heroPortrait.padding(.horizontal, 20).padding(.top, 8)
                            Spacer(minLength: 0)
                            // 타종 박스 하단 공백에 320x50 배너 — 스크롤 없이 한 화면 노출
                            AdFitBanner()
                                .frame(width: 320, height: 50)
                                .frame(maxWidth: .infinity)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.bottom, 46)

                        SegmentPanel(engine: engine, jump: $jump, geo: geo)
                    }

                    if bannerVisible {
                        Text(bannerMsg)
                            .font(.system(size: 34, weight: .heavy)).foregroundStyle(skin.ink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 34).padding(.vertical, 24)
                            .background(skin.card)
                            .overlay(RoundedRectangle(cornerRadius: 22).stroke(skin.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                            .allowsHitTesting(false)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(skin.paper.ignoresSafeArea())
            }
            .navigationTitle("모의 수능 타종")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(skin.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(dark ? .dark : .light, for: .navigationBar)
        }
        .onReceive(ticker) { _ in engine.tick() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { engine.handleForeground() }
        }
        .onChange(of: engine.bannerToken) { _, _ in
            bannerMsg = engine.bannerText
            withAnimation(.easeOut(duration: 0.25)) { bannerVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeIn(duration: 0.3)) { bannerVisible = false }
            }
        }
        .sheet(isPresented: $showListening) {
            ListeningSheet(engine: engine).environment(\.bellSkin, skin)
        }
        .sheet(item: $jump) { jt in
            JumpSheet(seg: engine.schedule[jt.index],
                      range: engine.rangeText(jt.index),
                      started: engine.started) {
                engine.jump(to: jt.index); jump = nil
            }
            .environment(\.bellSkin, skin)
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.visible)
        }
        .alert("처음 상태로 돌아갈까요?", isPresented: $showEnd) {
            Button("취소", role: .cancel) {}
            Button("종료", role: .destructive) { engine.reset() }
        }
        .fullScreenCover(isPresented: $fullscreen) {
            FullClockView(engine: engine, analog: analog)
                .environment(\.bellSkin, skin)
        }
        .environment(\.bellSkin, skin)
    }

    // MARK: 조각들
    private var clockToggleBar: some View {
        HStack(spacing: 8) {
            Button { fullscreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(skin.ink2)
                    .frame(width: 34, height: 34)
                    .background(skin.paper)
                    .overlay(Circle().stroke(skin.line, lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button { dark.toggle() } label: {
                Image(systemName: dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(skin.ink2)
                    .frame(width: 34, height: 34)
                    .background(skin.paper)
                    .overlay(Circle().stroke(skin.line, lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 2) {
                clockToggle("디지털", !analog) { analog = false }
                clockToggle("아날로그", analog) { analog = true }
            }
            .padding(2)
            .background(skin.paper)
            .overlay(Capsule().stroke(skin.line, lineWidth: 1))
            .clipShape(Capsule())
        }
    }

    private var statusChip: some View {
        HStack(spacing: 7) {
            Circle().fill(BellPalette.subject(engine.current.subject)).frame(width: 8, height: 8)
            if let subj = engine.current.subject {
                Text(subj).font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(BellPalette.subject(subj))
                Text("·").foregroundStyle(skin.ink3)
            }
            Text(engine.statusText).font(.system(size: 13, weight: .bold)).foregroundStyle(skin.ink2)
        }
        .padding(.horizontal, 13).padding(.vertical, 7)
        .background(skin.paper)
        .overlay(Capsule().stroke(skin.line, lineWidth: 1))
        .clipShape(Capsule())
    }

    private func clockView(size: CGFloat) -> some View {
        Group {
            if analog {
                AnalogClock(time: engine.simTime).frame(width: size, height: size)
            } else {
                Text(engine.timeText)
                    .font(.system(size: size * 0.27, weight: .light, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(skin.ink)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: size)
        .frame(maxWidth: .infinity)
    }

    private var nameCountdown: some View {
        VStack(spacing: 4) {
            Text(engine.displayName)
                .font(.system(size: 16, weight: .heavy)).foregroundStyle(skin.ink)
            Text(engine.nextCountdown ?? " ")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(skin.ink3)
                .animation(.none, value: engine.nextCountdown)
        }
    }

    private var progressBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(skin.line)
                Capsule().fill(skin.ink).frame(width: max(0, g.size.width * engine.progress))
            }
        }
        .frame(height: 8)
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeBtn("수동", !engine.liveMode) { engine.setLive(false) }
            modeBtn("실시간", engine.liveMode) { engine.setLive(true) }
        }
        .padding(2)
        .background(skin.paper)
        .overlay(Capsule().stroke(skin.line, lineWidth: 1))
        .clipShape(Capsule())
    }
    private func modeBtn(_ label: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(label).font(.system(size: 12.5, weight: .heavy))
                .foregroundStyle(on ? skin.paper : skin.ink2)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? skin.ink : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            if engine.liveMode {
                HStack(spacing: 7) {
                    Circle().fill(skin.good).frame(width: 8, height: 8)
                    Text("실제 시각에 맞춰 자동 진행 중")
                        .font(.system(size: 13.5, weight: .bold)).foregroundStyle(skin.ink2)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(skin.card)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(skin.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else {
                Button { engine.start() } label: {
                    Text("시작").font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(skin.paper).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(engine.started ? skin.ink.opacity(0.3) : skin.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain).disabled(engine.started)

                Button { showEnd = true } label: {
                    Text("종료").font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(engine.started ? skin.danger : skin.ink3)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(skin.card)
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(engine.started ? skin.danger.opacity(0.4) : skin.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain).disabled(!engine.started)
            }

            Button { engine.toggleMute() } label: {
                Image(systemName: engine.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(engine.muted ? skin.danger : skin.ink2)
                    .frame(width: 46, height: 46)
                    .background(skin.card)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(skin.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var listeningButton: some View {
        Button { showListening = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "headphones").font(.system(size: 14, weight: .semibold))
                Text(engine.listeningName.map { "듣기평가 · \($0)" } ?? "영어 듣기평가 음원 선택")
                    .font(.system(size: 13.5, weight: .bold)).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(skin.ink3)
            }
            .foregroundStyle(engine.listeningName == nil ? skin.ink2 : skin.ink)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(skin.paper)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(skin.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 가로모드 우측 구간 목록
    private var segmentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(engine.schedule.indices, id: \.self) { i in
                        SegmentRow(engine: engine, index: i, jump: $jump).id(i)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: engine.activeIndex) { _, new in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    // MARK: 세로 히어로
    private var heroPortrait: some View {
        VStack(spacing: 14) {
            clockToggleBar
            statusChip
            clockView(size: 200)
            nameCountdown
            progressBar.padding(.top, 2)
            modeToggle
            controlsRow
            listeningButton
        }
        .padding(20)
        .background(skin.card)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(skin.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(dark ? 0.4 : 0.06), radius: 14, x: 0, y: 6)
    }

    // MARK: 가로 레이아웃 (좌: 시계 / 우: 컨트롤+구간)
    private func heroLandscape(geo: GeometryProxy) -> some View {
        let clockSize = min(geo.size.height * 0.6, geo.size.width * 0.36, 260)
        return HStack(spacing: 16) {
            VStack(spacing: 12) {
                statusChip
                clockView(size: clockSize)
                nameCountdown
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                clockToggleBar
                progressBar
                modeToggle
                controlsRow
                listeningButton
                segmentList
            }
            .frame(width: min(360, geo.size.width * 0.44))
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clockToggle(_ label: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(label)
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundStyle(on ? skin.paper : skin.ink3)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(on ? skin.ink : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

}

// MARK: - 하단 슬라이드 구간 패널 (독립 뷰: 드래그가 BellView 전체를 다시 그리지 않게 분리)
private struct SegmentPanel: View {
    @ObservedObject var engine: BellEngine
    @Binding var jump: JumpTarget?
    let geo: GeometryProxy
    @Environment(\.bellSkin) private var skin
    @State private var panelExpanded = false
    @State private var drag: CGFloat = 0

    var body: some View {
        let peek: CGFloat = 44
        let fullH = min(geo.size.height * 0.74, geo.size.height - 24)
        let collapsedOffset = max(0, fullH - peek)
        let raw = (panelExpanded ? 0 : collapsedOffset) + drag
        let off = max(0, min(collapsedOffset, raw))
        let spring = Animation.spring(response: 0.5, dampingFraction: 0.9)

        return VStack(spacing: 0) {
            // 손잡이 (그래버만) — 탭/드래그로 펼침·접힘
            VStack(spacing: 6) {
                Capsule().fill(skin.line).frame(width: 42, height: 5)
                if panelExpanded {
                    Text("구간 선택")
                        .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(skin.ink2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: panelExpanded ? 52 : peek)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(spring) { panelExpanded.toggle() }
            }
            .gesture(
                // .global = 화면 기준 고정 좌표계. 패널이 .offset으로 움직여도
                // translation이 흔들리지 않아 손가락을 1:1로 따라간다.
                DragGesture(coordinateSpace: .global)
                    .onChanged { v in drag = v.translation.height }
                    .onEnded { v in
                        let t = v.translation.height
                        withAnimation(spring) {
                            if panelExpanded { if t > 60 { panelExpanded = false } }
                            else { if t < -60 { panelExpanded = true } }
                            drag = 0
                        }
                    }
            )

            // 구간 목록
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(engine.schedule.indices, id: \.self) { i in
                            SegmentRow(engine: engine, index: i, jump: $jump).id(i)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 28)
                }
                .onChange(of: engine.activeIndex) { _, new in
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .frame(height: fullH)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(skin.card))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(skin.line, lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.08), radius: 13, y: -4)
        .offset(y: off)
    }
}

// MARK: - 구간 한 줄 (세로 패널·가로 목록 공용)
private struct SegmentRow: View {
    @ObservedObject var engine: BellEngine
    let index: Int
    @Binding var jump: JumpTarget?
    @Environment(\.bellSkin) private var skin

    var body: some View {
        let seg = engine.schedule[index]
        let active = index == engine.activeIndex
        let accent = BellPalette.subject(seg.subject)
        return Button { jump = JumpTarget(index: index) } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(seg.phase == .exam ? accent : (seg.phase == .prep ? skin.ink3 : skin.line))
                    .frame(width: 4, height: active ? 34 : 26)
                Text(engine.rangeText(index))
                    .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(active ? skin.ink2 : skin.ink3)
                    .frame(width: 96, alignment: .leading)
                Text(seg.name)
                    .font(.system(size: 14.5, weight: active ? .heavy : .semibold))
                    .foregroundStyle(active ? skin.ink : skin.ink2)
                Spacer(minLength: 0)
                if active {
                    Text("현재").font(.system(size: 10.5, weight: .heavy)).foregroundStyle(skin.paper)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(skin.ink).clipShape(Capsule())
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(active ? accent.opacity(seg.phase == .free ? 0.06 : 0.10) : skin.card)
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(active ? accent.opacity(0.5) : skin.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 듣기평가 음원 선택 시트
struct ListeningSheet: View {
    @Environment(\.bellSkin) private var skin
    @ObservedObject var engine: BellEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showImporter = false
    @State private var external: ListeningExternal?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("오후 1시 7분에 자동으로 재생돼요.")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(skin.ink2)
                        .padding(.bottom, 2)

                    // 내 파일에서 MP3 선택
                    Button { showImporter = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(skin.ink2)
                            Text("내 파일에서 MP3 선택").font(.system(size: 14.5, weight: .heavy)).foregroundStyle(skin.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(skin.ink3)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .background(skin.paper)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(skin.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // 현재 선택
                    if let n = engine.listeningName {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(skin.good)
                            Text("선택됨 · \(n)").font(.system(size: 12.5, weight: .bold)).foregroundStyle(skin.ink).lineLimit(1)
                            Spacer()
                            Button { engine.clearListening() } label: {
                                Text("해제").font(.system(size: 12, weight: .bold)).foregroundStyle(skin.danger)
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(skin.good.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    sectionHeader("평가원 · 교육청")
                    ForEach(engine.listeningPresets) { p in
                        Button { engine.setListening(p); dismiss() } label: {
                            HStack {
                                Text(p.name).font(.system(size: 14.5, weight: .bold)).foregroundStyle(skin.ink)
                                Spacer()
                                if engine.listeningName == p.name {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(skin.good)
                                } else {
                                    Text("선택").font(.system(size: 12, weight: .bold)).foregroundStyle(skin.ink3)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 13)
                            .background(skin.card)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(engine.listeningName == p.name ? skin.good : skin.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    sectionHeader("사설 모의고사 · 다운로드")
                    ForEach(engine.listeningExternals) { e in
                        Button { external = e } label: {
                            HStack {
                                Text(e.name).font(.system(size: 14, weight: .bold)).foregroundStyle(skin.ink)
                                Spacer()
                                Image(systemName: "safari").font(.system(size: 13, weight: .semibold)).foregroundStyle(skin.ink3)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(skin.card)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(skin.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(skin.paper.ignoresSafeArea())
            .navigationTitle("영어 듣기평가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let u = urls.first {
                engine.setCustomListening(u); dismiss()
            }
        }
        .confirmationDialog(external?.name ?? "", isPresented: Binding(get: { external != nil }, set: { if !$0 { external = nil } }), titleVisibility: .visible) {
            Button("Safari에서 열기") {
                if let e = external, let url = URL(string: e.url) { openURL(url) }
                external = nil
            }
            Button("취소", role: .cancel) { external = nil }
        } message: {
            Text("저작권상 직접 제공이 어려워요. 사이트에서 받은 뒤 '내 파일에서 MP3 선택'으로 불러오세요.")
        }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .heavy)).foregroundStyle(skin.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8).padding(.leading, 2)
    }
}

// MARK: - 구간 이동 하단 시트
struct JumpTarget: Identifiable { let id = UUID(); let index: Int }

struct JumpSheet: View {
    @Environment(\.bellSkin) private var skin
    let seg: BellSegment
    let range: String
    let started: Bool
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(BellPalette.subject(seg.subject)).frame(width: 9, height: 9)
                    Text(range).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(skin.ink3)
                }
                Text(seg.name).font(.system(size: 23, weight: .heavy)).foregroundStyle(skin.ink)
            }

            Text(started ? "이 구간으로 이동할까요?" : "이 구간에서 시작할까요?")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(skin.ink2)

            Spacer(minLength: 4)

            Button { onConfirm() } label: {
                Text(started ? "이 구간으로 이동" : "여기서 시작")
                    .font(.system(size: 17, weight: .heavy)).foregroundStyle(skin.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(skin.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                Text("취소").font(.system(size: 15, weight: .bold)).foregroundStyle(skin.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(skin.paper.ignoresSafeArea())
    }
}

// MARK: - 아날로그 시계 (종이·잉크 톤)
struct FullClockView: View {
    @Environment(\.bellSkin) private var skin
    @ObservedObject var engine: BellEngine
    let analog: Bool
    @Environment(\.dismiss) private var dismiss
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            skin.paper.ignoresSafeArea()
            GeometryReader { g in
                let clockSize = min(g.size.height * 0.52, g.size.width * 0.5, 320)
                VStack(spacing: g.size.height > g.size.width ? 24 : 14) {
                    HStack(spacing: 7) {
                        Circle().fill(BellPalette.subject(engine.current.subject)).frame(width: 9, height: 9)
                        if let subj = engine.current.subject {
                            Text(subj).font(.system(size: 15, weight: .heavy)).foregroundStyle(BellPalette.subject(subj))
                            Text("·").foregroundStyle(skin.ink3)
                        }
                        Text(engine.statusText).font(.system(size: 15, weight: .bold)).foregroundStyle(skin.ink2)
                    }
                    .padding(.horizontal, 15).padding(.vertical, 9)
                    .background(skin.paper).overlay(Capsule().stroke(skin.line, lineWidth: 1)).clipShape(Capsule())

                    if analog {
                        AnalogClock(time: engine.simTime).frame(width: clockSize, height: clockSize)
                    } else {
                        Text(engine.timeText)
                            .font(.system(size: clockSize * 0.34, weight: .light, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                            .foregroundStyle(skin.ink).padding(.horizontal, 12)
                    }

                    Text(engine.displayName).font(.system(size: 24, weight: .heavy)).foregroundStyle(skin.ink)
                    Text(engine.nextCountdown ?? " ").font(.system(size: 14, weight: .bold)).foregroundStyle(skin.ink3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(skin.ink2)
                            .frame(width: 40, height: 40)
                            .background(skin.card)
                            .overlay(Circle().stroke(skin.line, lineWidth: 1)).clipShape(Circle())
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(20)
        }
        .onReceive(ticker) { _ in engine.tick() }
    }
}

struct AnalogClock: View {
    @Environment(\.bellSkin) private var skin
    let time: Date

    var body: some View {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: time)
        let h = Double(comps.hour ?? 0)
        let m = Double(comps.minute ?? 0)
        let s = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1_000_000_000
        let hourAngle = (h.truncatingRemainder(dividingBy: 12) + m / 60) * 30
        let minAngle  = (m + s / 60) * 6
        let secAngle  = s * 6

        GeometryReader { g in
            let w = g.size.width, ht = g.size.height
            let c = CGPoint(x: w / 2, y: ht / 2)
            let r = min(w, ht) / 2

            ZStack {
                Circle().fill(skin.card)
                Circle().strokeBorder(skin.ink, lineWidth: 6)

                // 분 눈금
                Path { p in
                    for i in 0..<60 {
                        let a = Double(i) * 6 * .pi / 180
                        let outer = r - 9
                        let inner = r - (i % 5 == 0 ? 19 : 14)
                        p.move(to: CGPoint(x: c.x + sin(a) * inner, y: c.y - cos(a) * inner))
                        p.addLine(to: CGPoint(x: c.x + sin(a) * outer, y: c.y - cos(a) * outer))
                    }
                }
                .stroke(skin.ink3, lineWidth: 1)

                // 1 ~ 12
                ForEach(1...12, id: \.self) { n in
                    let a = Double(n) * 30 * .pi / 180
                    Text("\(n)")
                        .font(.system(size: r * 0.15, weight: .bold, design: .rounded))
                        .foregroundStyle(skin.ink)
                        .position(x: c.x + sin(a) * (r - r * 0.30),
                                  y: c.y - cos(a) * (r - r * 0.30))
                }

                // 시침
                handPath(c: c, len: r * 0.5, angle: hourAngle)
                    .stroke(skin.ink, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                // 분침
                handPath(c: c, len: r * 0.72, angle: minAngle)
                    .stroke(skin.ink2, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                // 초침
                handPath(c: c, len: r * 0.80, angle: secAngle)
                    .stroke(skin.danger, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                Circle().fill(skin.ink).frame(width: 9, height: 9).position(c)
            }
        }
    }

    private func handPath(c: CGPoint, len: CGFloat, angle: Double) -> Path {
        let a = angle * .pi / 180
        var p = Path()
        // 중심에서 살짝 뒤로 빠진 꼬리까지
        let tail: CGFloat = len * 0.12
        p.move(to: CGPoint(x: c.x - sin(a) * tail, y: c.y + cos(a) * tail))
        p.addLine(to: CGPoint(x: c.x + sin(a) * len, y: c.y - cos(a) * len))
        return p
    }
}

// MARK: 타종 화면 전용 색 (전역 Theme과 분리 — 다른 탭에 영향 없음)
struct BellSkin {
    let paper: Color, card: Color, ink: Color, ink2: Color, ink3: Color, line: Color, danger: Color, good: Color
    static let light = BellSkin(
        paper: Theme.paper, card: Theme.card, ink: Theme.ink, ink2: Theme.ink2,
        ink3: Theme.ink3, line: Theme.line, danger: Theme.danger, good: Theme.good)
    static let dark = BellSkin(
        paper: Color(hex: 0x141310), card: Color(hex: 0x201E18), ink: Color(hex: 0xF3EFE6),
        ink2: Color(hex: 0xB8B2A4), ink3: Color(hex: 0x827C6E), line: Color(hex: 0x36322A),
        danger: Color(hex: 0xFF6B6B), good: Color(hex: 0x8FD66B))
}

private struct BellSkinKey: EnvironmentKey { static let defaultValue = BellSkin.light }
extension EnvironmentValues {
    var bellSkin: BellSkin {
        get { self[BellSkinKey.self] }
        set { self[BellSkinKey.self] = newValue }
    }
}
