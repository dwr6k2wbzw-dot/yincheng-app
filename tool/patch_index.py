"""編譯前調整 web/index.html：標題、載入中提示、啟動錯誤顯示在畫面上（不再是一片空白）"""
import pathlib, re

p = pathlib.Path("web/index.html")
s = p.read_text(encoding="utf-8")
s = re.sub(r"<title>.*?</title>", "<title>小城外</title>", s, flags=re.S)
# iPhone「加入主畫面」用的圖示（180×180）
s = re.sub(r'<link rel="apple-touch-icon"[^>]*>', '<link rel="apple-touch-icon" sizes="180x180" href="icons/xcw-touch-180-v2.png">', s)
# 網頁小圖示：換檔名避免 Safari 用舊的暫存
s = re.sub(r'<link rel="icon"[^>]*>', '<link rel="icon" type="image/png" href="icons/xcw-favicon-v2.png"/>', s)
# iPhone「加入主畫面」顯示的名稱
s = re.sub(r'<meta name="apple-mobile-web-app-title"[^>]*>', '<meta name="apple-mobile-web-app-title" content="小城外">', s)
if 'apple-mobile-web-app-title' not in s:
    s = s.replace("</head>", '  <meta name="apple-mobile-web-app-title" content="小城外">\n</head>', 1)
s = re.sub(r'<div id="boot".*?</div>', "", s, flags=re.S)
s = s.replace('<body style="background:#0F1115">', "<body>")
s = re.sub(r"<script id=\"boot-js\">.*?</script>", "", s, flags=re.S)

# 載入速度記錄（⋯ → 載入速度）：各階段完成時間＋最慢的檔案
timing = r"""<script id="yc-timing">
window.ycMarks = [];
window.ycMark = function (name) {
  for (var i = 0; i < window.ycMarks.length; i++) if (window.ycMarks[i][0] === name) return;
  window.ycMarks.push([name, performance.now()]);
};
window.addEventListener('flutter-first-frame', function () { window.ycMark('第一個畫面'); });
window.ycLoadReport = function () {
  var s = function (ms) { return (Math.round(ms / 100) / 10) + ' 秒'; };
  var out = ['打開後經過的時間：'];
  window.ycMarks.forEach(function (m) { out.push('・' + m[0] + '：' + s(m[1])); });
  try {
    var nav = performance.getEntriesByType('navigation')[0];
    if (nav) out.splice(1, 0, '・網頁本身：' + s(nav.responseEnd));
    var list = performance.getEntriesByType('resource').filter(function (r) { return r.duration > 150; })
      .sort(function (a, b) { return b.duration - a.duration; }).slice(0, 8).map(function (r) {
        var n = r.name.split('?')[0].split('/').slice(-2).join('/');
        return '・' + n + '  ' + s(r.duration) + '  ' + (r.transferSize ? Math.round(r.transferSize / 1024) + 'KB' : '快取');
      });
    if (list.length) { out.push(''); out.push('最慢的檔案／查詢：'); out = out.concat(list); }
  } catch (e) {}
  out.push('');
  out.push('網路：' + ((navigator.connection && navigator.connection.effectiveType) || '不明'));
  return out.join('\n');
};
</script>"""
s = re.sub(r'<script id="yc-timing">.*?</script>', "", s, flags=re.S)
s = s.replace("</head>", timing + "\n</head>", 1)

boot = r"""<div id="boot" style="position:fixed;inset:0;z-index:-1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:22px;
padding:24px;text-align:center;white-space:pre-wrap;color:#D3B16E;background:#0A0A09;font:13px/1.6 -apple-system,sans-serif;letter-spacing:.3em">
<div style="display:flex;align-items:flex-end;gap:26px"><img src="assets/assets/logos/yincheng.png" alt="" style="height:84px">
<img src="assets/assets/logos/xcw.png" alt="" style="height:68px"></div><div>載入中</div></div>
<script id="boot-js">
(function () {
  var t0 = Date.now(), rendered = false, failed = [];
  // 記錄下載失敗的網址（只記路徑，不含查詢參數），方便回報
  var origFetch = window.fetch;
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    return origFetch.apply(this, arguments).catch(function (e) {
      failed.push(String(url).split('?')[0]); throw e;
    });
  };
  function note(msg) {
    // App 已經畫出畫面：只在底部顯示一行小提示，不擋住操作
    var n = document.getElementById('boot-note');
    if (!n) {
      n = document.createElement('div'); n.id = 'boot-note';
      n.style.cssText = 'position:fixed;left:8px;right:8px;bottom:8px;z-index:9999;padding:8px 12px;border-radius:8px;' +
        'background:#232733;color:#FFB547;font:12px/1.5 -apple-system,sans-serif;white-space:pre-wrap';
      n.onclick = function () { n.remove(); };
      document.body.appendChild(n);
    }
    n.textContent = msg + '（點一下關閉）';
  }
  function res() {
    // 各檔案下載時間與大小（最慢的 6 個），判斷是網路慢還是檔案壞掉
    try {
      var list = performance.getEntriesByType('resource').map(function (r) {
        return r.name.split('?')[0].split('/').slice(-2).join('/') + '  ' + Math.round(r.duration / 100) / 10 + 's  ' +
          (r.transferSize ? Math.round(r.transferSize / 1024) + 'KB' : (r.responseEnd ? '快取' : '未完成'));
      });
      return '\n\n進度：' + (window.ycStage || 'Dart 尚未啟動') + '\n檔案：\n' + list.slice(-8).join('\n');
    } catch (e) { return ''; }
  }
  function show(msg) {
    var full = msg + (failed.length ? '\n\n下載失敗：\n' + failed.slice(-3).join('\n') : '') + res();
    if (rendered) { note(full); return; }
    var b = document.getElementById('boot'); if (!b) return;
    b.style.zIndex = '9999'; b.style.background = '#0A0A09'; b.style.color = '#FF5C6C'; b.style.letterSpacing = '0'; b.style.fontSize = '12px'; b.style.textAlign = 'left';
    b.textContent = '啟動失敗（請截圖給 Claude）\n\n' + full + '\n\n已等待 ' + Math.round((Date.now() - t0) / 1000) + ' 秒';
  }
  window.addEventListener('flutter-first-frame', function () {
    rendered = true; var b = document.getElementById('boot'); if (b) b.remove();
  });
  window.addEventListener('error', function (e) {
    show((e.message || e.error || '未知錯誤') + (e.filename ? '\n' + e.filename.split('/').pop() + ':' + e.lineno : ''));
  });
  window.addEventListener('unhandledrejection', function (e) {
    var r = e.reason; show(r && (r.message || r.toString()) || '未知錯誤');
  });
  setTimeout(function () {
    if (!rendered && !document.querySelector('flutter-view, flt-glass-pane')) show('載入超過 30 秒還沒完成');
  }, 30000);
})();
</script>"""
s = s.replace("<body>", "<body style=\"background:#0A0A09\">\n" + boot, 1)

