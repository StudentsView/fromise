// ─────────────────────────────────────────────────────────────
//  ⚠️ 임시 worker — stop2g@fromise.com 으로 오는 "인증코드" 한 번 받기용
//  · 들어온 메일의 발신자·제목·인증코드·본문을 Worker 로그에 출력합니다.
//  · 인증코드를 확인했으면 반드시 원래 email-worker.js 내용으로 되돌려 배포하세요.
//    (그래야 2G폰 모드 해제 메일이 다시 정상 동작합니다)
//
//  로그 보는 법:
//   - 대시보드: Workers & Pages → 해당 worker → Logs → "Begin log stream"
//   - 또는 터미널: npx wrangler tail <worker-name>
//   그 상태에서 구글 가입 화면의 "코드 보내기"를 누르면 로그에 ✅ CODE 가 뜹니다.
// ─────────────────────────────────────────────────────────────
export default {
  async email(message) {
    const subject = message.headers.get("subject") || "";
    const raw = await new Response(message.raw).text();

    // 구글 인증코드(G-123456) 우선, 없으면 제목/본문의 4~8자리 숫자
    const code =
      (raw.match(/G-\d{4,8}/) ||
        subject.match(/\b\d{4,8}\b/) ||
        raw.match(/\b\d{6}\b/) ||
        [])[0];

    console.log("📩 from:", message.from);
    console.log("📨 subject:", subject);
    if (code) console.log("✅ CODE:", code);
    else console.log("⚠️ 코드 패턴을 못 찾음 — 아래 raw에서 직접 확인하세요.");
    console.log("----- raw (앞 4000자) -----");
    console.log(raw.slice(0, 4000));
  },
};
