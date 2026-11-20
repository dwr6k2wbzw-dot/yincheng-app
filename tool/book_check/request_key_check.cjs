// 訂位頁防重複送出（ops 0121）的檢查：攔下對資料庫的請求，模擬斷線、改內容、名額已滿、舊資料庫。
// 用法（要有 playwright）：先在 tool/book 開 `python3 -m http.server 8766`，再 `node tool/book_check/request_key_check.cjs`。資料都是假的。
const { chromium } = require('playwright');
const fs = require('fs');
const avail = fs.readFileSync(__dirname + '/avail.json', 'utf8');
const ok = JSON.stringify({ token: 'tok123', display_name: '測試店', date: '2026-11-18', time: '20:00', party: 2, name: '王 先生', repeat: true });
let pass = 0, fail = 0;
const check = (name, got, want) => { const y = JSON.stringify(got) === JSON.stringify(want); y ? pass++ : fail++; console.log((y ? 'PASS ' : 'FAIL ') + name + (y ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want))); };

async function run(name, plan, steps) {
  const b = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME, args: ['--no-sandbox'] } : {});
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, locale: 'zh-TW', timezoneId: 'Asia/Taipei' });
  const calls = [];
  await p.route('**/rest/v1/rpc/reservation_availability', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: avail }));
  await p.route('**/functions/v1/**', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: '{"sent":true}' }));
  await p.route('**/rest/v1/rpc/book_reservation', (r) => {
    const body = JSON.parse(r.request().postData());
    calls.push(body);
    const act = plan[Math.min(calls.length - 1, plan.length - 1)];
    if (act === 'drop') return r.abort('connectionfailed');
    if (act === 'old') return r.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify({ code: 'PGRST202', message: 'Could not find the function public.book_reservation(p_request...) in the schema cache' }) });
    if (act === 'full') return r.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'P0001', message: '這天的訂位已滿，請選別天或直接來電' }) });
    return r.fulfill({ status: 200, contentType: 'application/json', body: ok });
  });
  await p.goto('http://localhost:8766/index.html?s=yincheng&intro=0', { waitUntil: 'networkidle' });
  await p.waitForTimeout(800);
  await p.click('#cal button[data-d="2026-11-18"]');
  await p.click('#slots button[data-t="20:00"]');
  await p.fill('#name', '王'); await p.click('#titles .chip[data-t="先生"]');
  await p.fill('#phone', '0912345678'); await p.fill('#email', 'a@test.tw');
  const st = async () => ({ err: await p.$eval('#err', (e) => (e.hidden ? '' : e.textContent)), done: await p.$eval('#done', (e) => !e.hidden) });
  await steps(p, calls, st);
  await b.close();
}

(async () => {
  await run('斷線後再按一次', ['drop', 'ok'], async (p, calls, st) => {
    await p.click('#submit'); await p.waitForTimeout(700);
    check('斷線：顯示看得懂的中文、沒有顯示成功', await st(), { err: '連線失敗，請稍後再試', done: false });
    check('斷線：按鈕可以再按', await p.$eval('#submit', (e) => e.disabled), false);
    await p.click('#submit'); await p.waitForTimeout(700);
    check('再按一次：成功', (await st()).done, true);
    check('兩次送的是同一個代號', calls.length === 2 && !!calls[0].p_request && calls[0].p_request === calls[1].p_request, true);
    check('代號是 uuid', /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(calls[0].p_request), true);
  });
  await run('斷線後改了內容再送', ['drop', 'ok'], async (p, calls, st) => {
    await p.click('#submit'); await p.waitForTimeout(700);
    await p.fill('#email', 'b@test.tw');
    await p.click('#submit'); await p.waitForTimeout(700);
    check('改了 Email：換一個新代號（是另一次訂位）', calls.length === 2 && calls[0].p_request !== calls[1].p_request, true);
  });
  await run('被名額擋下後原樣再送', ['full', 'full'], async (p, calls, st) => {
    await p.click('#submit'); await p.waitForTimeout(900);
    check('名額已滿：顯示原本的訊息', (await st()).err, '這天的訂位已滿，請選別天或直接來電');
  });
  await run('資料庫還沒更新', ['old', 'ok'], async (p, calls, st) => {
    await p.click('#submit'); await p.waitForTimeout(900);
    check('舊資料庫：自動改用原本的方式送，客人看到成功', (await st()), { err: '', done: true });
    check('第二次沒有帶代號', calls.length === 2 && !('p_request' in calls[1]) && 'p_request' in calls[0], true);
  });
  console.log(`\n${pass} pass / ${fail} fail`);
  process.exit(fail ? 1 : 0);
})();
