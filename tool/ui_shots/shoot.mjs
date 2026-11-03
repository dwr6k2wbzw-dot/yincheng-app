// 畫面截圖檢查（ui-shots.yml）：開示範版 App，依序點下方分頁截圖。
// 用法：node shoot.mjs <網址> <輸出資料夾>
import { chromium } from 'playwright';
import fs from 'node:fs';
const [url, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, locale: 'zh-TW', timezoneId: 'Asia/Taipei' });
p.on('pageerror', (e) => console.log('pageerror', e.message));
await p.goto(url, { waitUntil: 'networkidle' });
await p.waitForTimeout(6000); // 等 Flutter 與中文字型載入
const tabs = Number(process.env.TABS || 5);
for (let i = 0; i < tabs; i++) {
  await p.mouse.click((390 / tabs) * (i + 0.5), 844 - 40);
  await p.waitForTimeout(2500);
  await p.screenshot({ path: `${out}/tab${i}-a.png` });
  await p.mouse.move(195, 450);
  await p.mouse.wheel(0, 700);
  await p.waitForTimeout(1200);
  await p.screenshot({ path: `${out}/tab${i}-b.png` });
  await p.mouse.wheel(0, -2000);
}
await b.close();
