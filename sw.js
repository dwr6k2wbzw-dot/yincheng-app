// 把 App 存在手機裡（老闆 2026-10-16：打開太慢）
// - 不會變的大檔案（帶版本號的主程式、Google 的畫圖引擎、中文字型）：存一次，之後直接從手機讀
// - 網頁本身、其他小檔案：先上網拿最新的，拿不到（沒網路或超過 4 秒）才用手機裡存的
// - 資料庫（Supabase）、客人訂位頁、版本檢查：完全不經過這裡
// 部署時 5b43e48c 會換成這次的版本號；換版時舊版本號的檔案會自動清掉。
const V = '5b43e48c';
const APP = 'yc-app';
const STATIC = 'yc-static-1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try {
      const c = await caches.open(APP);
      for (const req of await c.keys()) {
        const v = new URL(req.url).searchParams.get('v');
        if (v && v !== V) await c.delete(req); // 舊版的主程式
      }
      for (const k of await caches.keys()) {
        if (k !== APP && k !== STATIC) await caches.delete(k);
      }
    } catch (e) {}
    await self.clients.claim();
  })());
});

function isStatic(url) {
  return (url.origin === 'https://www.gstatic.com' && url.pathname.startsWith('/flutter-canvaskit/')) ||
    url.origin === 'https://fonts.gstatic.com';
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (isStatic(url)) { event.respondWith(cacheFirst(req, STATIC)); return; }
  if (url.origin !== self.location.origin) return; // 資料庫等其他網站
  const base = new URL(self.registration.scope).pathname;
  if (!url.pathname.startsWith(base)) return;
  const rest = url.pathname.slice(base.length);
  // preview/：功能許願的預覽版，不經過正式版的暫存
  if (rest.startsWith('book/') || rest.startsWith('invite/') || rest.startsWith('preview/') || rest === 'version.txt' || rest === 'sw.js') return;
  if (url.searchParams.get('v') === V) { event.respondWith(cacheFirst(req, APP)); return; }
  event.respondWith(networkFirst(req));
});

async function cacheFirst(req, name) {
  const c = await caches.open(name);
  const hit = await c.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok || res.type === 'opaque') { try { await c.put(req, res.clone()); } catch (e) {} }
  return res;
}

async function networkFirst(req) {
  const c = await caches.open(APP);
  const key = req.mode === 'navigate' ? new URL(self.registration.scope).href : req;
  const net = fetch(req).then(async (res) => {
    if (res.ok) { try { await c.put(key, res.clone()); } catch (e) {} }
    return res;
  });
  const cached = await c.match(key);
  if (!cached) return net;
  // 有存過：網路 4 秒內回來就用新的，否則先用存的
  const timeout = new Promise((resolve) => setTimeout(() => resolve(null), 4000));
  try {
    const res = await Promise.race([net, timeout]);
    return res || cached;
  } catch (e) {
    return cached;
  }
}
