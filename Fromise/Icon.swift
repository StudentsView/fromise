import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────
//  Icon.swift — 이모지 제거용 아이콘 시스템
//
//  기본은 SF Symbols(벡터, 다크모드 자동). 나중에 자체 PNG를 쓰고 싶으면
//  Assets.xcassets 에 이미지를 넣고 아래 `asset` 값만 채우면 자동으로 그 PNG가 쓰임.
//  (코드 다른 곳은 손댈 필요 없음)
// ─────────────────────────────────────────────────────────────

enum AppIcon {
    // 탭/기능
    case home, planner, bell, clock, log, settings
    // 보조
    case check, plus, chevronRight, back, more
    case pen, highlighter, eraser, listening, mute, lock, dark, wake

    /// SF Symbol 이름 (PNG가 없을 때 기본으로 사용)
    var symbol: String {
        switch self {
        case .home:         return "house.fill"
        case .planner:      return "calendar"
        case .bell:         return "bell.fill"
        case .clock:        return "clock.fill"
        case .log:          return "chart.line.uptrend.xyaxis"
        case .settings:     return "gearshape.fill"
        case .check:        return "checkmark"
        case .plus:         return "plus"
        case .chevronRight: return "chevron.right"
        case .back:         return "chevron.left"
        case .more:         return "ellipsis"
        case .pen:          return "pencil.tip"
        case .highlighter:  return "highlighter"
        case .eraser:       return "eraser"
        case .listening:    return "headphones"
        case .mute:         return "speaker.slash.fill"
        case .lock:         return "lock.fill"
        case .dark:         return "moon.fill"
        case .wake:         return "sun.max.fill"
        }
    }

    /// 자체 PNG를 쓰려면 여기에 에셋 이름을 반환 (없으면 nil → SF Symbol 사용)
    /// 예: case .bell: return "ic_bell"
    var asset: String? {
        switch self {
        default: return nil
        }
    }
}

/// 어디서든 `Icon(.bell)` 으로 호출. PNG가 있으면 PNG, 없으면 SF Symbol.
struct Icon: View {
    let icon: AppIcon
    var size: CGFloat = 20
    var weight: Font.Weight = .semibold

    init(_ icon: AppIcon, size: CGFloat = 20, weight: Font.Weight = .semibold) {
        self.icon = icon; self.size = size; self.weight = weight
    }

    var body: some View {
        if let name = icon.asset, UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .renderingMode(.template)      // tint(...) 로 색 입힘
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: icon.symbol)
                .font(.system(size: size, weight: weight))
        }
    }
}