# 把 App 存在手機裡（tool/sw.js，部署時複製並換上版本號；老闆 2026-10-16）
s = re.sub(r'<script id="yc-sw">.*?</script>', "", s, flags=re.S)
sw = r"""<script id="yc-sw">
if ('serviceWorker' in navigator && location.protocol === 'https:') {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js', { updateViaCache: 'none' }).catch(function () {});
  });
}
</script>"""
s = s.replace("</head>", sw + "\n</head>", 1)

# 拍照辨識送貨單（免費文字辨識 Tesseract.js，在手機上執行；辨識程式與語言資料第一次使用時才下載）
s = re.sub(r'<script id="yc-scan">.*?</script>', "", s, flags=re.S)
scan = r"""<script id="yc-scan">
window.ycPickImage = function (fromLibrary) {
  return new Promise(function (resolve, reject) {
    var input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    // fromLibrary：直接開相簿（班表照片，老闆 2026-10-12）；否則直接開相機（送貨單、交接）
    if (!fromLibrary) input.setAttribute('capture', 'environment');
    input.style.display = 'none';
    document.body.appendChild(input);
    var finished = false;
    function finish(v) { if (!finished) { finished = true; input.remove(); resolve(v); } }
    input.addEventListener('cancel', function () { finish(null); });
    input.addEventListener('change', function () {
      var f = input.files && input.files[0];
      if (!f) { finish(null); return; }
      var url = URL.createObjectURL(f);
      var img = new Image();
      img.onload = function () {
        try {
          var max = 2000, k = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
          var c = document.createElement('canvas');
          c.width = Math.round(img.naturalWidth * k); c.height = Math.round(img.naturalHeight * k);
          c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
          URL.revokeObjectURL(url);
          finish(c.toDataURL('image/jpeg', 0.85));
        } catch (e) { finished = true; reject(e); }
      };
      img.onerror = function () { finished = true; reject(new Error('照片讀取失敗')); };
      img.src = url;
    });
    input.click();
  });
};
// App 新版本檢查（小鈴鐺）：deploy.yml 會寫入 window.ycBuild 與 version.txt，兩者不同就代表有新版
window.ycCheckUpdate = async function () {
  try {
    if (!window.ycBuild) return false;
    var r = await fetch('version.txt?t=' + Date.now(), { cache: 'no-store' });
    if (!r.ok) return false;
    var v = (await r.text()).trim();
    return /^[0-9a-f]{6,40}$/.test(v) && v !== window.ycBuild;
  } catch (e) { return false; }
};
window.ycReload = function () {
  location.replace(location.pathname + '?u=' + Date.now() + location.hash);
};
// 存檔（損益表）：手機用分享選單（可選「儲存到檔案」），不支援就直接下載
window.ycSaveFile = async function (bytes, name, mime) {
  var file = new File([bytes], name, { type: mime });
  if (navigator.canShare && navigator.share) {
    try {
      if (navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file], title: name });
        return 'shared';
      }
    } catch (e) {
      if (e && e.name === 'AbortError') return 'cancel';
    }
  }
  var url = URL.createObjectURL(file);
  var a = document.createElement('a');
  a.href = url; a.download = name; a.style.display = 'none';
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(function () { URL.revokeObjectURL(url); }, 30000);
  return 'downloaded';
};
window.ycOcr = async function (dataUrl) {
  if (!window.Tesseract) {
    await new Promise(function (ok, bad) {
      var sc = document.createElement('script');
      sc.src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';
      sc.onload = ok;
      sc.onerror = function () { bad(new Error('辨識程式下載失敗，請檢查網路')); };
      document.head.appendChild(sc);
    });
  }
  var worker = await Tesseract.createWorker(['chi_tra', 'eng']);
  try {
    var r = await worker.recognize(dataUrl);
    return r.data.text || '';
  } finally {
    await worker.terminate();
  }
};
</script>"""
s = s.replace("</body>", scan + "\n</body>", 1)

p.write_text(s, encoding="utf-8")
print("index.html patched")
