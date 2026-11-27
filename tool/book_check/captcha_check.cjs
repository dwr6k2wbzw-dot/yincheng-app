// 訂位頁機器人驗證（ops 0146）的檢查：攔下資料庫、驗證函式、Cloudflare 的請求，全部用假的。
// 用法（要有 playwright）：先在 tool/book 開 `python3 -m http.server 8766`，再 `node tool/book_check/captcha_check.cjs`。
const { chromium } = require('playwright');
const fs = require('fs');
const base = JSON.parse(fs.readFileSync(__dirname + '/avail.json', 'utf8'));
const ok = JSON.stringify({ token: 'tok123', display_name: '測試店', date: '2026-11-18', time: '20:00', party: 2, name: '王 先生' });
let pass = 0, fail = 0;
const check = (name, got, want) => { const y = JSON.stringify(got) === JSON.stringify(want); y ? pass++ : fail++; console.log((y ? 'PASS ' : 'FAIL ') + name + (y ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want))); };

// 假的 Turnstile：render 之後馬上給一個 token，每次 reset 給新的
const FAKE_CF = `(() => { let n = 0, cb = null, el = null;
  window.turnstile = {
    render(sel, o) { el = document.querySelector(sel); el.innerHTML = '<div class="fake-cf">我不是機器人 ✓</div>'; cb = o.callback; window.cfOpts = o; setTimeout(() => cb('cf-token-' + (++n)), 10); return 'w1'; },
    reset() { setTimeout(() => cb && cb('cf-token-' + (++n)), 10); },
  };
  const u = new URL(document.currentScript.src); const f = u.searchParams.get('onload'); if (f && window[f]) window[f]();
})();`;

async function run(name, opts, steps) {
  const b = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME, args: ['--no-sandbox'] } : {});
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, locale: opts.locale || 'zh-TW', timezoneId: 'Asia/Taipei' });
  const books = [], verifies = [], cfLoads = [];
  const avail = { ...base, ...(opts.captcha === undefined ? {} : { captcha: opts.captcha }) };
  await p.route('**/rest/v1/rpc/reservation_availability', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(avail) }));
  await p.route('https://challenges.cloudflare.com/**', (r) => { cfLoads.push(r.request().url()); r.fulfill({ status: 200, contentType: 'application/javascript', body: FAKE_CF }); });
  await p.route('**/functions/v1/booking-captcha', (r) => {
    const body = JSON.parse(r.request().postData()); verifies.push(body);
    const act = (opts.verify || [])[verifies.length - 1] || 'ok';
    if (act === 'fail') return r.fulfill({ status: 403, contentType: 'application/json', body: '{"error":"failed"}' });
    return r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ pass: '00000000-0000-4000-8000-0000000000p' + verifies.length }) });
  });
  await p.route('**/functions/v1/reservation-email', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: '{"sent":true}' }));
  await p.route('**/rest/v1/rpc/book_reservation', (r) => {
    const body = JSON.parse(r.request().postData()); books.push(body);
    const act = (opts.plan || [])[books.length - 1] || 'ok';
    if (act === 'full') return r.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'P0001', message: '這天的訂位已滿，請選別天或直接來電' }) });
    if (act === 'captcha') return r.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'P0001', message: 'CAPTCHA_REQUIRED：請先完成「我不是機器人」的驗證再送出' }) });
    return r.fulfill({ status: 200, contentType: 'application/json', body: ok });
  });
  await p.goto('http://localhost:8766/index.html?s=yincheng&intro=0' + (opts.lang ? '&lang=' + opts.lang : ''), { waitUntil: 'networkidle' });
  await p.waitForTimeout(800);
  await p.click('#cal button[data-d="2026-11-18"]');
  await p.click('#slots button[data-t="20:00"]');
  await p.fill('#name', '王'); await p.click('#titles .chip[data-t="先生"]');
  await p.fill('#phone', '0912345678'); await p.fill('#email', 'a@test.tw');
  const st = async () => ({ err: await p.$eval('#err', (e) => (e.hidden ? '' : e.textContent)), done: await p.$eval('#done', (e) => !e.hidden) });
  await steps(p, { books, verifies, cfLoads }, st);
  await b.close();
}

