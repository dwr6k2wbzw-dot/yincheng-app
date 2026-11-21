// 部署時把 i18n.js 某個語言的固定文字印成 JSON，給 seo.py 產生靜態頁用（2026-11-10）。
// 店家自己的文字（低消、營業時間說明、外語地址）0135 起在訂位頁資料（stores.json 的 profile 是快照），不在這裡。
// minAmount 印成「每人 {n} 元」這種樣子，seo.py 再換成金額。用法：node i18n_dump.js en
const fs = require('fs'), path = require('path');
const lang = process.argv[2] || 'en';
const g = { location: { search: '?lang=' + lang }, document: { documentElement: { dataset: {} } }, URLSearchParams };
g.window = g;
new Function('window', 'location', 'document', fs.readFileSync(path.join(__dirname, 'i18n.js'), 'utf8'))(g, g.location, g.document);
const t = (k, ...a) => g.YCI.t(k, ...a);
const out = { minAmount: t('minAmount', '{n}') };
for (const k of ['htmlLang', 'booking', 'loading', 'date', 'time', 'party', 'contact', 'less', 'more', 'name', 'namePh', 'titles', 'mr', 'ms',
  'phone', 'email', 'note', 'submit', 'privacy', 'address', 'tel', 'minSpend']) out[k] = t(k);
process.stdout.write(JSON.stringify(out));
