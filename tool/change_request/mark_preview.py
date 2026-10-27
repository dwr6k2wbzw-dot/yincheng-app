"""預覽版的 index.html：加上「預覽版」標示、不註冊離線暫存（sw.js）。
用法：python3 mark_preview.py build/web/index.html
"""
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
# 不註冊離線暫存：預覽版放在 preview/<代號>/，不要和正式版的暫存混在一起
s = s.replace("if ('serviceWorker' in navigator && location.protocol === 'https:')", "if (false)")
banner = (
    '<div id="yc-preview" style="position:fixed;left:50%;transform:translateX(-50%);bottom:84px;z-index:9998;'
    'pointer-events:none;padding:4px 12px;border-radius:12px;background:rgba(255,181,71,.92);color:#111;'
    'font:12px/1.4 -apple-system,sans-serif">預覽版・資料是真的，請小心操作</div>'
)
s = s.replace("</body>", banner + "\n</body>", 1)
p.write_text(s, encoding="utf-8")
print("preview marked")
