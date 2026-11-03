"""部署時把店家事實寫進各店訂位頁的 HTML（2026-11-04）。

訂位頁的內容原本全靠 JavaScript 載入，搜尋引擎和 AI 只看得到「載入中」。
這裡把 stores.json 的地址、電話、營業時間、低消，
1) 先寫成頁面上看得到的資訊卡（跟 index.html 的 renderInfo() 中文版一樣，載入後 JS 會用同樣內容蓋過去）、
2) 再寫成 schema.org 結構化資料（JSON-LD）。
兩者內容一致，客人和機器看到的是同一份事實。

用法：python3 seo.py <stores.json> <頁面.html> <slug> <頁面網址>
"""
import html
import re
import json
import sys
import urllib.parse

DAYS_ZH = {'Sunday': '日', 'Monday': '一', 'Tuesday': '二', 'Wednesday': '三', 'Thursday': '四', 'Friday': '五', 'Saturday': '六'}


def day_label(days):
    known = {('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'): '週日至週四',
             ('Friday', 'Saturday'): '週五、六', ('Saturday', 'Sunday'): '週六、日'}
    return known.get(tuple(days)) or '週' + '、'.join(DAYS_ZH[d] for d in days)


def row(key, body):
    return '<div class="irow"><span class="ik">%s</span><span>%s</span></div>' % (key, body)


def info_rows(slug, s):
    # 跟 index.html renderInfo()、i18n.js 中文字串一致；改那邊時這裡也要改
    addr = '台北市' + s['addressLocality'] + s['streetAddress']
    q = urllib.parse.quote(addr)
    rows = [
        row('地址', '<a href="https://www.google.com/maps/search/?api=1&amp;query=%s" target="_blank" rel="noopener">%s</a><small>（%s）</small>'
            % (q, html.escape(addr), html.escape(s['directions']))),
        row('電話', '<a href="tel:%s">%s</a>' % (s['telephone'].replace('-', ''), s['phoneDisplay'])),
        row('低消', '每人一杯飲品%s%s<span class="nw">每人 %d 元</span><br>（無限時）' % ('<br>' if s['minSpendWhen'].startswith('週') else '，', s['minSpendWhen'], s['minSpend'])),
    ]
    if slug == 'xcw':
        rows.append(row('咖啡', '咖啡與咖啡調酒時段營業時間：每週六、日 13:00～17:30<br>無開放預約'))
        rows.append(row('酒吧', '經典酒吧時段營業時間：18:00～24:00（週末～01:00）<br>無公休日'))
    if slug == 'yincheng':
        rows.append(row('營業時間', '週日至週四 18:00～01:00<br>週五、六 19:00～02:00（無公休日）'))
    return ''.join(rows)


def json_ld(slug, s, url):
    data = {
        '@context': 'https://schema.org',
        '@type': 'BarOrPub',
        '@id': url + '#store',
        'name': s['name'],
        'alternateName': s['alternateName'],
        'description': s['description'],
        'url': url,
        'image': url.rsplit('/', 2)[0] + '/og-%s.jpg' % slug,
        'telephone': s['telephone'],
        'address': {
            '@type': 'PostalAddress',
            'streetAddress': s['streetAddress'],
            'addressLocality': s['addressLocality'],
            'addressRegion': '台北市',
            'postalCode': s['postalCode'],
            'addressCountry': 'TW',
        },
        'openingHoursSpecification': [
            {'@type': 'OpeningHoursSpecification', 'dayOfWeek': h['days'], 'opens': h['opens'], 'closes': h['closes']}
            for h in s['hours']
        ],
        'servesCuisine': s['servesCuisine'],
        'priceRange': '低消每人一杯飲品；%s每人 NT$%d' % (s['minSpendWhen'], s['minSpend']),
        'acceptsReservations': url,
        'brand': {'@type': 'Brand', 'name': '小城外 CityNorth'},
        'sameAs': s['sameAs'],
    }
    if s.get('foundingDate'):
        data['foundingDate'] = s['foundingDate']
    return '<script type="application/ld+json">%s</script>' % json.dumps(data, ensure_ascii=False).replace('</', '<\\/')


def main():
    stores_path, page, slug, url = sys.argv[1:5]
    s = json.load(open(stores_path, encoding='utf-8'))[slug]
    h = open(page, encoding='utf-8').read()
    hours = '；'.join('%s %s～%s' % (day_label(x['days']), x['opens'], x['closes']) for x in s['hours'])
    desc = '%s。地址：台北市%s%s。電話 %s。營業時間：%s。線上訂位，即時確認。' % (
        s['description'].rstrip('。'), s['addressLocality'], s['streetAddress'], s['phoneDisplay'], hours)
    # 舊的 meta description 換成含事實的版本
    h = re.sub(r'<meta name="description" content="[^"]*">', '', h)
    h = h.replace('</head>', '<meta name="description" content="%s">\n%s\n</head>' % (html.escape(desc), json_ld(slug, s, url)), 1)
    # 正式網址（canonical），避免 ?s= 等不同網址被當成重複頁面
    h = h.replace('</head>', '<link rel="canonical" href="%s">\n</head>' % url, 1)
    # 頁尾連到另一家店：客人多一個選擇，搜尋引擎也能從一家找到另一家（2026-11-04）
    o = s['sister']
    sister_url = url.rsplit('/', 2)[0] + '/' + o['slug'] + '/'
    h = h.replace('</main>', '<footer class="sister"><span class="sk">%s</span><a href="%s">%s<small>%s</small></a></footer>\n</main>'
                  % (html.escape(o['label']), sister_url, html.escape(o['name']), html.escape(o['where'])), 1)
    old = '<div class="card info" id="info" hidden></div>'
    assert old in h, '找不到資訊卡'
    h = h.replace(old, '<div class="card info" id="info">%s</div>' % info_rows(slug, s), 1)
    # 標題：店名直接寫在 HTML（載入後 JS 會設成同一個店名，不會閃）
    h = h.replace('<h1 id="store" data-i18n="booking">線上訂位</h1>', '<h1 id="store">%s</h1>' % html.escape(s['displayName']), 1)
    h = re.sub(r'<title>[^<]*</title>', '<title>%s</title>' % html.escape(s['title']), h, count=1)
    open(page, 'w', encoding='utf-8').write(h)


if __name__ == '__main__':
    main()
