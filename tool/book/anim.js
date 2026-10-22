// 訂位頁動畫（老闆 2026-10-18：「訂位介面可以做成有趣的動畫嗎」）——電影院主題
//   1. 開場倒數：第一次打開（同一個分頁只放一次）放 3・2・1 電影片頭倒數，點一下可跳過
//   2. 封面：背景照片慢慢推近、放映機光束掃過、底片顆粒；店名像對焦一樣清楚起來
//   3. 卡片：往下滑時一張張浮上來；選日期、時段會輕輕彈一下
//   4. 訂位成功：變成一張電影票，蓋上「已訂位」章，爆米花噴出來
//   小城外（老闆 2026-10-18：老宅、王家衛）另一套：開場老時鐘＋一句話、封面壁燈閃爍＋煙、
//   店名霓虹抽格（step-printing），訂位成功變一張手寫便條：時鐘指到訂位時間、蓋郵戳。
// 手機設定「減少動態效果」時全部不動；網址加 ?anim=0 也可以關掉。
(function () {
  const q = new URLSearchParams(location.search);
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduce || q.get('anim') === '0') return;
  const lang = (window.YCI && YCI.lang) || 'zh';
  const wkw = (q.get('s') || document.documentElement.dataset.slug) === 'xcw'; // 小城外：老宅、王家衛
  const W = {
    zh: { skip: '點一下跳過', stamp: '已訂位', admit: '入場券', seat: '座位保留中',
          line: '時間，在這裡慢了下來', see: (t) => t + '，不見不散' },
    en: { skip: 'Tap to skip', stamp: 'RESERVED', admit: 'ADMIT', seat: 'Your table is waiting',
          line: 'Here, time slows down.', see: (t) => 'See you at ' + t + '.' },
    ja: { skip: 'タップでスキップ', stamp: '予約済', admit: '入場券', seat: 'お席をご用意します',
          line: 'ここでは、時間がゆっくり流れる。', see: (t) => t + '、お待ちしています' },
  }[lang] || {};
  document.documentElement.classList.add('anim');
  if (wkw) document.documentElement.classList.add('wkw');

  // ---------- 1. 開場倒數 ----------
  let seen = false;
  try { seen = sessionStorage.getItem('yc_intro') === '1'; sessionStorage.setItem('yc_intro', '1'); } catch (_) { seen = true; }
  // 小城外開場（老闆可選）：clock 老時鐘／door 推開老木門／rain 雨夜霓虹／sky 仰望天井／letter 拆一封信／grand 老爺鐘＋蒂芬妮桌燈（店裡實景）
  const WKW_INTRO = 'grand'; // 老闆 2026-10-18 選 E
  const pick = ['clock', 'door', 'rain', 'sky', 'letter', 'grand'].includes(q.get('intro')) ? q.get('intro') : WKW_INTRO;
  if (q.get('intro') && q.get('intro') !== '0') seen = false; // 預覽用：網址指定就每次都放
  if (!seen && q.get('intro') !== '0' && wkw) {
    const o = document.createElement('div');
    o.className = 'intro wk wk-' + pick;
    o.setAttribute('aria-hidden', 'true');
    const line = '<p class="line">' + (W.line || '') + '</p>';
    const skip = '<span class="skip">' + (W.skip || '') + '</span>';
    let dur = 2600;
    if (pick === 'door') {
      // 推開老木門：門縫透光、兩扇門往內打開
      o.innerHTML = '<div class="glow"></div>' + line +
        '<div class="door l"><i class="pn"></i><i class="pn"></i><b class="knob"></b></div>' +
        '<div class="door r"><i class="pn"></i><i class="pn"></i><b class="knob"></b></div>' + skip;
      dur = 3000;
    } else if (pick === 'rain') {
      // 雨夜霓虹：雨絲落下、「小城外」霓虹招牌閃幾下亮起、地上倒影
      let drops = '';
      for (let i = 0; i < 46; i++) drops += '<i style="left:' + (Math.random() * 100).toFixed(1) + '%;animation-delay:' + (-Math.random()).toFixed(2) + 's;animation-duration:' + (0.45 + Math.random() * 0.35).toFixed(2) + 's;opacity:' + (0.25 + Math.random() * 0.5).toFixed(2) + '"></i>';
      o.innerHTML = '<div class="rain">' + drops + '</div><div class="sign"><b>小城外</b><b class="refl">小城外</b></div>' + line + skip;
      dur = 3000;
    } else if (pick === 'sky') {
      // 仰望天井：黑暗中一方天光慢慢打開、灰塵在光裡飄，最後光鋪滿畫面
      let dust = '';
      for (let i = 0; i < 26; i++) dust += '<i style="left:' + (20 + Math.random() * 60).toFixed(1) + '%;top:' + (20 + Math.random() * 60).toFixed(1) + '%;animation-delay:' + (-Math.random() * 4).toFixed(2) + 's"></i>';
      o.innerHTML = '<div class="well"><div class="light">' + dust + '</div></div>' + line + skip;
      dur = 3000;
    } else if (pick === 'grand') {
      // 老爺鐘＋蒂芬妮桌燈（老闆 2026-10-18 給的店內照片）：桌燈「喀」一聲亮起，照亮老爺鐘，鐘擺擺動、指針走
      const R = ['XII', 'I', 'II', 'III', 'IIII', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI'];
      let nums = '';
      R.forEach((r, i) => {
        const a = (i * 30 - 90) * Math.PI / 180;
        nums += '<text x="' + (200 + Math.cos(a) * 33).toFixed(1) + '" y="' + (128 + Math.sin(a) * 33 + 3).toFixed(1) + '">' + r + '</text>';
      });
      // 2026-10-22 老闆選「光影＋王家衛鏡頭感」：（天井樓梯）→ 黑暗中桌燈亮起、彩色玻璃投在老牆、光束裡飄灰塵、
      // 窗外雨夜霓虹、鐘擺抽格殘影、墨綠暗紅調色＋底片顆粒＋暗角、鏡頭慢慢推近
      let dust = '', rain = '', bokeh = '';
      for (let i = 0; i < 22; i++) dust += '<i style="left:' + (8 + Math.random() * 80).toFixed(1) + '%;top:' + (10 + Math.random() * 80).toFixed(1) + '%;animation-delay:' + (-Math.random() * 6).toFixed(2) + 's;animation-duration:' + (5 + Math.random() * 4).toFixed(1) + 's"></i>';
      for (let i = 0; i < 14; i++) rain += '<i style="left:' + (Math.random() * 100).toFixed(1) + '%;animation-delay:' + (-Math.random() * 3).toFixed(2) + 's;animation-duration:' + (1.6 + Math.random() * 1.6).toFixed(2) + 's"></i>';
      ['#E0574A', '#3FA27A', '#E8A33C', '#E0574A', '#5A7FD0'].forEach((c, i) => {
        bokeh += '<b style="left:' + (10 + i * 18 + Math.random() * 8).toFixed(1) + '%;top:' + (25 + Math.random() * 45).toFixed(1) + '%;background:' + c + ';animation-delay:' + (-Math.random() * 4).toFixed(2) + 's"></b>';
      });
      // 2026-10-22 老闆：門拿掉，改成店裡的天井樓梯（老闆給的照片）：壁燈亮起、照亮掛著小城外招牌的老牆與磨石子扶手，
      // 鏡頭沿著樓梯往上爬，抽格切進二樓的老爺鐘與桌燈
      const sc = document.querySelector('script[src*="anim.js"]');
      const logoUrl = new URL('logo-xcw.png', sc ? sc.src : location.href).href;
      let sdust = '';
      for (let i = 0; i < 16; i++) sdust += '<i style="left:' + (8 + Math.random() * 40).toFixed(1) + '%;top:' + (8 + Math.random() * 40).toFixed(1) + '%;animation-delay:' + (-Math.random() * 6).toFixed(2) + 's;animation-duration:' + (5 + Math.random() * 4).toFixed(1) + 's"></i>';
      const stair = '<div class="stair"><div class="cam"><svg viewBox="0 0 360 640" preserveAspectRatio="xMidYMid slice">' +
        '<defs><radialGradient id="sw" cx=".3" cy=".13" r="1"><stop offset="0" stop-color="#EBC9AE"/><stop offset=".22" stop-color="#B98670"/><stop offset=".55" stop-color="#6E4638"/><stop offset="1" stop-color="#24160F"/></radialGradient>' +
        '<filter id="tz" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="1.6" numOctaves="1" seed="4"/><feColorMatrix values="0 0 0 0 .36  0 0 0 0 .32  0 0 0 0 .28  0 0 0 -2.2 1.35"/><feComposite in2="SourceGraphic" operator="in"/></filter>' +
        '<linearGradient id="tzc" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7A6658"/><stop offset="1" stop-color="#2A201A"/></linearGradient>' +
        '<linearGradient id="fr" x1="0" x2="1"><stop offset="0" stop-color="#5A1E0E"/><stop offset=".5" stop-color="#9A3E1E"/><stop offset="1" stop-color="#5A1E0E"/></linearGradient></defs>' +
        '<rect width="360" height="640" fill="url(#sw)"/>' +
        // 左邊：暗色門框、上方小窗、牆角柱
        '<rect x="0" y="0" width="46" height="640" fill="#1E1714"/><rect x="6" y="210" width="34" height="430" fill="#120D0B" stroke="#3A2C24" stroke-width="2"/>' +
        '<rect x="8" y="20" width="30" height="150" fill="#2A2420"/><rect x="11" y="26" width="24" height="64" class="swin"/><rect x="11" y="96" width="24" height="68" fill="#3B3632"/>' +
        '<rect x="46" y="0" width="34" height="640" fill="#A27C69" opacity=".75"/><line x1="80" y1="0" x2="80" y2="640" stroke="#5A3E33" stroke-width="1.5"/>' +
        // 壁燈：鑄鐵臂、六角燈籠
        '<g class="lant"><path d="M84 132 Q96 132 100 120 L106 110" fill="none" stroke="#2A2422" stroke-width="4"/><rect x="80" y="118" width="8" height="26" rx="3" fill="#2A2422"/>' +
        '<path d="M96 66 L118 66 L124 80 L90 80 Z" fill="#2A2422"/><path d="M106 56 L112 66 H100 Z" fill="#2A2422"/>' +
        '<path d="M92 80 H122 L118 108 H96 Z" class="lglass"/><rect x="94" y="108" width="26" height="6" fill="#2A2422"/></g>' +
        // 木框招牌：深色板子、金色 logo、小城外
        '<g class="plaq"><rect x="128" y="196" width="104" height="104" fill="url(#fr)"/><rect x="134" y="202" width="92" height="92" fill="none" stroke="#C88A4E" stroke-width="1"/>' +
        '<rect x="140" y="208" width="80" height="80" fill="#26291F"/><image href="' + logoUrl + '" x="164" y="216" width="32" height="32"/>' +
        '<text x="180" y="266" class="pq">小城外</text><text x="180" y="278" class="pq en">CITY NORTH</text></g>' +
        // 牆上管線與開關
        '<path d="M80 336 H176" stroke="#E8D4C4" stroke-width="4" opacity=".7"/><rect x="176" y="328" width="26" height="16" rx="1.5" fill="#E9DED2"/><rect x="183" y="332" width="12" height="8" fill="#D6CABD"/>' +
        // 磨石子樓梯扶手：斜斜往右上爬
        '<path d="M190 640 V452 L360 262 V640 Z" fill="url(#tzc)"/><path d="M190 640 V452 L360 262 V640 Z" fill="#000" filter="url(#tz)" opacity=".9"/>' +
        '<path d="M180 452 L190 452 L360 262 L360 250 Z" fill="#8A7E72"/><path d="M180 452 H190 V640 H180 Z" fill="#4A4038"/>' +
        '<path d="M204 470 L212 476 L206 560 L214 640 H202 L198 560 Z" fill="#E9E0D4" opacity=".75"/>' +
        '<path d="M340 300 L360 290 V330 Z" fill="none" stroke="#1E1A16" stroke-width="2"/>' +
        '</svg><div class="sdust">' + sdust + '</div></div><div class="sglow"></div></div>';
      o.innerHTML = '<div class="stage"><div class="wall"></div><div class="win">' + bokeh + '<span class="rn">' + rain + '</span></div>' +
        '<div class="tints"><i></i><i></i><i></i></div><div class="beam">' + dust + '</div>' +
        '<div class="lampglow"></div><svg class="room" viewBox="0 0 360 560" preserveAspectRatio="xMidYMid meet">' +
        '<defs><linearGradient id="wd" x1="0" x2="1"><stop offset="0" stop-color="#5A2E18"/><stop offset=".5" stop-color="#8A4A26"/><stop offset="1" stop-color="#4A2412"/></linearGradient>' +
        '<radialGradient id="gd" cx=".4" cy=".35"><stop offset="0" stop-color="#F7E3A6"/><stop offset=".6" stop-color="#C9A04E"/><stop offset="1" stop-color="#7A5A22"/></radialGradient>' +
        '<radialGradient id="dl" cx=".5" cy=".5"><stop offset="0" stop-color="#EFE2BE"/><stop offset="1" stop-color="#BFA36A"/></radialGradient></defs>' +
        // 老爺鐘：圓拱頂、鐘面、長箱、鐘擺
        '<g class="gclock"><path d="M150 70 Q200 30 250 70 V200 H150 Z" fill="url(#wd)"/><rect x="140" y="196" width="120" height="14" fill="#6B3519"/>' +
        '<rect x="158" y="80" width="84" height="104" rx="4" fill="url(#gd)" opacity=".9"/>' +
        '<circle cx="200" cy="128" r="42" fill="url(#dl)" stroke="#9C7A3A" stroke-width="3"/>' +
        '<circle cx="200" cy="128" r="26" fill="none" stroke="#9C7A3A" stroke-width="1" opacity=".6"/>' + nums +
        '<line x1="200" y1="128" x2="200" y2="108" class="gh"/><line x1="200" y1="128" x2="200" y2="96" class="gm"/><circle cx="200" cy="128" r="3" fill="#3A2A12"/>' +
        '<rect x="152" y="210" width="96" height="290" fill="url(#wd)"/><rect x="166" y="226" width="68" height="250" rx="3" fill="#2A140A" stroke="#A86A34" stroke-width="2"/>' +
        // 鐘擺＋兩道抽格殘影（王家衛 step-printing）
        '<g class="pend ghost g2nd"><line x1="200" y1="228" x2="200" y2="400" stroke="#C9A04E" stroke-width="2"/><circle cx="200" cy="410" r="20" fill="url(#gd)"/></g>' +
        '<g class="pend ghost g1st"><line x1="200" y1="228" x2="200" y2="400" stroke="#C9A04E" stroke-width="2"/><circle cx="200" cy="410" r="20" fill="url(#gd)"/></g>' +
        '<g class="pend"><line x1="200" y1="228" x2="200" y2="400" stroke="#C9A04E" stroke-width="2"/><circle cx="200" cy="410" r="20" fill="url(#gd)"/></g>' +
        '<line x1="186" y1="232" x2="186" y2="330" stroke="#B8903E" stroke-width="1.2"/><line x1="214" y1="232" x2="214" y2="350" stroke="#B8903E" stroke-width="1.2"/>' +
        '<rect x="144" y="500" width="112" height="16" fill="#4A2412"/></g>' +
        // 蒂芬妮桌燈：彩色玻璃燈罩、鵝頸銅管、圓底座
        '<g class="tlamp" transform="translate(-27.5 -260) scale(1.5)"><path d="M70 520 Q70 506 95 504 Q120 506 120 520 Z" fill="#B8903E"/><path d="M95 504 V470 Q95 400 70 392" fill="none" stroke="#B8903E" stroke-width="4"/>' +
        '<g class="shade"><path d="M40 430 Q42 392 70 386 Q98 392 100 430 Z" fill="#3B2A10"/>' +
        '<path d="M44 428 Q46 398 70 391 L70 428 Z" class="g1"/><path d="M70 391 Q94 398 96 428 L70 428 Z" class="g2"/>' +
        '<path d="M52 410 L64 400 L70 416 L58 424 Z" class="g3"/><path d="M76 402 L88 408 L84 424 L72 420 Z" class="g4"/>' +
        '<path d="M60 396 L70 392 L80 396 L70 404 Z" class="g5"/><path d="M40 430 H100 L96 436 H44 Z" fill="#7A5A22"/></g></g>' +
        '</svg>' + line + '</div>' +
        stair + '<div class="grade"></div><div class="grain"></div><div class="vig"></div>' + skip;
      dur = 5000;
    } else if (pick === 'letter') {
      // 拆一封信：牛皮信封、紅色火漆，封口打開、信紙抽出來寫著一句話
      o.innerHTML = '<div class="env"><div class="paper"><p>' + (W.line || '') + '</p></div><div class="body"></div><div class="flap"></div><b class="seal">外</b></div>' + skip;
      dur = 3200;
    } else {
      // 老時鐘滴答＋一句話，抽格淡出
      let ticks = '';
      for (let i = 0; i < 12; i++) ticks += '<line x1="100" y1="14" x2="100" y2="' + (i % 3 ? 22 : 28) + '" transform="rotate(' + i * 30 + ' 100 100)"/>';
      o.innerHTML = '<div class="clock"><svg viewBox="0 0 200 200"><circle cx="100" cy="100" r="92" class="face"/>' + ticks +
        '<line x1="100" y1="100" x2="100" y2="52" class="hh"/><line x1="100" y1="100" x2="100" y2="30" class="mh"/>' +
        '<g class="sh"><line x1="100" y1="116" x2="100" y2="22"/></g><circle cx="100" cy="100" r="4" class="pin"/></svg></div>' + line + skip;
    }
    document.body.appendChild(o);
    const done = () => { o.classList.add('out'); setTimeout(() => o.remove(), 900); clearTimeout(t); };
    const t = setTimeout(done, dur);
    o.addEventListener('click', done);
  } else if (!seen && q.get('intro') !== '0') {
    const o = document.createElement('div');
    o.className = 'intro';
    o.setAttribute('aria-hidden', 'true');
    o.innerHTML = '<div class="leader"><svg viewBox="0 0 200 200"><circle cx="100" cy="100" r="88" class="ring"/><circle cx="100" cy="100" r="70" class="ring thin"/>' +
      '<path d="M100 0V200M0 100H200" class="cross"/><circle cx="100" cy="100" r="44" class="sweep"/></svg><b>3</b></div>' +
      '<span class="skip">' + (W.skip || '') + '</span><i class="scratch s1"></i><i class="scratch s2"></i>';
    document.body.appendChild(o);
    const num = o.querySelector('b');
    let n = 3;
    const tick = setInterval(() => {
      n -= 1;
      if (n >= 1) { num.textContent = n; num.classList.remove('pop'); void num.offsetWidth; num.classList.add('pop'); }
      else end();
    }, 560);
    function end() {
      clearInterval(tick);
      o.classList.add('out');
      setTimeout(() => o.remove(), 600);
    }
    o.addEventListener('click', end);
  }

  // ---------- 2. 封面 ----------
  const head = document.querySelector('header.brand');
  function decorateHero() {
    if (!head || !head.classList.contains('hero') || head.querySelector('.hbg')) return;
    const bg = document.createElement('div');
    bg.className = 'hbg';
    bg.style.backgroundImage = head.style.backgroundImage;
    head.style.backgroundImage = 'none';
    const grain = document.createElement('div'); grain.className = 'grain';
    if (wkw) {
      // 小城外：壁燈閃爍、煙、偏綠的色調（窗花格子老闆 2026-10-18 拿掉）
      const lamp = document.createElement('div'); lamp.className = 'lamp';
      const smoke = document.createElement('div'); smoke.className = 'smoke';
      smoke.innerHTML = '<i></i><i></i><i></i>';
      const grade = document.createElement('div'); grade.className = 'grade';
      head.prepend(bg, lamp, smoke, grade, grain);
    } else {
      const beam = document.createElement('div'); beam.className = 'beam';
      head.prepend(bg, beam, grain);
    }
    head.classList.add('cine');
  }
  decorateHero();
  // 店名、說明文字載入後才出現：等文字換好再播
  const store = document.getElementById('store');
  const sub = document.getElementById('contact');
  let titled = false;
  function reveal() {
    if (titled || !store || !store.textContent.trim() || store.textContent === (window.YCI ? YCI.t('booking') : '')) return;
    titled = true;
    store.classList.add('focus');
    if (sub) sub.classList.add('rise');
  }
  if (store) new MutationObserver(reveal).observe(store, { childList: true, characterData: true, subtree: true });
  setTimeout(() => { titled = false; reveal(); }, 2500); // 保險：載入很慢或失敗也播

  // ---------- 3. 卡片浮上來 ----------
  const io = 'IntersectionObserver' in window ? new IntersectionObserver((es) => {
    es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
  }, { threshold: 0.08 }) : null;
  function watchCards() {
    document.querySelectorAll('main .card:not(.rv)').forEach((c, i) => {
      c.classList.add('rv');
      c.style.transitionDelay = Math.min(i, 4) * 70 + 'ms';
      if (io) io.observe(c); else c.classList.add('in');
    });
  }
  watchCards();
  new MutationObserver(watchCards).observe(document.querySelector('main') || document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['hidden'] });

  // ---------- 4. 訂位成功：電影票 ----------
  const done = document.getElementById('done');
  if (done) {
    new MutationObserver(() => {
      if (done.hidden || done.classList.contains('ticket') || done.classList.contains('memo') || !done.querySelector('.big')) return;
      if (wkw) { memo(); return; }
      done.classList.add('ticket');
      const top = document.createElement('div');
      top.className = 'tk-top';
      top.innerHTML = '<span>' + (W.admit || '') + '</span><span class="tk-no">No. ' + String(Math.floor(Math.random() * 9000) + 1000) + '</span>';
      done.prepend(top);
      const stamp = document.createElement('div');
      stamp.className = 'stamp';
      stamp.textContent = W.stamp || '';
      done.appendChild(stamp);
      const pop = document.createElement('div');
      pop.className = 'popcorn';
      pop.setAttribute('aria-hidden', 'true');
      for (let i = 0; i < 18; i++) {
        const k = document.createElement('i');
        const a = (Math.PI * (0.15 + 0.7 * Math.random())) * -1; // 往上噴
        const d = 90 + Math.random() * 140;
        k.style.setProperty('--x', Math.cos(a) * d * (Math.random() < 0.5 ? -1 : 1) + 'px');
        k.style.setProperty('--y', Math.sin(a) * d + 'px');
        k.style.setProperty('--r', (Math.random() * 540 - 270) + 'deg');
        k.style.animationDelay = (0.55 + Math.random() * 0.25) + 's';
        k.style.width = k.style.height = (9 + Math.random() * 9) + 'px';
        pop.appendChild(k);
      }
      done.appendChild(pop);
      setTimeout(() => pop.remove(), 3200);
      done.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }).observe(done, { childList: true, attributes: true, attributeFilter: ['hidden'] });
  }

  // 小城外：手寫便條，時鐘指到訂位時間、蓋郵戳
  // 小城外訂位成功的樣式（老闆可選）：note 手寫便條／rail 老車票／type 打字機／postcard 明信片／grand 老爺鐘
  const WKW_DONE = 'grand'; // 老闆 2026-10-18 選 E
  function memo() {
    const kind = ['note', 'rail', 'type', 'postcard', 'grand'].includes(q.get('done')) ? q.get('done') : WKW_DONE;
    done.classList.add('memo', 'm-' + kind);
    const txt = done.textContent;
    const m = txt.match(/(\d{1,2}):(\d{2})/) || [];
    const dm = txt.match(/(\d{1,2})\/(\d{1,2})/) || [];
    const hh = +(m[1] || 20), mm = +(m[2] || 0);
    const time = (m[1] || '20') + ':' + (m[2] || '00');
    const see = W.see ? W.see(time) : time;
    const now = new Date(Date.now() + 8 * 3600e3);
    const today = now.getUTCFullYear() + '.' + (now.getUTCMonth() + 1) + '.' + now.getUTCDate();
    const hAng = (hh % 12) * 30 + mm * 0.5, mAng = mm * 6;
    const top = document.createElement('div');
    top.className = 'mm-top';
    const add = (cls, html) => { const e = document.createElement('div'); e.className = cls; e.innerHTML = html; done.appendChild(e); return e; };
    if (kind === 'rail') {
      // 老式硬卡車票：票號、日期時間大字、剪票孔
      top.innerHTML = '<div class="rl-head"><span>小城外</span><span class="rl-no">No. ' + String(Math.floor(Math.random() * 90000) + 10000) + '</span></div>' +
        '<div class="rl-big"><b>' + (dm[1] ? dm[1] + '.' + dm[2] : '') + '</b><b>' + time + '</b></div><div class="rl-line">' + see + '</div>';
      add('punch', '');
      add('rl-stamp', '<b>' + (W.stamp || '') + '</b>');
    } else if (kind === 'type') {
      // 打字機：一個字一個字打出來
      top.innerHTML = '<p class="tw"><span class="tw-t"></span><i class="caret"></i></p>';
      const t = top.querySelector('.tw-t');
      let i = 0;
      const chars = Array.from(see);
      setTimeout(function typing() { if (i < chars.length) { t.textContent += chars[i++]; setTimeout(typing, 110 + Math.random() * 90); } }, 700);
      add('tw-stamp', W.stamp || '');
    } else if (kind === 'postcard') {
      // 明信片：郵票（老爺鐘圖）＋波浪郵戳，翻面出現
      top.innerHTML = '<p class="pc-to">' + see + '</p>';
      add('pc-stamp', '<svg viewBox="0 0 60 72"><rect x="2" y="2" width="56" height="68" fill="#2F3A26"/><path d="M18 22 Q30 10 42 22 V58 H18 Z" fill="#8A4A26"/>' +
        '<circle cx="30" cy="27" r="8" fill="#EFE2BE"/><line x1="30" y1="27" x2="30" y2="22" stroke="#3A2A12" stroke-width="1.5"/><line x1="30" y1="27" x2="34" y2="29" stroke="#3A2A12" stroke-width="1.5"/>' +
        '<line x1="30" y1="38" x2="30" y2="50" stroke="#C9A04E"/><circle cx="30" cy="52" r="3.5" fill="#C9A04E"/><text x="30" y="66" text-anchor="middle" font-size="6" fill="#E8D9B8">小城外</text></svg>');
      add('pc-mark', '<svg viewBox="0 0 150 60"><circle cx="34" cy="30" r="26" fill="none" stroke="currentColor" stroke-width="2"/><text x="34" y="28" text-anchor="middle" font-size="9" fill="currentColor">' + (W.stamp || '') + '</text>' +
        '<text x="34" y="40" text-anchor="middle" font-size="7" fill="currentColor">' + today + '</text>' +
        '<path d="M64 18 q8 -6 16 0 t16 0 t16 0 t16 0 t16 0 M64 30 q8 -6 16 0 t16 0 t16 0 t16 0 t16 0 M64 42 q8 -6 16 0 t16 0 t16 0 t16 0 t16 0" fill="none" stroke="currentColor" stroke-width="2"/></svg>');
    } else if (kind === 'grand') {
      // 老爺鐘：墨綠牆、桌燈光暈、金色鐘面指到訂位時間
      const R = ['XII', 'I', 'II', 'III', 'IIII', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI'];
      let nums = '';
      R.forEach((r, i) => { const a = (i * 30 - 90) * Math.PI / 180; nums += '<text x="' + (50 + Math.cos(a) * 34).toFixed(1) + '" y="' + (50 + Math.sin(a) * 34 + 3).toFixed(1) + '">' + r + '</text>'; });
      top.innerHTML = '<svg viewBox="0 0 100 100" class="gdial"><circle cx="50" cy="50" r="47" class="rim"/><circle cx="50" cy="50" r="42" class="face"/>' + nums +
        '<line x1="50" y1="50" x2="50" y2="31" class="hh" style="--to:' + (hAng + 720) + 'deg"/><line x1="50" y1="50" x2="50" y2="20" class="mh" style="--to:' + (mAng + 1440) + 'deg"/><circle cx="50" cy="50" r="3" class="pin"/></svg>' +
        '<p class="see">' + see + '</p>';
      add('g-glow', '');
      add('postmark', '<b>' + (W.stamp || '') + '</b><small>' + today + '</small>');
    } else {
      // 手寫便條：小時鐘指到訂位時間、郵戳
      let ticks = '';
      for (let i = 0; i < 12; i++) ticks += '<line x1="50" y1="9" x2="50" y2="14" transform="rotate(' + i * 30 + ' 50 50)"/>';
      top.innerHTML = '<svg viewBox="0 0 100 100" class="mclock"><circle cx="50" cy="50" r="45"/>' + ticks +
        '<line x1="50" y1="50" x2="50" y2="28" class="hh" style="--to:' + (hAng + 720) + 'deg"/>' +
        '<line x1="50" y1="50" x2="50" y2="16" class="mh" style="--to:' + (mAng + 1440) + 'deg"/><circle cx="50" cy="50" r="3"/></svg>' +
        '<p class="see">' + see + '</p>';
      add('postmark', '<b>' + (W.stamp || '') + '</b><small>' + today + '</small>');
    }
    done.prepend(top);
    done.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
})();
