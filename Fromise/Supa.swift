import Foundation
import Supabase

// ─────────────────────────────────────────────────────────────
//  Supa.swift — Supabase 클라이언트 (앱 전역 1개)
//  ※ File ▸ Add Package Dependencies 로 supabase-swift 설치 후 컴파일됨.
//  URL·anon key는 기존 대수능닷컴 프로젝트 것 그대로 (anon key는 공개용이라 안전).
// ─────────────────────────────────────────────────────────────

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://qrzzhabqwqyluzisrewl.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFyenpoYWJxd3F5bHV6aXNyZXdsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDYyNjksImV4cCI6MjA5NjE4MjI2OX0.maOa6mMBxrRzvhX1475OwmLwwxyi4uiaCPx-_-c9d1Y",
    // 로컬 저장 세션을 (갱신 시도 없이) 곧바로 초기 세션으로 방출 — supabase-swift의 다음 메이저에서 기본이 될 동작에 미리 옵트인.
    // 이걸 켜면 런타임 경고가 사라지고, 앱 시작 시 세션 복원이 더 빨라진다. (만료 여부가 필요하면 session.isExpired로 별도 확인)
    options: SupabaseClientOptions(
        auth: .init(emitLocalSessionAsInitialSession: true)
    )
)
