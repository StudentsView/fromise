import SwiftUI
import AdFitSDK

// ─────────────────────────────────────────────────────────────
//  AdFitBanner.swift — 카카오 애드핏 배너 광고 SwiftUI 래퍼
//  사용:  AdFitBanner()              // 기본 320x50
//        AdFitBanner(adUnitSize: "320x100")
//  광고가 로드되기 전에는 "AD" 플레이스홀더(흰 사각형)를 표시하고,
//  광고가 수신되면(대체광고 포함) 자동으로 사라진다.
// ─────────────────────────────────────────────────────────────

enum AdFitConfig {
    /// 애드핏에 등록한 배너 광고단위 ID.
    static let clientId = "DAN-GisvkFbFf5oVLZLn"
}

struct AdFitBanner: View {
    var clientId: String = AdFitConfig.clientId
    var adUnitSize: String = "320x50"        // 320x50 / 320x100 / 250x250 / 300x250 등
    @State private var loaded = false

    var body: some View {
        ZStack {
            AdFitBannerRepresentable(clientId: clientId, adUnitSize: adUnitSize) {
                loaded = true                 // 광고 수신 → 플레이스홀더 제거
            }
            if !loaded {
                AdPlaceholder()               // 로드 전: 광고 자리 표시
            }
        }
    }
}

/// 광고가 아직 안 뜬 동안 자리를 표시하는 흰 사각형 + 가운데 작은 "AD".
private struct AdPlaceholder: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.white)
            Text("AD")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.28))
        }
        .overlay(Rectangle().stroke(Color.black.opacity(0.07), lineWidth: 1))
        .allowsHitTesting(false)
    }
}

/// 애드핏 배너 UIView 래퍼. 광고 수신 시 onLoad 콜백.
private struct AdFitBannerRepresentable: UIViewRepresentable {
    let clientId: String
    let adUnitSize: String
    let onLoad: () -> Void

    func makeUIView(context: Context) -> AdFitBannerAdView {
        let banner = AdFitBannerAdView(clientId: clientId, adUnitSize: adUnitSize)
        banner.delegate = context.coordinator
        banner.loadAd()                       // 광고 요청
        return banner
    }

    func updateUIView(_ uiView: AdFitBannerAdView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onLoad: onLoad) }

    final class Coordinator: NSObject, AdFitBannerAdViewDelegate {
        let onLoad: () -> Void
        init(onLoad: @escaping () -> Void) { self.onLoad = onLoad }

        func adViewDidReceiveAd(_ bannerAdView: AdFitBannerAdView) {
            print("[AdFit] 광고 수신 성공")
            onLoad()
        }
        func adViewDidFailToReceiveAd(_ bannerAdView: AdFitBannerAdView, error: Error) {
            print("[AdFit] 광고 수신 실패: \(error.localizedDescription)")
            // 실패 시 플레이스홀더 유지
        }
        func adViewDidClickAd(_ bannerAdView: AdFitBannerAdView) {
            print("[AdFit] 광고 클릭")
        }
    }
}
