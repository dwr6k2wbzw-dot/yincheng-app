// 部署時把 i18n.js 某個語言的字串印成 JSON，給 seo.py 產生英文靜態頁用（2026-11-10）。
// 這樣英文的營業時間、低消、地址只寫在 i18n.js 一個地方。用法：node i18n_dump.js en
const fs = require('fs'), path = require('path');
const lang = process.argv[2] || 'en';
const g = { location: { search: '?lang=' + lang }, document: { documentElement: { dataset: {} } }, URLSearchParams };
g.window = g;
new Function('window', 'location', 'document', fs.readFileSync(path.join(__dirname, 'i18n.js'), 'utf8'))(g, g.location, g.document);
const t = (k, ...a) => g.YCI.t(k, ...a);
const out = { minSpendTextYc: t('minSpendTextYc', 800), minSpendText: t('minSpendText', 600) };
for (const k of ['htmlLang', 'booking', 'loading', 'date', 'time', 'party', 'contact', 'less', 'more', 'name', 'namePh', 'titles', 'mr', 'ms',
  'phone', 'email', 'note', 'submit', 'privacy', 'address', 'tel', 'minSpend', 'coffee', 'coffeeText', 'bar', 'barText', 'hoursLabel', 'ycHours',
  'addr', 'addrNote']) out[k] = t(k);
process.stdout.write(JSON.stringify(out));
