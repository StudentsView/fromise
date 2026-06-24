# 2G폰 모드 — 설정 가이드

코드는 모두 작성되어 있습니다. 아래는 **직접 해주셔야 하는 외부 설정**(Apple/Xcode/Supabase/Cloudflare/Resend)입니다. 도메인은 본인 소유(fromise.com)라는 전제입니다.

---

## 1. Apple Developer
- **Family Controls (Distribution)**: 이미 승인됨 ✅
- App ID(`com.flmang.Fromise`)에 Capability 확인: **Family Controls**, **App Groups**
- **App Group 생성**: `group.com.flmang.Fromise` (이미 entitlements에 기재됨)

## 2. Xcode
### (a) 메인 타깃 `Fromise`
- Signing & Capabilities에 다음이 잡혀 있는지 확인 (entitlements 파일은 이미 연결됨):
  - **Family Controls**
  - **App Groups** → `group.com.flmang.Fromise`

### (b) 확장 타깃 추가 (자동 만료 해제용)
1. `File ▸ New ▸ Target… ▸ Device Activity Monitor Extension`
2. Product Name: **FromiseMonitor**, Embed in: Fromise
3. 생성된 기본 `DeviceActivityMonitor` 서브클래스 파일을
   `FromiseMonitor/DeviceActivityMonitorExtension.swift` 내용으로 교체
   (principal class 이름 = `DeviceActivityMonitorExtension`, Info.plist도 동봉본과 일치)
4. 확장 타깃 Signing & Capabilities에 **Family Controls** + **App Groups(group.com.flmang.Fromise)** 추가
   (동봉한 `FromiseMonitor/FromiseMonitor.entitlements` 사용)

> 확장이 없어도 앱은 동작하지만, "앱을 안 켜도 기간 종료 시 자동 해제"는 이 확장이 처리합니다.
> 확장이 없으면 다음에 앱을 열 때 만료가 확인되어 해제됩니다.

## 3. Supabase
- SQL Editor에서 `backend/two_g_locks.sql` 실행 (테이블 2개 + RLS)
  - `two_g_locks`: 활성 잠금(코드·만료·`unlock_count` 스냅샷). 해제/만료 시 삭제
  - `two_g_stats`: 누적 메일 해제 횟수(영속). 해제할 때마다 +1
- 앱의 Supabase URL/anon 키는 기존 설정(`Supa.swift`) 그대로 사용

### 메일 해제 지연 규칙
- `n`회 해제한 사람은 다음 코드가 **`n`시간 뒤** 도착합니다(0회면 즉시).
- 구현: 활성화 시 `two_g_locks.unlock_count`에 현재 누적 횟수를 스냅샷 → Worker가 그만큼
  **Resend `scheduled_at`(예약 발송)** 으로 지연시킵니다. 앱은 시작 화면에서 이 지연을 공지합니다.
- Resend 예약 발송은 별도 설정 없이 `scheduled_at`(ISO8601) 파라미터로 동작합니다.

> **도메인 메모**: 메일(수신·발송)은 `fromise.com`, Supabase에 연결된 도메인은 `daesuneung.com`이지만 **서로 무관합니다.**
> 앱과 Worker는 Supabase를 프로젝트 URL(`*.supabase.co`)로 직접 호출하므로, Supabase가 어느 도메인에 연결돼 있든 영향이 없습니다.
> 인바운드 매칭은 발신자(가입 이메일) 주소로 하므로 가입 이메일의 도메인도 상관없습니다.

## 4. Resend (발송) — fromise.com 전용 계정
- Resend **fromise.com 계정**(daesuneung.com 계정과 별개)에 도메인 `fromise.com` 추가 후 **DNS 인증(SPF/DKIM)** 완료
- 발신 주소 `stop2g@fromise.com` 사용 허용
- API 키 발급 → Cloudflare Worker secret **`RESEND_API_KEY_FROMISE`** 로 사용
  (daesuneung.com 계정의 `RESEND_API_KEY`와 혼동 금지)

