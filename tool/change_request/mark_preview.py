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
# 連線白名單（CSP connect-src，健檢 2026-11-01，Codex 審查 PR #137）：預覽版跑的是「還沒經老闆核准」的程式、用的是真資料。
# check_patch.py 擋得住寫明的網址，擋不住用程式拼出來的；這裡讓瀏覽器本身只准連到這幾個地方
# （fetch／XHR／WebSocket／sendBeacon 都算），其他一律被瀏覽器擋下。
# 需要的：自己（version.txt）、我們的 Supabase（API＋即時連線）、Flutter 引擎與字型（gstatic）、拍照辨識（jsdelivr）。
CSP = (
    "connect-src 'self' data: blob: "
    "https://yfulcyeoqavqarpfnznw.supabase.co wss://yfulcyeoqavqarpfnznw.supabase.co "
    "https://www.gstatic.com https://fonts.gstatic.com https://fonts.googleapis.com https://cdn.jsdelivr.net"
)
s = s.replace("<head>", '<head>\n<meta http-equiv="Content-Security-Policy" content="' + CSP + '">', 1)
p.write_text(s, encoding="utf-8")
print("preview marked")
