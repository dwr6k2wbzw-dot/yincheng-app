"""部署時把店家事實寫進各店訂位頁的 HTML（2026-11-04）。

訂位頁的內容原本全靠 JavaScript 載入，搜尋引擎和 AI 只看得到「載入中」。
這裡把 stores.json 的地址、電話、營業時間、低消，
1) 先寫成頁面上看得到的資訊卡（跟 index.html 的 renderInfo() 同一套畫法，讀 stores.json 的 profile＝訂位頁資料的快照；
   載入後 JS 會用資料庫的內容蓋過去）、
2) 再寫成 schema.org 結構化資料（JSON-LD）。
兩者內容一致，客人和機器看到的是同一份事實。

用法：python3 seo.py <stores.json> <頁面.html> <slug> <中文頁網址> [en]

最後加 en（2026-11-10）：頁面是英文靜態頁 book/<店>/en/，店家事實、固定文字、結構化資料都換成英文，
讓英文搜尋和 AI 讀得到。固定文字來自 i18n.js（用 i18n_dump.js 取出），英文標題、介紹在 stores.json 的 en。
"""
import html
import os
import re
import json
import subprocess
import sys
import urllib.parse

DAYS_ZH = {'Sunday': '日', 'Monday': '一', 'Tuesday': '二', 'Wednesday': '三', 'Thursday': '四', 'Friday': '五', 'Saturday': '六'}


def day_label(days):
    known = {('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday'): '週日至週四',
             ('Friday', 'Saturday'): '週五、六', ('Saturday', 'Sunday'): '週六、日'}
    return known.get(tuple(days)) or '週' + '、'.join(DAYS_ZH[d] for d in days)


def row(key, body):
    return '<div class="irow"><span class="ik">%s</span><span>%s</span></div>' % (key, body)


def pick(m, lang):
    m = m or {}
    return m.get(lang) or m.get('zh') or ''


def txt(v):
    return html.escape(v, quote=True).replace('\n', '<br>')


def info_rows(s, t, lang):
    # 跟 index.html renderInfo() 一樣的畫法：地址、電話、低消、店家自己加的列（profile＝訂位頁資料的快照）
    p = s['profile']
    q = urllib.parse.quote('台北市' + s['addressLocality'] + s['streetAddress'])
    addr, note = '台北市' + s['addressLocality'] + s['streetAddress'], '（%s）' % s['directions']
    if (p.get('address_i18n') or {}).get(lang):
        addr, note = p['address_i18n'][lang], (p.get('directions_i18n') or {}).get(lang, '')
    rows = [
        row(t['address'], '<a href="https://www.google.com/maps/search/?api=1&amp;query=%s" target="_blank" rel="noopener">%s</a>%s'
            % (q, html.escape(addr), '<small>%s</small>' % html.escape(note) if note else '')),
        row(t['tel'], '<a href="tel:%s">%s</a>' % (s['telephone'].replace('-', ''), s['phoneDisplay'])),
    ]
    amt = '<span class="nw">%s</span>' % html.escape(t['minAmount'].replace('{n}', str(p['min_spend']))) if p.get('min_spend') else ''
    mt = pick(p.get('min_spend_text'), lang)
    if mt or amt:
        rows.append(row(t['minSpend'], txt(mt).replace('{amount}', amt) if mt else amt))
    for r in p.get('info_rows') or []:
        k, v = pick(r.get('label'), lang), pick(r.get('text'), lang)
        if k and v:
            rows.append(row(html.escape(k), txt(v)))
    return ''.join(rows)


def json_ld(slug, s, url, en=None):
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
    if en:  # 英文頁：同一家店（@id 相同），介紹、地址、低消換成英文
        data.update(description=en['description'], url=url + 'en/', servesCuisine=en['servesCuisine'],
                    priceRange=en['priceRange'], acceptsReservations=url + 'en/')
        data['address'].update(streetAddress=en['streetAddress'], addressLocality=en['addressLocality'], addressRegion='Taipei City')
    return '<script type="application/ld+json">%s</script>' % json.dumps(data, ensure_ascii=False).replace('</', '<\\/')


