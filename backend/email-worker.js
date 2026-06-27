// ─────────────────────────────────────────────────────────────
//  Cloudflare Email Worker — stop2g@fromise.com 수신 → 해제코드 회신
//
//  흐름: 가입 이메일에서 stop2g@fromise.com 으로 메일 도착
//        → 발신자 주소로 활성 2G 잠금의 코드를 Supabase에서 조회(service_role)
//        → Resend(fromise.com 전용 계정)로 그 발신자에게 8자리 코드 회신
//  · 코드 삭제는 앱에서 "코드 입력 → 해제 성공" 시 수행하므로 여기선 발송만.
//  · 위조 방지: 코드는 항상 "등록된 가입 이메일"로만 발송됨(아무 from을 위조해도
//    코드는 진짜 소유자에게 감). 별도 발신자 검증 불필요.
//
//  수신(MX)은 Cloudflare Email Routing, 발송은 Resend → 충돌 없음.
//  의존성 없음(fetch만) → 대시보드 인라인 에디터로 붙여넣어도 동작.
//
//  Worker secret (암호화 변수):
//    SUPABASE_URL            예: https://qrzzhabqwqyluzisrewl.supabase.co
//    SUPABASE_SERVICE_KEY    Supabase service_role 키 (서버 전용)
//    RESEND_API_KEY_FROMISE  fromise.com 전용 Resend 계정 API 키
// ─────────────────────────────────────────────────────────────

const TABLE = "/rest/v1/two_g_locks";

export default {
  async email(message, env) {
    // 1. 봉투 주소 대신, 실제 메일 헤더의 "From"을 가져옵니다.
    const rawFrom = message.headers.get("From") || "";
    console.log("[2g] raw From header:", rawFrom);

    if (!rawFrom) return;

    // 2. "이름 <email@domain.com>" 형태에서 꺾쇠 안의 순수 이메일만 추출합니다.
    const emailMatch = rawFrom.match(/(?:<)(.+?)(?:>)/);
    const from = (emailMatch ? emailMatch[1] : rawFrom).trim().toLowerCase();
    
    console.log("[2g] parsed inbound from:", from);

    // 3) 가입 이메일로 활성 잠금 조회 (service_role → RLS 우회)
    const lock = await lookupLock(from, env);
    console.log("[2g] lock:", lock ? `FOUND (unlock_count=${lock.unlock_count})` : "NONE");
    if (!lock?.code) return; // 활성 잠금 없음 → 무시

    // 4) 누적 해제 횟수만큼 지연 후 발송 (n회 해제 → n시간 뒤)
    const delayHours = Math.max(0, lock.unlock_count || 0);
    await sendCode(from, lock.code, delayHours, env);
  },
};

async function lookupLock(email, env) {
  try {
    // 대소문자 무시 매칭(ilike) + 아직 기간이 끝나지 않은 활성 잠금만 발송
    const now = new Date().toISOString();
    const url = `${env.SUPABASE_URL}${TABLE}?email=ilike.${encodeURIComponent(email)}&ends_at=gt.${encodeURIComponent(now)}&select=code,unlock_count&limit=1`;
    const res = await fetch(url, {
      headers: {
        apikey: env.SUPABASE_SERVICE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      },
    });
    if (!res.ok) {
      console.error("[2g] supabase query failed:", res.status, await res.text());
      return null;
    }
    const rows = await res.json();
    return rows?.[0] ?? null;
  } catch (e) {
    console.error("[2g] supabase error:", e);
    return null;
  }
}

async function sendCode(to, code, delayHours, env) {
  const payload = {
    from: "Fromise <stop2g@fromise.com>",
    to: [to],
    subject: "Fromise 2G폰 모드 해제코드",
    text:
      `요청하신 8자리 해제코드입니다.\n\n` +
      `    ${code}\n\n` +
      (delayHours > 0
        ? `이전에 ${delayHours}회 메일로 해제하셨기 때문에, 이 코드는 요청 후 ${delayHours}시간 뒤에 발송되도록 예약되었습니다.\n\n`
        : ``) +
      `Fromise 앱 > 설정 > 2G폰 모드 화면에 입력하면 잠금이 해제됩니다.\n` +
      `본인이 요청하지 않았다면 이 메일을 무시하세요.`,
  };
  // Resend 예약 발송: 지연이 있으면 scheduled_at(ISO8601)로 미래 발송
  if (delayHours > 0) {
    payload.scheduled_at = new Date(Date.now() + delayHours * 3600 * 1000).toISOString();
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY_FROMISE}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const body = await res.text();
  if (!res.ok) console.error("[2g] resend send failed:", res.status, body);
  else console.log("[2g] resend sent (delayH=" + delayHours + "):", body);
}
