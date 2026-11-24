// 訂位頁 GA4（2026-11-24，tool/book/ga.py）的檢查：沒填評估 ID 不載入；有填時訂位成功只送 booking_complete＋人數，不送個人資料。
// 攔下 Google 的程式和對資料庫的請求，不會真的送到 GA、也不會真的訂位。資料都是假的。
// 用法（要有 playwright）：先在 tool/book 開 `python3 -m http.server 8766`，再 `node tool/book_check/ga_check.cjs`。
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const book = path.join(__dirname, '..', 'book');
const avail = fs.readFileSync(__dirname + '/avail.json', 'utf8');
const ok = JSON.stringify({ token: 'tok123', display_name: '測試店', date: '2026-11-18', time: '20:00', party: 2, name: '王 先生' });
let pass = 0, fail = 0;
const check = (name, got, want) => { const y = JSON.stringify(got) === JSON.stringify(want); y ? pass++ : fail++; console.log((y ? 'PASS ' : 'FAIL ') + name + (y ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want))); };

// 跑 ga.py（跟部署一樣），回傳放好 GA4 的頁面和 ga.py 印出的訊息
function inject(id) {
  const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'ga-')), 'index.html');
  fs.copyFileSync(path.join(book, 'index.html'), f);
  const out = execFileSync('python3', [path.join(book, 'ga.py'), id, 'https://booking.barcitynorth.com', f], { encoding: 'utf8' });
  return { html: fs.readFileSync(f, 'utf8'), out };
}

async function run(name, html, result, steps) {
  const b = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME, args: ['--no-sandbox'] } : {});
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, locale: 'zh-TW', timezoneId: 'Asia/Taipei' });
  const google = [];
  await p.route('https://www.googletagmanager.com/**', (r) => { google.push(r.request().url()); r.fulfill({ status: 200, contentType: 'text/javascript', body: '' }); });
  await p.route('**/rest/v1/rpc/reservation_availability', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: avail }));
  await p.route('**/functions/v1/**', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: '{"sent":true}' }));
  await p.route('**/rest/v1/rpc/book_reservation', (r) => result === 'ok'
    ? r.fulfill({ status: 200, contentType: 'application/json', body: ok })
    : r.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'P0001', message: '這天的訂位已滿，請選別天或直接來電' }) }));
  await p.route('http://localhost:8766/ga-test.html*', (r) => r.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: html }));
  await p.goto('http://localhost:8766/ga-test.html?s=yincheng&intro=0', { waitUntil: 'networkidle' });
  await p.waitForTimeout(800);
  await p.click('#cal button[data-d="2026-11-18"]');
  await p.click('#slots button[data-t="20:00"]');
  await p.fill('#name', '王'); await p.click('#titles .chip[data-t="先生"]');
  await p.fill('#phone', '0912345678'); await p.fill('#email', 'a@test.tw'); await p.fill('#note', '靠窗');
  await p.click('#submit'); await p.waitForTimeout(900);
  const layer = await p.evaluate(() => (window.dataLayer || []).map((a) => Array.from(a)));
  const done = await p.$eval('#done', (e) => !e.hidden);
  await steps({ google, layer, done, gtag: await p.evaluate(() => typeof window.gtag) });
  await b.close();
}

(async () => {
  const raw = fs.readFileSync(path.join(book, 'index.html'), 'utf8');
  check('原始頁面只有一個 <!--GA--> 記號', raw.split('<!--GA-->').length, 2);
  check('取消頁不放 GA4（網址帶取消碼）', /<!--GA-->|googletagmanager/.test(fs.readFileSync(path.join(book, 'cancel.html'), 'utf8')), false);

  const none = inject('');
  check('沒填 ID：記號拿掉、沒有 Google 的程式', [none.html.includes('<!--GA-->'), none.html.includes('googletagmanager')], [false, false]);
  const bad = inject('UA-12345-1');
  check('ID 格式不對：不載入、部署記錄有警告', [bad.html.includes('googletagmanager'), bad.out.includes('::warning')], [false, true]);
  const good = inject('G-TEST1234');
  check('有填 ID：載入 Google 的程式', good.html.includes('gtag/js?id=G-TEST1234'), true);

  await run('沒填 ID 時訂位成功', none.html, 'ok', async (s) => {
    check('沒填 ID：沒有連到 Google、沒有 gtag', [s.google.length, s.gtag], [0, 'undefined']);
    check('沒填 ID：客人照樣看到訂位成功', s.done, true);
  });
  await run('有填 ID 時訂位成功', good.html, 'ok', async (s) => {
    check('有填 ID：載入 gtag/js', s.google.some((u) => u.includes('/gtag/js?id=G-TEST1234')), true);
    const config = s.layer.find((a) => a[0] === 'config');
    check('跨網域：官網和訂位頁', config && config[2].linker.domains, ['barcitynorth.com', 'booking.barcitynorth.com']);
    check('訂位成功只送一次 booking_complete，只帶人數', s.layer.filter((a) => a[0] === 'event'), [['event', 'booking_complete', { party_size: 2 }]]);
    const sent = JSON.stringify(s.layer);
    check('沒有送出姓名、電話、Email、備註、日期、時間', ['王', '0912345678', 'a@test.tw', '靠窗', '2026-11-18', '20:00', 'tok123'].filter((v) => sent.includes(v)), []);
    check('有填 ID：客人照樣看到訂位成功', s.done, true);
  });
  await run('有填 ID 但訂位失敗', good.html, 'full', async (s) => {
    check('訂位沒成功：不送 booking_complete', s.layer.filter((a) => a[0] === 'event'), []);
    check('訂位沒成功：沒有顯示成功', s.done, false);
  });
  console.log(`\n${pass} pass / ${fail} fail`);
  process.exit(fail ? 1 : 0);
})();
