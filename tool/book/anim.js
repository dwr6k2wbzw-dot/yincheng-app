// 訂位頁動畫（老闆 2026-10-18：「訂位介面可以做成有趣的動畫嗎」）——電影院主題
//   1. 開場倒數：第一次打開（同一個分頁只放一次）放 3・2・1 電影片頭倒數，點一下可跳過
//   2. 封面：背景照片慢慢推近、放映機光束掃過、底片顆粒；店名像對焦一樣清楚起來
//   3. 卡片：往下滑時一張張浮上來；選日期、時段會輕輕彈一下
//   4. 訂位成功：變成一張電影票，蓋上「已訂位」章，爆米花噴出來
// 手機設定「減少動態效果」時全部不動；網址加 ?anim=0 也可以關掉。
(function () {
  const q = new URLSearchParams(location.search);
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduce || q.get('anim') === '0') return;
  const lang = (window.YCI && YCI.lang) || 'zh';
  const W = {
    zh: { skip: '點一下跳過', stamp: '已訂位', admit: '入場券', seat: '座位保留中' },
    en: { skip: 'Tap to skip', stamp: 'RESERVED', admit: 'ADMIT', seat: 'Your table is waiting' },
    ja: { skip: 'タップでスキップ', stamp: '予約済', admit: '入場券', seat: 'お席をご用意します' },
  }[lang] || {};
  document.documentElement.classList.add('anim');

  // ---------- 1. 開場倒數 ----------
  let seen = false;
  try { seen = sessionStorage.getItem('yc_intro') === '1'; sessionStorage.setItem('yc_intro', '1'); } catch (_) { seen = true; }
  if (!seen && q.get('intro') !== '0') {
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
    const beam = document.createElement('div'); beam.className = 'beam';
    const grain = document.createElement('div'); grain.className = 'grain';
    head.prepend(bg, beam, grain);
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
      if (done.hidden || done.classList.contains('ticket') || !done.querySelector('.big')) return;
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
})();
