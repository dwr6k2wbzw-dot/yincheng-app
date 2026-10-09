"""編譯前調整 web/index.html：標題、載入中提示、啟動錯誤顯示在畫面上（不再是一片空白）"""
import pathlib, re

p = pathlib.Path("web/index.html")
s = p.read_text(encoding="utf-8")
s = re.sub(r"<title>.*?</title>", "<title>隱城營運</title>", s, flags=re.S)
s = re.sub(r'<div id="boot".*?</div>', "", s, flags=re.S)
s = s.replace('<body style="background:#0F1115">', "<body>")
s = re.sub(r"<script id=\"boot-js\">.*?</script>", "", s, flags=re.S)

boot = r"""<div id="boot" style="position:fixed;inset:0;z-index:-1;display:flex;align-items:center;justify-content:center;
padding:24px;text-align:center;white-space:pre-wrap;color:#9AA0AE;font:15px/1.6 -apple-system,sans-serif">載入中…</div>
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
  function show(msg) {
    var full = msg + (failed.length ? '\n\n下載失敗：\n' + failed.slice(-3).join('\n') : '');
    if (rendered) { note(full); return; }
    var b = document.getElementById('boot'); if (!b) return;
    b.style.zIndex = '9999'; b.style.background = '#0F1115'; b.style.color = '#FF5C6C';
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
s = s.replace("<body>", "<body style=\"background:#0F1115\">\n" + boot, 1)
p.write_text(s, encoding="utf-8")
print("index.html patched")
