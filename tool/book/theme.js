// 節慶風格（老闆 2026-10-17）：依台北日期自動換上節慶裝飾，過了就恢復黑金原樣。
// 預覽：網址加 ?theme=halloween；關掉：?theme=none。
// 新增節慶：在 THEMES 加一筆（日期 MM-DD，含頭尾），style.css 加對應的 .t-<id> 樣式。
(function () {
  const THEMES = [
    // off：不自動換上（老闆 2026-10-21 拿掉萬聖節風格；?theme=halloween 仍可預覽）
    { id: 'halloween', from: '10-20', to: '10-31', off: true,
      greet: { zh: '萬聖節快樂', en: 'Happy Halloween', ja: 'ハッピーハロウィン' } },
    // 小城外十週年（老闆 2026-10-23：只顯示小城外，即日起到 11/30）
    { id: 'anniv10', from: '10-23', to: '11-30', stores: ['xcw'],
      greet: { zh: '十 週 年', en: 'TENTH ANNIVERSARY', ja: '十 周 年' } },
  ];

  const q = new URLSearchParams(location.search).get('theme');
  // 台北日期（客人手機時區不一定是台北）
  const md = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Taipei', month: '2-digit', day: '2-digit' })
    .format(new Date()).replace('/', '-');
  const inRange = (t) => t.from <= t.to ? (md >= t.from && md <= t.to) : (md >= t.from || md <= t.to);
  const slug = new URLSearchParams(location.search).get('s') || document.documentElement.dataset.slug || '';
  const forStore = (t) => !t.stores || t.stores.includes(slug); // stores：只在這幾家店顯示
  const theme = q === 'none' ? null : (THEMES.find((t) => t.id === q) || (q ? null : THEMES.find((t) => !t.off && inRange(t) && forStore(t))));
  if (!theme) return;

  const lang = (window.YCI && YCI.lang) || 'zh';
  document.body.classList.add('t-' + theme.id);

  if (theme.id === 'anniv10') {
    // 十週年（2026-10-29 收斂）：只留一個安靜的燙金「10」＋一行字，不放光芒、金箔、星星
    const head = document.querySelector('header.brand');
    if (head) {
      const g = document.createElement('div');
      g.className = 'anniv';
      g.innerHTML = '<span class="rule" aria-hidden="true"></span><b class="ten">10</b><span class="rule" aria-hidden="true"></span>' +
        '<p class="ann">' + (theme.greet[lang] || theme.greet.zh) + '</p>';
      const anchor = head.querySelector('.kicker') || head.querySelector('h1');
      if (anchor) anchor.after(g); else head.append(g);
    }
    return;
  }

  const bat = '<svg viewBox="0 0 64 32" aria-hidden="true"><path fill="currentColor" d="M32 10c-2 0-3 2-3.5 3.5C27 11 24 9 20 9c2 3 1 6-1 7-2-3-6-5-11-4 3 2 4 5 3 8 4-2 9-1 12 2 2-2 5-2 9-1 4-1 7-1 9 1 3-3 8-4 12-2-1-3 0-6 3-8-5-1-9 1-11 4-2-1-3-4-1-7-4 0-7 2-8.5 4.5C35 12 34 10 32 10z"/><circle cx="30.5" cy="14" r=".8" fill="#0A0A09"/><circle cx="33.5" cy="14" r=".8" fill="#0A0A09"/></svg>';
  const ghost = '<svg viewBox="0 0 40 48" aria-hidden="true"><path fill="currentColor" d="M20 2C10 2 4 10 4 20v24l5-4 5 4 6-4 6 4 5-4 5 4V20C36 10 30 2 20 2z"/><ellipse cx="14.5" cy="20" rx="2.6" ry="3.6" fill="#0A0A09"/><ellipse cx="25.5" cy="20" rx="2.6" ry="3.6" fill="#0A0A09"/><ellipse cx="20" cy="29" rx="3" ry="2.2" fill="#0A0A09"/></svg>';
  const pumpkin = '<svg viewBox="0 0 48 44" aria-hidden="true"><path fill="#6E8A3A" d="M23 3c2-2 5-2 6 0-2 1-3 3-3 6h-3c0-2 0-4 0-6z"/><ellipse cx="15" cy="26" rx="12" ry="16" fill="#E07B2C"/><ellipse cx="33" cy="26" rx="12" ry="16" fill="#E07B2C"/><ellipse cx="24" cy="26" rx="11" ry="17" fill="#F0913A"/><path class="pk-face" fill="#FFD27A" d="M14 21l5-4 2 6zM34 21l-5-4-2 6zM13 30c4 4 18 4 22 0-2 5-6 7-11 7s-9-2-11-7zm6 1v3h3v-3zm7 0v3h3v-3z"/></svg>';

  // 裝飾層：不擋點擊、不影響閱讀；系統設定「減少動態效果」時不動
  const fx = document.createElement('div');
  fx.className = 'fx';
  fx.setAttribute('aria-hidden', 'true');
  fx.innerHTML =
    '<span class="moon"></span>' +
    '<span class="bat b1">' + bat + '</span><span class="bat b2">' + bat + '</span><span class="bat b3">' + bat + '</span>' +
    '<span class="ghost g1">' + ghost + '</span><span class="ghost g2">' + ghost + '</span>' +
    '<span class="web"></span><span class="fog"></span>';
  document.body.prepend(fx);

  const head = document.querySelector('header.brand');
  if (head) {
    const g = document.createElement('p');
    g.className = 'greet';
    g.innerHTML = '<span class="pk">' + pumpkin + '</span><span>' + (theme.greet[lang] || theme.greet.zh) + '</span><span class="pk">' + pumpkin + '</span>';
    const anchor = head.querySelector('.kicker') || head.querySelector('h1');
    if (anchor) anchor.after(g); else head.append(g);
  }
})();
