"""編譯前調整 web/index.html：標題、載入中提示、啟動錯誤顯示在畫面上（不再是一片空白）"""
import pathlib, re

p = pathlib.Path("web/index.html")
s = p.read_text(encoding="utf-8")
s = re.sub(r"<title>.*?</title>", "<title>隱城營運</title>", s, flags=re.S)
s = re.sub(r'<div id="boot".*?</div>', "", s, flags=re.S)
s = s.replace('<body style="background:#0F1115">', "<body>")
s = re.sub(r"<script id=\"boot-js\">.*?</script>", "", s, flags=re.S)

boot = """<div id="boot" style="position:fixed;inset:0;z-index:-1;display:flex;align-items:center;justify-content:center;
padding:24px;text-align:center;white-space:pre-wrap;color:#9AA0AE;font:15px/1.6 -apple-system,sans-serif">載入中…</div>
<script id="boot-js">
(function () {
  var t0 = Date.now();
  function box() { return document.getElementById('boot'); }
  function show(msg, color) {
    var b = box(); if (!b) return;
    b.style.zIndex = '9999'; b.style.background = '#0F1115'; b.style.color = color || '#FFB547';
    b.textContent = msg;
  }
  window.addEventListener('flutter-first-frame', function () { var b = box(); if (b) b.remove(); });
  window.addEventListener('error', function (e) {
    show('啟動失敗（請截圖給 Claude）\\n\\n' + (e.message || e.error || '未知錯誤') +
         (e.filename ? '\\n' + e.filename.split('/').pop() + ':' + e.lineno : ''), '#FF5C6C');
  });
  window.addEventListener('unhandledrejection', function (e) {
    var r = e.reason; show('啟動失敗（請截圖給 Claude）\\n\\n' + (r && (r.message || r.toString()) || '未知錯誤'), '#FF5C6C');
  });
  setTimeout(function () {
    if (box() && !document.querySelector('flutter-view, flt-glass-pane')) show('載入超過 30 秒還沒完成（請截圖給 Claude）\\n已等待 ' + Math.round((Date.now() - t0) / 1000) + ' 秒');
  }, 30000);
})();
</script>"""
s = s.replace("<body>", "<body style=\"background:#0F1115\">\n" + boot, 1)
p.write_text(s, encoding="utf-8")
print("index.html patched")
