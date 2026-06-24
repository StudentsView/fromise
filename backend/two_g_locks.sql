-- ─────────────────────────────────────────────────────────────
-- 2G폰 모드 잠금 테이블 (Supabase)
-- 유저당 1개(활성 잠금). 활성화마다 code가 새로 덮어써짐(upsert).
-- 해제(코드 입력 성공) 또는 기간 종료 시 앱이 행을 삭제.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.two_g_locks (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  code         text not null,                 -- 8자리 숫자 해제코드
  email        text,                          -- 가입 이메일(인바운드 매칭용)
  unlock_count int  not null default 0,       -- 활성화 시점의 누적 해제 횟수(= 코드 발송 지연 h)
  started_at   timestamptz not null default now(),
  ends_at      timestamptz not null,
  created_at   timestamptz not null default now()
);
-- 기존 테이블이 있으면 컬럼 보강
alter table public.two_g_locks add column if not exists unlock_count int not null default 0;

create index if not exists two_g_locks_email_idx on public.two_g_locks (lower(email));

alter table public.two_g_locks enable row level security;

-- 본인 행만 접근 (앱은 anon+로그인 세션으로 접근)
drop policy if exists "own_select" on public.two_g_locks;
drop policy if exists "own_insert" on public.two_g_locks;
drop policy if exists "own_update" on public.two_g_locks;
drop policy if exists "own_delete" on public.two_g_locks;
create policy "own_select" on public.two_g_locks for select using (auth.uid() = user_id);
create policy "own_insert" on public.two_g_locks for insert with check (auth.uid() = user_id);
create policy "own_update" on public.two_g_locks for update using (auth.uid() = user_id);
create policy "own_delete" on public.two_g_locks for delete using (auth.uid() = user_id);

-- 인바운드 메일 처리(Cloudflare Worker)는 service_role 키로 접근하므로 RLS를 우회합니다.


-- ─────────────────────────────────────────────────────────────
-- 누적 해제 횟수 통계 (잠금이 삭제돼도 영속)
-- 메일로 해제할 때마다 +1. n회 해제한 사람은 다음 코드가 n시간 뒤 발송됨.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.two_g_stats (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  unlock_count int not null default 0,
  updated_at   timestamptz not null default now()
);

alter table public.two_g_stats enable row level security;

drop policy if exists "stats_select" on public.two_g_stats;
drop policy if exists "stats_insert" on public.two_g_stats;
drop policy if exists "stats_update" on public.two_g_stats;
create policy "stats_select" on public.two_g_stats for select using (auth.uid() = user_id);
create policy "stats_insert" on public.two_g_stats for insert with check (auth.uid() = user_id);
create policy "stats_update" on public.two_g_stats for update using (auth.uid() = user_id);