## 5. Cloudflare (수신 → 코드 발송)
- `fromise.com`을 Cloudflare로 관리(네임서버 이전 또는 DNS 위임)
- **Email Routing** 활성화 (수신용 **MX 레코드** 자동 추가)
- Routing 규칙: `stop2g@fromise.com` → **Send to a Worker**
- Worker 코드: `backend/email-worker.js`
- Worker Variables(암호화)에 secret 등록:
  - `SUPABASE_URL` = `https://qrzzhabqwqyluzisrewl.supabase.co`
  - `SUPABASE_SERVICE_KEY` = Supabase **service_role** 키 (⚠️ 서버 전용, 앱에 넣지 말 것)
  - `RESEND_API_KEY_FROMISE` = fromise.com 전용 Resend 계정의 API 키

### Secret 추가 방법 (둘 중 택1)
**A. 대시보드**
1. Cloudflare 대시보드 → **Workers & Pages** → 해당 Worker 선택
2. **Settings → Variables and Secrets** → **Add**
3. Type을 **Secret** 으로 선택 → 이름(`SUPABASE_SERVICE_KEY` 등)·값 입력 → **Save/Deploy**
4. 세 개(`SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `RESEND_API_KEY_FROMISE`) 반복
   - `SUPABASE_URL`은 비밀이 아니므로 Text 변수로 둬도 됩니다.

**B. Wrangler CLI**
```bash
npx wrangler secret put SUPABASE_URL            # 값 붙여넣기
npx wrangler secret put SUPABASE_SERVICE_KEY
npx wrangler secret put RESEND_API_KEY_FROMISE
```
> 이 Worker는 외부 의존성이 없어 대시보드 인라인 에디터에 그대로 붙여넣어도 동작합니다.

### DNS 주의 (수신 Cloudflare + 발송 Resend 공존)
충돌의 핵심은 **MX(수신)** 와 **SPF(한 줄 제한)** 입니다. 아래만 지키면 공존합니다.
- **MX는 Cloudflare Email Routing 것만** 둡니다. (Resend는 *발송*이라 MX 불필요 — Resend가 MX를 요구하면 그건 inbound 설정이니 추가하지 말 것)
- **SPF는 TXT 한 줄로 병합** (도메인당 1개):
  `v=spf1 include:_spf.mx.cloudflare.net include:amazonses.com ~all`
  (Resend가 안내하는 include 값을 함께 넣으세요. 별도 TXT 두 줄이면 무효)
- **DKIM**은 Resend가 준 CNAME/TXT를 그대로 추가 (SPF와 별개라 충돌 없음).

> 발송을 **서브도메인**(예: `send.fromise.com`)으로 분리하면 SPF가 루트와 분리돼 더 안전합니다.
> 단 이 경우 회신 발신 주소가 `stop2g@send.fromise.com` 형태가 됩니다(수신은 여전히 루트 `stop2g@fromise.com`).

---

## 동작 흐름 요약
1. 설정 ▸ 2G폰 모드 ▸ 허용 앱·사이트 지정 ▸ 기간(최소 1일) ▸ 시작
2. 활성화 시 8자리 코드 발급 → `two_g_locks`에 저장, 화이트리스트 잠금 적용
3. 기간 동안 Fromise + 허용 목록만 사용 가능 (앱 종료/재실행해도 유지)
4. 급할 때: 가입 이메일에서 `stop2g@fromise.com`으로 메일 → 코드 회신 → 앱에 입력 → 해제 + 코드 삭제
5. 기간이 끝나면 확장이 자동 해제, 앱이 다음 실행 때 코드 삭제

## 테스트 주의
- **실기기 필수** (스크린타임 API는 시뮬레이터 미지원)
- 화이트리스트는 개별 **앱/사이트**를 고르세요(카테고리 전체 선택은 허용 처리되지 않음)
- 웹 차단은 Safari 기준