const CAP = { provider: 'turnstile', site_key: '0x4AAAAAAAtestsitekey' };
(async () => {
  await run('沒打開驗證的店（隱城、小城外）', {}, async (p, c, st) => {
    check('沒打開：不載入 Cloudflare', c.cfLoads.length, 0);
    check('沒打開：驗證區塊藏起來', await p.$eval('#cf', (e) => e.hidden), true);
    await p.click('#submit'); await p.waitForTimeout(700);
    check('沒打開：照原本的方式訂成功', (await st()).done, true);
    check('沒打開：沒有呼叫驗證、沒有帶通行證', c.verifies.length === 0 && !('p_captcha' in c.books[0]), true);
  });
  await run('打開驗證的店', { captcha: CAP }, async (p, c, st) => {
    check('打開：載入一次 Cloudflare（explicit）', c.cfLoads.length === 1 && c.cfLoads[0].includes('render=explicit'), true);
    check('打開：用店家的 site key、action=booking、中文', await p.evaluate(() => [cfOpts.sitekey, cfOpts.action, cfOpts.language]), ['0x4AAAAAAAtestsitekey', 'booking', 'zh-tw']);
    await p.click('#submit'); await p.waitForTimeout(900);
    check('打開：訂成功', (await st()).done, true);
    check('打開：先換通行證（帶店代號和 token）', c.verifies[0], { slug: 'yincheng', token: 'cf-token-1' });
    check('打開：訂位帶通行證', c.books[0].p_captcha, '00000000-0000-4000-8000-0000000000p1');
  });
  await run('訂位被名額擋下再送', { captcha: CAP, plan: ['full', 'ok'] }, async (p, c, st) => {
    await p.click('#submit'); await p.waitForTimeout(900);
    check('名額已滿：顯示原本的訊息', (await st()).err, '這天的訂位已滿，請選別天或直接來電');
    await p.click('#submit'); await p.waitForTimeout(900);
    check('再送：沿用同一張通行證（不用重新驗證）', c.verifies.length === 1 && c.books[1].p_captcha === c.books[0].p_captcha, true);
    check('再送：成功', (await st()).done, true);
  });
  await run('通行證失效（伺服器說要驗證）', { captcha: CAP, plan: ['captcha', 'ok'] }, async (p, c, st) => {
    await p.click('#submit'); await p.waitForTimeout(900);
    check('失效：提示重新驗證（不顯示代碼）', (await st()).err, '請先完成上方「我不是機器人」的驗證，再按確認訂位。');
    await p.click('#submit'); await p.waitForTimeout(900);
    check('再按：換一張新的通行證', c.verifies.length === 2 && c.books[1].p_captcha !== c.books[0].p_captcha, true);
    check('再按：成功', (await st()).done, true);
  });
  await run('Cloudflare 沒通過', { captcha: CAP, verify: ['fail', 'ok'] }, async (p, c, st) => {
    await p.click('#submit'); await p.waitForTimeout(900);
    check('沒通過：不送訂位、提示重新驗證', [(await st()).err, c.books.length], ['請先完成上方「我不是機器人」的驗證，再按確認訂位。', 0]);
    await p.click('#submit'); await p.waitForTimeout(900);
    check('再按：成功', (await st()).done, true);
  });
  await run('英文', { captcha: CAP, lang: 'en', locale: 'en-US', plan: ['captcha', 'ok'] }, async (p, c, st) => {
    check('英文：驗證也是英文', await p.evaluate(() => cfOpts.language), 'en');
    await p.click('#submit'); await p.waitForTimeout(900);
    check('英文：提示是英文、沒有 Error: 前綴', (await st()).err, 'Please complete the "I am human" check above, then confirm.');
  });
  await run('還沒設定 site key', { captcha: { provider: 'turnstile', site_key: null } }, async (p, c, st) => {
    check('沒有 site key：不載入 Cloudflare', c.cfLoads.length, 0);
    check('沒有 site key：說明還沒設定好、不能送出', [await p.$eval('#cf', (e) => e.textContent), await p.$eval('#submit', (e) => e.disabled)],
      ['這家店的線上訂位還沒設定完成，請直接聯絡店家。', true]);
  });
  console.log(`\n${pass} pass / ${fail} fail`);
  process.exit(fail ? 1 : 0);
})();
