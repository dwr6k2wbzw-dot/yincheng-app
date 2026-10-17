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
  const wkw = q.get('s') === 'xcw'; // 小城外：老宅、王家衛
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
  const WKW_INTRO = 'clock';
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
      o.innerHTML = '<div class="lampglow"></div><svg class="room" viewBox="0 0 360 560" preserveAspectRatio="xMidYMid meet">' +
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
        '<g class="pend"><line x1="200" y1="228" x2="200" y2="400" stroke="#C9A04E" stroke-width="2"/><circle cx="200" cy="410" r="20" fill="url(#gd)"/></g>' +
        '<line x1="186" y1="232" x2="186" y2="330" stroke="#B8903E" stroke-width="1.2"/><line x1="214" y1="232" x2="214" y2="350" stroke="#B8903E" stroke-width="1.2"/>' +
        '<rect x="144" y="500" width="112" height="16" fill="#4A2412"/></g>' +
        // 蒂芬妮桌燈：彩色玻璃燈罩、鵝頸銅管、圓底座
        '<g class="tlamp" transform="translate(-27.5 -260) scale(1.5)"><path d="M70 520 Q70 506 95 504 Q120 506 120 520 Z" fill="#B8903E"/><path d="M95 504 V470 Q95 400 70 392" fill="none" stroke="#B8903E" stroke-width="4"/>' +
        '<g class="shade"><path d="M40 430 Q42 392 70 386 Q98 392 100 430 Z" fill="#3B2A10"/>' +
        '<path d="M44 428 Q46 398 70 391 L70 428 Z" class="g1"/><path d="M70 391 Q94 398 96 428 L70 428 Z" class="g2"/>' +
        '<path d="M52 410 L64 400 L70 416 L58 424 Z" class="g3"/><path d="M76 402 L88 408 L84 424 L72 420 Z" class="g4"/>' +
        '<path d="M60 396 L70 392 L80 396 L70 404 Z" class="g5"/><path d="M40 430 H100 L96 436 H44 Z" fill="#7A5A22"/></g></g>' +
        '</svg>' + line + skip;
      dur = 3400;
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
  function memo() {
    done.classList.add('memo');
    const m = (done.textContent.match(/(\d{1,2}):(\d{2})/) || [])
    const hh = +(m[1] || 20), mm = +(m[2] || 0);
    const time = (m[1] || '20') + ':' + (m[2] || '00');
    const top = document.createElement('div');
    top.className = 'mm-top';
    let ticks = '';
    for (let i = 0; i < 12; i++) ticks += '<line x1="50" y1="9" x2="50" y2="14" transform="rotate(' + i * 30 + ' 50 50)"/>';
    top.innerHTML = '<svg viewBox="0 0 100 100" class="mclock"><circle cx="50" cy="50" r="45"/>' + ticks +
      '<line x1="50" y1="50" x2="50" y2="28" class="hh" style="--to:' + ((hh % 12) * 30 + mm * 0.5 + 720) + 'deg"/>' +
      '<line x1="50" y1="50" x2="50" y2="16" class="mh" style="--to:' + (mm * 6 + 1440) + 'deg"/><circle cx="50" cy="50" r="3"/></svg>' +
      '<p class="see">' + (W.see ? W.see(time) : time) + '</p>';
    done.prepend(top);
    const stamp = document.createElement('div');
    stamp.className = 'postmark';
    const d = new Date(Date.now() + 8 * 3600e3);
    stamp.innerHTML = '<b>' + (W.stamp || '') + '</b><small>' + d.getUTCFullYear() + '.' + (d.getUTCMonth() + 1) + '.' + d.getUTCDate() + '</small>';
    done.appendChild(stamp);
    done.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
})();
