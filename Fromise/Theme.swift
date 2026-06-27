import SwiftUI

// ─────────────────────────────────────────────────────────────
//  Theme.swift — 디자인 토큰 (HTML 목업에서 확정한 색·스타일)
//  따뜻한 종이 + 잉크 네이비 + 형광펜 한 획(시그니처)
// ─────────────────────────────────────────────────────────────

extension Color {
    /// 0xRRGGBB 정수로 색 생성
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    // 텍스트
    static let ink   = Color(hex: 0x1B1A22)
    static let ink2  = Color(hex: 0x5B5867)
    static let ink3  = Color(hex: 0x9B97A6)
    // 표면
    static let paper = Color(hex: 0xF6F2E9)
    static let card  = Color(hex: 0xFFFDF8)
    static let line  = Color(hex: 0xE7E0D2)
    static let select = Color(hex: 0x14B8A6)   // 타임테이블 드래그 선택 표시(웹과 동일 teal)
    // 형광펜
    static let hlCheese = Color(hex: 0xFCE8A6)
    static let hlSky    = Color(hex: 0xA9D9F5)
    static let hlMint   = Color(hex: 0xCDEBA3)
    static let hlViolet = Color(hex: 0xCDB8EC)
    static let hlPink   = Color(hex: 0xF8B9D4)
    static let hlCoral  = Color(hex: 0xF9B79C)
    // 의미색
    static let good    = Color(hex: 0x10B981)
    static let danger  = Color(hex: 0xEF4444)

    static let highlighters: [Color] = [hlCheese, hlMint, hlCoral, hlViolet, hlPink, hlSky]
}

// MARK: - 형광펜 한 획 (시그니처)
/// 핵심 단어 뒤에 손으로 그은 듯한 형광펜 자국을 깔아줌
struct HighlightText: View {
    let text: String
    var color: Color = Theme.hlCheese
    var font: Font = .system(size: 18, weight: .heavy)

    var body: some View {
        Text(text)
            .font(font)
            .background(alignment: .bottom) {
                GeometryReader { geo in
                    color
                        .frame(height: geo.size.height * 0.42)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .rotationEffect(.degrees(-1.4))
                        .offset(y: geo.size.height * 0.30)
                }
            }
    }
}

// MARK: - 카드 스타일
struct CardStyle: ViewModifier {
    var padding: CGFloat = 20
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.06), radius: 14, x: 0, y: 6)
    }
}
extension View {
    func card(padding: CGFloat = 20, radius: CGFloat = 24) -> some View {
        modifier(CardStyle(padding: padding, radius: radius))
    }
}
