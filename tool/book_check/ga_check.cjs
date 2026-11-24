// 訂位頁 GA4（2026-11-24，tool/book/ga.py）的檢查：沒填評估 ID 不載入；有填時訂位成功只送 booking_complete＋人數，不送個人資料。
// 有填 ID 的那兩次用正式的評估 ID 載入 Google 真的 gtag.js（要能上網）：假的 ID 沒有後台設定，測不出 config 被略過的問題
// （2026-11-24 正式站實測）。送往 GA 的請求全部攔下來檢查、不會真的送出；
// 對資料庫的請求也攔下來，不會真的訂位。資料都是假的。
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

// 一次 GA 請求裡可能有好幾個事件：網址參數共用，POST 內容每行一個事件
function parseHits(url, body) {
  const u = new URL(url);
  const lines = (body || '').split('\n').filter(Boolean);
  return (lines.length ? lines : ['']).map((line) => {
    const q = new URLSearchParams(u.search);
    new URLSearchParams(line).forEach((v, k) => q.set(k, v));
    return Object.fromEntries(q);
  });
}

// 網址帶假的日期、人數、Email、取消碼；來源是帶取消碼的取消頁，檢查這些都不會送到 GA
const PAGE = 'http://localhost:8766/ga-test.html?s=yincheng&intro=0&d=2026-11-18&p=2&email=b%40test.tw&t=URLSECRET&_gl=1*abc*_ga*MTIz&utm_source=ig';
const ID = 'G-6G8JJPVC7B';
const FROM = 'http://localhost:8766/cancel.html?t=REFSECRET';

async function run(name, html, result, steps) {
  const b = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME, args: ['--no-sandbox'] } : {});
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, locale: 'zh-TW', timezoneId: 'Asia/Taipei' });
  const google = [], hits = [], raw = [];
  await p.route('https://www.googletagmanager.com/**', (r) => { google.push(r.request().url()); r.continue(); });
  await p.route(/google-analytics\.com|analytics\.google\.com|\/g\/collect/, (r) => {
    raw.push(decodeURIComponent(r.request().url()) + '\n' + decodeURIComponent(r.request().postData() || ''));
    hits.push(...parseHits(r.request().url(), r.request().postData()));
    r.fulfill({ status: 204, body: '' });
  });
  await p.route('**/rest/v1/rpc/reservation_availability', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: avail }));
  await p.route('**/functions/v1/**', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: '{"sent":true}' }));
  await p.route('**/rest/v1/rpc/book_reservation', (r) => result === 'ok'
    ? r.fulfill({ status: 200, contentType: 'application/json', body: ok })
    : r.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'P0001', message: '這天的訂位已滿，請選別天或直接來電' }) }));
  await p.route('http://localhost:8766/ga-test.html*', (r) => r.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', body: html }));
  await p.goto(PAGE, { referer: FROM, waitUntil: 'networkidle' });
  await p.waitForTimeout(800);
  await p.click('#cal button[data-d="2026-11-18"]');
  await p.click('#slots button[data-t="20:00"]');
  await p.fill('#name', '王'); await p.click('#titles .chip[data-t="先生"]');
  await p.fill('#phone', '0912345678'); await p.fill('#email', 'a@test.tw'); await p.fill('#note', '靠窗');
  await p.click('#submit'); await p.waitForTimeout(900);
  // GA 會把事件攢一下才送，最多等 15 秒
  if (google.length) for (let i = 0; i < 30 && !hits.some((h) => h.en === 'booking_complete'); i++) await p.waitForTimeout(500);
  const layer = await p.evaluate(() => (window.dataLayer || []).map((a) => Array.from(a)));
  const done = await p.$eval('#done', (e) => !e.hidden);
  await steps({ google, hits, raw: raw.join('\n'), layer, done, gtag: await p.evaluate(() => typeof window.gtag) });
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
  const good = inject(ID);
  check('有填 ID：放進 Google 的程式和評估 ID', [good.html.includes('googletagmanager.com/gtag/js?id='), good.html.includes(JSON.stringify(ID))], [true, true]);

  await run('沒填 ID 時訂位成功', none.html, 'ok', async (s) => {
    check('沒填 ID：沒有連到 Google、沒有 gtag', [s.google.length, s.hits.length, s.gtag], [0, 0, 'undefined']);
    check('沒填 ID：客人照樣看到訂位成功', s.done, true);
  });
  await run('有填 ID 時訂位成功', good.html, 'ok', async (s) => {
    check('有填 ID：載入 gtag/js', s.google.some((u) => u.includes('/gtag/js?id=' + ID)), true);
    const config = s.layer.find((a) => a[0] === 'config');
    check('跨網域：官網和訂位頁', config && config[2].linker.domains, ['barcitynorth.com', 'booking.barcitynorth.com']);
    check('訂位成功只送一次 booking_complete，只帶人數', s.layer.filter((a) => a[0] === 'event'), [['event', 'booking_complete', { party_size: 2 }]]);
    const pv = s.hits.find((h) => h.en === 'page_view');
    check('網址只留店別和來源（日期、人數、Email、取消碼、_gl 拿掉）', pv && pv.dl, 'http://localhost:8766/ga-test.html?s=yincheng&utm_source=ig');
    check('之後的事件也是清理過的網址', [...new Set(s.hits.map((h) => h.dl))], ['http://localhost:8766/ga-test.html?s=yincheng&utm_source=ig']);
    const fst = s.hits.find((h) => h.en === 'form_start');
    check('form_start 的 form_destination 也是清理過的網址', fst && fst['ep.form_destination'], 'http://localhost:8766/ga-test.html?s=yincheng&utm_source=ig');
    check('來源網址（取消頁）拿掉取消碼', pv && pv.dr, 'http://localhost:8766/cancel.html');
    const bc = s.hits.filter((h) => h.en === 'booking_complete');
    check('GA 收到一次 booking_complete，人數 2', bc.map((h) => h['epn.party_size']), ['2']);
    const sent = JSON.stringify(s.layer) + s.raw;
    check('沒有送出姓名、電話、Email、備註、日期、時間、取消碼', ['王', '0912345678', 'a@test.tw', 'b@test.tw', '靠窗', '2026-11-18', '20:00', 'tok123', 'URLSECRET', 'REFSECRET'].filter((v) => sent.includes(v)), []);
    check('有填 ID：客人照樣看到訂位成功', s.done, true);
  });
  await run('有填 ID 但訂位失敗', good.html, 'full', async (s) => {
    check('訂位沒成功：不送 booking_complete', [s.layer.filter((a) => a[0] === 'event'), s.hits.filter((h) => h.en === 'booking_complete').length], [[], 0]);
    check('訂位沒成功：沒有顯示成功', s.done, false);
  });
  console.log(`\n${pass} pass / ${fail} fail`);
  process.exit(fail ? 1 : 0);
})();
