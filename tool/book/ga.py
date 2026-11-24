"""部署時把 Google Analytics 4 放進訂位頁（官網執行計畫 B5，2026-11-24）。

- 評估 ID（G- 開頭）來自 GitHub repo 變數 BOOKING_GA4_ID；沒填就只拿掉 <!--GA--> 記號，訂位頁不載入 Google 的程式、什麼都不送。
  格式不對也不載入，部署記錄會出現警告（不擋部署）。
- 只放訂位頁（index.html，各店專屬網址也是從它產生），不放取消頁：取消頁網址帶取消碼，不能送到 Google。
- 跨網域：官網 barcitynorth.com 和訂位頁用同一個 GA4 資料串流（「官網」）。linker 讓從官網點訂位按鈕過來的客人
  算同一個人、同一次造訪（官網的連結會帶 _gl）；GA4 後台「設定網域」也加了這兩個網域，兩邊一致。
- 訂位成功時送 booking_complete，只帶人數（index.html 送出成功的地方）；其他訂位內容和個人資料都不送。
- 網址清理（程式審查 2026-11-24）：GA4 預設會把整個網址和來源網址送出去。訂位頁網址可能帶日期、人數（?d=、?p=），
  從取消頁回來時來源網址帶取消碼，所以 page_location 只留 KEEP 裡的參數和 utm_ 開頭的；
  來源網址同網站的也照樣清理，別的網站只留網域。

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
    # 店別、語言、來源、廣告點擊編號
    keep = ['s', 'lang', 'ref', 'gclid']
    tag = ('<script async src="https://www.googletagmanager.com/gtag/js?id=%s"></script>'
           '<script>window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}'
           "gtag('js',new Date());(function(c,k){"
           'function clean(h){var u=new URL(h),o=new URL(u.origin+u.pathname);'
           'u.searchParams.forEach(function(v,n){if(k.indexOf(n)!==-1||/^utm_/.test(n))o.searchParams.append(n,v);});return o.href;}'
           'c.page_location=clean(location.href);'
           'try{var r=new URL(document.referrer);c.page_referrer=r.origin===location.origin?clean(r.href):r.origin+"/";}catch(e){}'
           "gtag('config',%s,c);})(%s,%s);</script>") % (ga_id, json.dumps(ga_id), json.dumps(config), json.dumps(keep))
    print('GA4：' + ga_id)
open(page, 'w', encoding='utf-8').write(h.replace('<!--GA-->', tag))
