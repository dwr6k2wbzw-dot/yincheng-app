// 訂位頁資料（ops 0135）的檢查：店家內容從資料庫來時，新開的店、只開中文的店、店家亂填程式碼、姊妹店連結都對。
// 用法（要有 playwright）：先在 tool/book 開 `python3 -m http.server 8766`，再 `node tool/book_check/profile_check.cjs`
// （沒有內建瀏覽器時加 CHROME=/usr/bin/google-chrome）。資料都是假的。
const { chromium } = require('playwright');
const fs = require('fs');
const base = JSON.parse(fs.readFileSync(__dirname + '/avail.json', 'utf8'));
let pass = 0, fail = 0;
const check = (name, got, want) => { const y = JSON.stringify(got) === JSON.stringify(want); y ? pass++ : fail++; console.log((y ? 'PASS ' : 'FAIL ') + name + (y ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want))); };
const avail = (profile) => JSON.stringify({ ...base, ...(profile === undefined ? {} : { profile }) });
const evil = '<img src=x onerror="window.__x=1">';

async function open(url, locale, bySlug) {
  const b = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME, args: ['--no-sandbox'] } : {});
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, locale, timezoneId: 'Asia/Taipei' });
  await p.route('**/rest/v1/rpc/reservation_availability', (r) => {
    const s = JSON.parse(r.request().postData()).p_slug;
    r.fulfill({ status: 200, contentType: 'application/json', body: bySlug[s] || bySlug['*'] });
  });
  await p.route('**/fonts.g*/**', (r) => r.abort());
  await p.goto('http://localhost:8766/' + url, { waitUntil: 'networkidle' });
  await p.waitForTimeout(500);
  return { b, p };
}
const read = (p) => p.evaluate(() => ({
  store: document.getElementById('store').textContent,
  logo: !document.getElementById('logo').hidden,
  hero: document.querySelector('.brand').classList.contains('hero'),
  info: document.getElementById('info').innerText,
  langs: [...document.querySelectorAll('nav.langs button')].filter((x) => !x.hidden).map((x) => x.dataset.lang).join(','),
  navHidden: document.querySelector('nav.langs').hidden,
  lang: document.documentElement.lang,
  phoneRequired: document.getElementById('phone').required,
  anim: document.documentElement.classList.contains('anim'),
  injected: !!window.__x || !!document.querySelector('#info img, #alt img'),
}));

(async () => {
  // 1. 新開的店：沒有任何訂位頁資料（資料庫回一份空的）
  {
    const { b, p } = await open('index.html?s=newshop&lang=en', 'en-US', { '*': avail({ langs: ['zh'], title: {}, info_rows: [], min_spend_text: {} }) });
    const r = await read(p);
    check('新店：大標用訂位設定的店名', r.store, '測試店');
    check('新店：沒有 logo、封面照', [r.logo, r.hero], [false, false]);
    check('新店：資訊卡只有地址、電話（沒有低消）', r.info.includes('低消') || r.info.includes('Minimum'), false);
    check('新店：只開中文 → 英文的客人改看中文、電話必填', [r.lang, r.phoneRequired], ['zh-Hant-TW', true]);
    check('新店：只有一種語言，不顯示切換列', r.navHidden, true);
    check('新店：不放兩家店量身做的動畫', r.anim, false);
    await b.close();
  }
  // 2. 店家填的字含程式碼：一律當成文字
  {
    const prof = { langs: ['zh', 'en'], title: { zh: evil }, min_spend: 500, min_spend_text: { zh: '每人一杯' + evil + '{amount}' },
      info_rows: [{ label: { zh: evil }, text: { zh: '第一行\n' + evil } }], sister: { slug: 'other', short_name: { zh: evil }, intro: { zh: evil } } };
    const { b, p } = await open('index.html?s=shop&anim=0', 'zh-TW', { shop: avail(prof), other: avail({ langs: ['zh'] }) });
    const r = await read(p);
    check('亂填：大標照字面顯示', r.store, evil);
    check('亂填：低消照字面顯示、金額換進去', r.info.includes('每人一杯' + evil + '每人 500 元'), true);
    check('亂填：換行照樣換', r.info.includes('第一行\n' + evil), true);
    check('亂填：兩種語言 → 切換列只留中文、英文', r.langs, 'zh,en');
    // 這家這天滿了 → 姊妹店卡片
    const full = JSON.parse(avail(prof)); full.days[0].groups_left = 0;
    await p.route('**/rest/v1/rpc/reservation_availability', (q) => {
      const s = JSON.parse(q.request().postData()).p_slug;
      q.fulfill({ status: 200, contentType: 'application/json', body: s === 'shop' ? JSON.stringify(full) : avail({ langs: ['zh'] }) });
    });
    await p.reload({ waitUntil: 'networkidle' }); await p.waitForTimeout(400);
    await p.click('#cal button[data-d="2026-11-18"]'); await p.waitForTimeout(600);
    const alt = await p.evaluate(() => { const a = document.getElementById('alt'); return a.hidden ? null : { text: a.innerText, href: a.querySelector('a').getAttribute('href') }; });
    check('姊妹店卡片有出來', !!alt, true);
    check('姊妹店名稱照字面顯示', alt && alt.text.includes(evil), true);
    check('沒有專屬網址的姊妹店連 ?s=', alt && alt.href.startsWith('?s=other&d=2026-11-18&p=2&lang=zh&ref=from-shop'), true);
    check('亂填：頁面上沒有多出任何圖片或程式', (await read(p)).injected, false);
    await b.close();
  }
  // 3. 資料庫還沒更新（沒有 profile 欄位）：頁面照樣能用
  {
    const { b, p } = await open('index.html?s=yincheng&anim=0', 'zh-TW', { '*': avail(undefined) });
    const r = await read(p);
    check('舊資料庫：店名、地址照常', [r.store, r.info.includes('測試地址')], ['測試店', true]);
    check('舊資料庫：日期照常可以選', await p.$$eval('#cal button[data-d]', (x) => x.length) > 0, true);
    await b.close();
  }
  console.log('\n通過 ' + pass + '，失敗 ' + fail);
  process.exit(fail ? 1 : 0);
})();
