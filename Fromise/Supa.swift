import Foundation
import Supabase

// ─────────────────────────────────────────────────────────────
//  Supa.swift — Supabase 클라이언트 (앱 전역 1개)
//  ※ File ▸ Add Package Dependencies 로 supabase-swift 설치 후 컴파일됨.
//  URL·anon key는 기존 대수능닷컴 프로젝트 것 그대로 (anon key는 공개용이라 안전).
// ─────────────────────────────────────────────────────────────

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://qrzzhabqwqyluzisrewl.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFyenpoYWJxd3F5bHV6aXNyZXdsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDYyNjksImV4cCI6MjA5NjE4MjI2OX0.maOa6mMBxrRzvhX1475OwmLwwxyi4uiaCPx-_-c9d1Y"
)
