"""部署時把 Google Analytics 4 放進訂位頁（官網執行計畫 B5，2026-11-24）。

- 評估 ID（G- 開頭）來自 GitHub repo 變數 BOOKING_GA4_ID；沒填就只拿掉 <!--GA--> 記號，訂位頁不載入 Google 的程式、什麼都不送。
  格式不對也不載入，部署記錄會出現警告（不擋部署）。
- 只放訂位頁（index.html，各店專屬網址也是從它產生），不放取消頁：取消頁網址帶取消碼，不能送到 Google。
- 跨網域：官網 barcitynorth.com 和訂位頁用同一個 GA4 資料串流（「官網」）。linker 讓從官網點訂位按鈕過來的客人
  算同一個人、同一次造訪（官網的連結會帶 _gl）；GA4 後台「設定網域」也加了這兩個網域，兩邊一致。
- 訂位成功時送 booking_complete，只帶人數（index.html 送出成功的地方）；其他訂位內容和個人資料都不送。

用法：python3 ga.py <評估 ID，可以是空的> <訂位頁網址> <頁面.html>
"""
import json
import re
import sys
import urllib.parse

ga_id, site, page = sys.argv[1].strip(), sys.argv[2], sys.argv[3]
h = open(page, encoding='utf-8').read()
assert h.count('<!--GA-->') == 1, page
tag = ''
if ga_id and not re.fullmatch(r'G-[A-Z0-9]{4,20}', ga_id):
    print('::warning title=GA4::BOOKING_GA4_ID 格式不對（要 G- 開頭、大寫），訂位頁先不載入 GA4')
elif ga_id:
    # 官網的網域＋訂位頁的網域
    config = {'linker': {'domains': ['barcitynorth.com', urllib.parse.urlparse(site).hostname]}}
    tag = ('<script async src="https://www.googletagmanager.com/gtag/js?id=%s"></script>'
           '<script>window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}'
           "gtag('js',new Date());gtag('config',%s,%s);</script>") % (ga_id, json.dumps(ga_id), json.dumps(config))
    print('GA4：' + ga_id)
open(page, 'w', encoding='utf-8').write(h.replace('<!--GA-->', tag))
