import SwiftUI
import PencilKit

// ─────────────────────────────────────────────────────────────
//  PencilPlannerCanvas.swift — 펜슬 드로잉 캔버스 (재사용 코어)
//  핵심: PencilKit(.pencilOnly) → 손가락=스크롤, 펜슬=그리기 (끊김 제거)
//  스크롤 잠금/텍스트선택 차단은 이 캔버스를 쓰는 DaySheetView 쪽에서 처리.
// ─────────────────────────────────────────────────────────────

enum PlannerMode { case type, draw }
enum DrawTool   { case pen, highlighter, eraser }

/// DrawTool → PencilKit 도구 변환 (펜·형광펜·지우개 두께 지원)
func pkTool(for tool: DrawTool, color: Color,
            penWidth: CGFloat = 3, hlWidth: CGFloat = 18, eraserWidth: CGFloat = 30) -> PKTool {
    switch tool {
    case .pen:         return PKInkingTool(.pen,    color: UIColor(color), width: penWidth)
    case .highlighter: return PKInkingTool(.marker, color: UIColor(color), width: hlWidth)
    case .eraser:
        if #available(iOS 16.4, *) { return PKEraserTool(.bitmap, width: eraserWidth) }
        else { return PKEraserTool(.bitmap) }
    }
}

struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var isDrawing: Bool     // 긋는 중 → 부모가 스크롤 잠금
    var tool: PKTool
    var isActive: Bool               // 그리기 모드 on/off
    var penOnly: Bool = false        // true=Apple Pencil만, false=손가락도 그리기
    var clearToken: Int = 0          // 값이 바뀌면 캔버스를 drawing으로 강제 동기화(전체 지우기 등)

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = penOnly ? .pencilOnly : .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = drawing
        canvas.tool = tool
        canvas.delegate = context.coordinator
        context.coordinator.lastClearToken = clearToken
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.tool = tool
        canvas.drawingPolicy = penOnly ? .pencilOnly : .anyInput
        canvas.isUserInteractionEnabled = isActive
        // 평소엔 drawing을 매 프레임 덮어쓰지 않음(그리기 루프 방지).
        // clearToken이 바뀐 경우에만(=전체 지우기) 바인딩 값으로 캔버스를 강제 동기화.
        if context.coordinator.lastClearToken != clearToken {
            context.coordinator.lastClearToken = clearToken
            canvas.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: PencilCanvas
        var lastClearToken = 0
        init(_ parent: PencilCanvas) { self.parent = parent }
        func canvasViewDidBeginUsingTool(_ c: PKCanvasView) { parent.isDrawing = true }
        func canvasViewDidEndUsingTool(_ c: PKCanvasView)   { parent.isDrawing = false }
        func canvasViewDrawingDidChange(_ c: PKCanvasView)  { parent.drawing = c.drawing }
    }
}