def main():
    stores_path, page, slug, url = sys.argv[1:5]
    en = len(sys.argv) > 5 and sys.argv[5] == 'en'
    stores = json.load(open(stores_path, encoding='utf-8'))
    s = stores[slug]
    e = s['en'] if en else None
    h = open(page, encoding='utf-8').read()
    t = json.loads(subprocess.check_output(['node', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'i18n_dump.js'), 'en' if en else 'zh']))
    if en:
        hours = '; '.join('%s %s–%s' % ({'週日至週四': 'Sun–Thu', '週五、六': 'Fri–Sat', '週六、日': 'Sat–Sun'}[day_label(x['days'])], x['opens'], x['closes']) for x in s['hours'])
        desc = '%s Address: %s. Phone %s. Hours: %s. Book online with instant confirmation.' % (
            e['description'], s['profile']['address_i18n']['en'], s['phoneDisplay'], hours)
        page_url = url + 'en/'
        # 這頁比中文頁深一層；html 標上英文，i18n.js 看到 data-lang 就用英文
        assert '<base href="../">' in h and ' lang="zh-Hant-TW">' in h
        h = h.replace('<base href="../">', '<base href="../../">', 1)
        h = h.replace(' lang="zh-Hant-TW">', ' lang="en" data-lang="en">', 1)
        # 固定文字（有 data-i18n 的）先換成英文，載入後 JS 會用同樣內容蓋過去
        h = re.sub(r'(data-i18n="(\w+)"[^>]*>)[^<]*', lambda m: m.group(1) + html.escape(t[m.group(2)]), h)
        h = re.sub(r'placeholder="[^"]*" data-i18n-ph="(\w+)"', lambda m: 'placeholder="%s" data-i18n-ph="%s"' % (html.escape(t[m.group(1)]), m.group(1)), h)
        h = re.sub(r'aria-label="[^"]*" data-i18n-aria="(\w+)"', lambda m: 'aria-label="%s" data-i18n-aria="%s"' % (html.escape(t[m.group(1)]), m.group(1)), h)
        # 分享預覽卡換成英文
        for prop, val in (('og:site_name', s['name']), ('og:title', e['title'].rsplit(' | ', 1)[0]), ('og:description', e['description']), ('og:url', page_url)):
            h, n = re.subn(r'(<meta property="%s" content=")[^"]*' % prop, lambda m: m.group(1) + html.escape(val), h, count=1)
            assert n == 1, prop
    else:
        hours = '；'.join('%s %s～%s' % (day_label(x['days']), x['opens'], x['closes']) for x in s['hours'])
        desc = '%s。地址：台北市%s%s。電話 %s。營業時間：%s。線上訂位，即時確認。' % (
            s['description'].rstrip('。'), s['addressLocality'], s['streetAddress'], s['phoneDisplay'], hours)
        page_url = url
    # 舊的 meta description 換成含事實的版本
    h = re.sub(r'<meta name="description" content="[^"]*">', '', h)
    h = h.replace('</head>', '<meta name="description" content="%s">\n%s\n</head>' % (html.escape(desc), json_ld(slug, s, url, e)), 1)
    # 正式網址（canonical），避免 ?s= 等不同網址被當成重複頁面；中英文頁互相標示（hreflang）
    h = h.replace('</head>', '<link rel="canonical" href="%s">\n'
                  '<link rel="alternate" hreflang="zh-Hant-TW" href="%s">\n<link rel="alternate" hreflang="en" href="%sen/">\n'
                  '<link rel="alternate" hreflang="x-default" href="%s">\n</head>' % (page_url, url, url, url), 1)
    # 頁尾連到另一家店：客人多一個選擇，搜尋引擎也能從一家找到另一家（2026-11-04）
    o = s['sister']
    sister_url = url.rsplit('/', 2)[0] + '/' + o['slug'] + '/' + ('en/' if en else '')
    # 老闆 2026-11-04：拿掉最下面一行說明，第一行改成「二店・訂位連結」＋往下指店名的箭頭
    arrow = ('<svg class="sa" viewBox="0 0 10 16" width="9" height="14" aria-hidden="true">'
             '<path d="M5 1v13M1 10l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.2" '
             'stroke-linecap="round" stroke-linejoin="round"/></svg>')
    label, rest, name = (e['sisterLabel'], 'Reservations', stores[o['slug']]['name']) if en else (o['label'], '訂位連結', o['name'])
    h = h.replace('</main>', '<footer class="sister"><span class="sk">%s<i>・</i>%s%s</span><a href="%s">%s</a></footer>\n</main>'
                  % (html.escape(label), rest, arrow, sister_url, html.escape(name)), 1)
    old = '<div class="card info" id="info" hidden></div>'
    assert old in h, '找不到資訊卡'
    h = h.replace(old, '<div class="card info" id="info">%s</div>' % info_rows(s, t, 'en' if en else 'zh'), 1)
    # 標題：店名直接寫在 HTML（載入後 JS 會設成同一個店名，不會閃）
    h, n = re.subn(r'<h1 id="store" data-i18n="booking">[^<]*</h1>', '<h1 id="store">%s</h1>' % html.escape(e['displayName'] if en else s['displayName']), h, count=1)
    assert n == 1, '找不到標題'
    h = re.sub(r'<title>[^<]*</title>', '<title>%s</title>' % html.escape(e['title'] if en else s['title']), h, count=1)
    open(page, 'w', encoding='utf-8').write(h)


if __name__ == '__main__':
    main()
