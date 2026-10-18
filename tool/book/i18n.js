// 訂位頁多語系（老闆 2026-10-17：客人可選中文／英文／日文；確認信照客人選的語言寄）
// 語言：網址 ?lang=en|ja|zh ＞ 上次選的（localStorage）＞ 手機語言 ＞ 中文
(function () {
  const LANGS = ['zh', 'en', 'ja'];
  let lang = new URLSearchParams(location.search).get('lang');
  if (!LANGS.includes(lang)) {
    try { lang = localStorage.getItem('yc_lang'); } catch (_) { lang = null; }
  }
  if (!LANGS.includes(lang)) {
    const n = (navigator.language || '').toLowerCase();
    lang = n.startsWith('ja') ? 'ja' : n.startsWith('zh') ? 'zh' : n ? 'en' : 'zh';
  }
  const D = {
    zh: {
      htmlLang: 'zh-Hant-TW', booking: '線上訂位', loading: '載入中…', myBooking: '我的訂位',
      date: '1. 日期', time: '2. 時間', party: '3. 人數', contact: '4. 聯絡資料',
      less: '減少', more: '增加', name: '姓名', namePh: '例如：王', titles: '稱謂', mr: '先生', ms: '小姐',
      phone: '手機', email: 'Email（確認信會寄到這裡）', note: '備註（選填）',
      submit: '確認訂位', sending: '送出中…',
      privacy: '送出即表示同意店家使用您的姓名、電話與 Email 聯繫這次訂位，不會用於其他用途。',
      paused: '目前暫停線上訂位，請直接聯絡店家。', noDays: '目前沒有可以訂的日期。',
      partyNote: (n) => '線上訂位一組最多 ' + n + ' 位；更多人數或包場請直接聯絡店家。',
      address: '地址', tel: '電話', minSpend: '低消',
      minSpendText: (amt) => '平日每人一杯飲品，國定假日前夕每人 ' + amt + ' 元',
      prevMonth: '上個月', nextMonth: '下個月', monthTitle: (y, m) => y + '年' + m + '月',
      week: ['日', '一', '二', '三', '四', '五', '六'],
      closed: '公休', full: '已滿', today: '（今日）', pickDate: '請選日期',
      dsel: (d) => (d.getMonth() + 1) + '月' + d.getDate() + '日 週' + D.zh.week[d.getDay()],
      dateLabel: (d) => (d.getMonth() + 1) + '/' + d.getDate() + '（週' + D.zh.week[d.getDay()] + '）',
      noSlots: '這天沒有開放的時段',
      altTitle: '這天還可以訂我們的另一家店', altGo: (n) => '改訂' + n,
      storeName: { yincheng: '隱城', xcw: '小城外' },
      storeIntro: { xcw: '位於大稻埕的老宅酒吧', yincheng: '位於大安區的小城外二店' },
      dayFull: '這天的訂位已滿，請選別天或直接來電。',
      dayLeft: (n) => '這天只剩 ' + n + ' 位，請調整人數或選別天。',
      largeFull: (n) => '這天 ' + n + ' 位以上的訂位已滿，請選別天或直接來電。',
      fewLeft: (n) => '這天還剩 ' + n + ' 位。',
      needDateTime: '請先選日期和時間', needTitle: '請選先生或小姐',
      booked: '訂位成功 ✓', guests: (n) => n + ' 位',
      hold: '訂位座位保留 15 分鐘，逾時未抵達將自動取消訂位，敬請見諒。',
      mailing: '正在寄確認信…',
      mailSent: (e) => '確認信已寄到 ' + e + '（沒收到請看垃圾郵件）',
      mailLate: '確認信寄送延遲，訂位已成功，請保留這個畫面。',
      manageHint: (url) => '要更改人數或取消，請點確認信裡的連結，或<a href="' + url + '">點這裡</a>（更改人數需經店家確認）。',
      status: { confirmed: '已確認', cancelled: '已取消', arrived: '已到店', no_show: '未到' }, statusLabel: '狀態：',
      pending: (n) => '已申請改為 ' + n + ' 位，等待店家確認（確認後會寄信通知您）。',
      approved: (n) => '店家已確認改為 ' + n + ' 位。',
      rejected: (req, n) => '上次申請改為 ' + req + ' 位，店家無法調整，維持 ' + n + ' 位。',
      changeParty: '更改人數', changeNote: (n) => '臨時增減人數需經店家確認；確認前仍以原本 ' + n + ' 位保留。',
      sendChange: '送出更改申請', editChange: '修改申請', withdrawn: '已撤回更改申請。',
      cancelBtn: '取消這筆訂位', cancelling: '取消中…', cancelConfirm: '確定要取消這筆訂位嗎？', cancelled: '已取消，名額已釋出。',
      badLink: '連結不完整，請從確認信重新點開', notFound: '找不到這筆訂位，請從確認信重新點開',
      netErr: '連線失敗，請稍後再試',
    },
    en: {
      htmlLang: 'en', booking: 'Reservation', loading: 'Loading…', myBooking: 'My Reservation',
      date: '1. Date', time: '2. Time', party: '3. Guests', contact: '4. Contact',
      less: 'Fewer', more: 'More', name: 'Name', namePh: 'e.g. Smith', titles: 'Title', mr: 'Mr.', ms: 'Ms.',
      phone: 'Mobile (optional)', email: 'Email (confirmation will be sent here)', note: 'Notes (optional)',
      submit: 'Confirm reservation', sending: 'Sending…',
      privacy: 'By submitting, you agree that we may use your name, phone and email only to contact you about this reservation.',
      paused: 'Online reservations are paused. Please contact us directly.', noDays: 'No dates are available right now.',
      partyNote: (n) => 'Online reservations are for up to ' + n + ' guests. For larger groups or private events, please contact us.',
      address: 'Address', tel: 'Phone', minSpend: 'Minimum',
      minSpendText: (amt) => 'Weekdays: one drink per person. Eve of national holidays: NT$' + amt + ' per person.',
      prevMonth: 'Previous month', nextMonth: 'Next month', monthTitle: (y, m) => ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][m - 1] + ' ' + y,
      week: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
      closed: 'Closed', full: 'Full', today: ' (Today)', pickDate: 'Please choose a date',
      dsel: (d) => D.en.week[d.getDay()] + ', ' + ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.getMonth()] + ' ' + d.getDate(),
      dateLabel: (d) => D.en.week[d.getDay()] + ' ' + (d.getMonth() + 1) + '/' + d.getDate(),
      noSlots: 'No times available on this day',
      altTitle: 'Our sister bar still has seats on this day', altGo: (n) => 'Book ' + n,
      storeName: { yincheng: 'Yincheng', xcw: 'Xiaochengwai' },
      storeIntro: { xcw: 'A bar in a historic old house in Dadaocheng', yincheng: 'The second Xiaochengwai location, in Da\'an District' },
      dayFull: 'This day is fully booked. Please choose another day or call us.',
      dayLeft: (n) => 'Only ' + n + ' seats left on this day. Please adjust the party size or choose another day.',
      largeFull: (n) => 'Reservations for ' + n + ' or more guests are full on this day. Please choose another day or call us.',
      fewLeft: (n) => 'Only ' + n + ' seats left on this day.',
      needDateTime: 'Please choose a date and time first', needTitle: 'Please choose Mr. or Ms.',
      booked: 'Reservation confirmed ✓', guests: (n) => n + (n === 1 ? ' guest' : ' guests'),
      hold: 'Your table will be held for 15 minutes. If you have not arrived by then, the reservation will be cancelled automatically. Thank you for your understanding.',
      mailing: 'Sending confirmation email…',
      mailSent: (e) => 'Confirmation sent to ' + e + ' (please check your spam folder if you don’t see it).',
      mailLate: 'The confirmation email is delayed, but your reservation is confirmed. Please keep this screen.',
      manageHint: (url) => 'To change the party size or cancel, use the link in the confirmation email, or <a href="' + url + '">tap here</a> (party size changes need our confirmation).',
      status: { confirmed: 'Confirmed', cancelled: 'Cancelled', arrived: 'Arrived', no_show: 'No-show' }, statusLabel: 'Status: ',
      pending: (n) => 'You asked to change to ' + n + ' guests. Waiting for our confirmation (we’ll email you).',
      approved: (n) => 'Confirmed: party size changed to ' + n + '.',
      rejected: (req, n) => 'We couldn’t change to ' + req + ' guests; your reservation stays at ' + n + '.',
      changeParty: 'Change party size', changeNote: (n) => 'Changes need our confirmation. Until then, your table stays reserved for ' + n + '.',
      sendChange: 'Send change request', editChange: 'Update request', withdrawn: 'Change request withdrawn.',
      cancelBtn: 'Cancel this reservation', cancelling: 'Cancelling…', cancelConfirm: 'Cancel this reservation?', cancelled: 'Cancelled. Thank you for letting us know.',
      badLink: 'This link is incomplete. Please open it again from the confirmation email.', notFound: 'Reservation not found. Please open the link again from the confirmation email.',
      netErr: 'Connection failed. Please try again later.',
    },
    ja: {
      htmlLang: 'ja', booking: 'オンライン予約', loading: '読み込み中…', myBooking: 'ご予約内容',
      date: '1. 日付', time: '2. 時間', party: '3. 人数', contact: '4. ご連絡先',
      less: '減らす', more: '増やす', name: 'お名前', namePh: '例：山田', titles: '敬称', mr: '男性', ms: '女性',
      phone: '携帯電話（任意）', email: 'メール（確認メールをお送りします）', note: '備考（任意）',
      submit: '予約を確定する', sending: '送信中…',
      privacy: '送信により、お名前・電話番号・メールアドレスを本予約のご連絡のみに使用することに同意したものとみなされます。',
      paused: '現在オンライン予約を停止しています。直接お店にご連絡ください。', noDays: '現在予約できる日付がありません。',
      partyNote: (n) => 'オンライン予約は1組 ' + n + ' 名様までです。それ以上の人数や貸切は直接お店にご連絡ください。',
      address: '住所', tel: '電話', minSpend: '最低消費',
      minSpendText: (amt) => '平日はお一人様1ドリンク、祝日の前日はお一人様 ' + amt + ' 元',
      prevMonth: '前の月', nextMonth: '次の月', monthTitle: (y, m) => y + '年' + m + '月',
      week: ['日', '月', '火', '水', '木', '金', '土'],
      closed: '定休日', full: '満席', today: '（今日）', pickDate: '日付を選んでください',
      dsel: (d) => (d.getMonth() + 1) + '月' + d.getDate() + '日（' + D.ja.week[d.getDay()] + '）',
      dateLabel: (d) => (d.getMonth() + 1) + '/' + d.getDate() + '（' + D.ja.week[d.getDay()] + '）',
      noSlots: 'この日は予約できる時間がありません',
      altTitle: 'この日は姉妹店にまだお席があります', altGo: (n) => n + 'を予約する',
      storeName: { yincheng: '隱城', xcw: '小城外' },
      storeIntro: { xcw: '大稻埕にある古民家バー', yincheng: '大安区にある小城外の2号店' },
      dayFull: 'この日は満席です。別の日を選ぶか、お電話ください。',
      dayLeft: (n) => 'この日は残り ' + n + ' 席です。人数を調整するか、別の日をお選びください。',
      largeFull: (n) => 'この日は ' + n + ' 名様以上のご予約が満席です。別の日を選ぶか、お電話ください。',
      fewLeft: (n) => 'この日は残り ' + n + ' 席です。',
      needDateTime: '先に日付と時間を選んでください', needTitle: '敬称を選んでください',
      booked: 'ご予約が完了しました ✓', guests: (n) => n + ' 名様',
      hold: 'お席はご予約時間から15分間お取り置きいたします。15分を過ぎてもご来店がない場合は自動的にキャンセルとなります。あらかじめご了承ください。',
      mailing: '確認メールを送信中…',
      mailSent: (e) => '確認メールを ' + e + ' に送信しました（届かない場合は迷惑メールフォルダをご確認ください）。',
      mailLate: '確認メールの送信が遅れていますが、ご予約は完了しています。この画面を保存してください。',
      manageHint: (url) => '人数の変更やキャンセルは、確認メールのリンクまたは<a href="' + url + '">こちら</a>から（人数変更はお店の確認が必要です）。',
      status: { confirmed: '予約確定', cancelled: 'キャンセル済み', arrived: 'ご来店済み', no_show: '未来店' }, statusLabel: '状態：',
      pending: (n) => n + ' 名様への変更を申請中です。お店の確認後、メールでお知らせします。',
      approved: (n) => 'お店が確認しました。' + n + ' 名様に変更されました。',
      rejected: (req, n) => req + ' 名様への変更はお受けできませんでした。' + n + ' 名様のままです。',
      changeParty: '人数の変更', changeNote: (n) => '人数の変更はお店の確認が必要です。確認までは ' + n + ' 名様でお席をお取りしています。',
      sendChange: '変更を申請する', editChange: '申請を修正する', withdrawn: '変更申請を取り消しました。',
      cancelBtn: 'この予約をキャンセル', cancelling: 'キャンセル中…', cancelConfirm: 'この予約をキャンセルしますか？', cancelled: 'キャンセルしました。',
      badLink: 'リンクが不完全です。確認メールからもう一度開いてください。', notFound: 'ご予約が見つかりません。確認メールからもう一度開いてください。',
      netErr: '接続に失敗しました。しばらくしてからもう一度お試しください。',
    },
  };
  // 資料庫回來的錯誤（中文）→ 英文／日文（對不到就附原文）
  const ERR = [
    [/這天的訂位已滿/, { en: 'This day is fully booked. Please choose another day or call us.', ja: 'この日は満席です。別の日を選ぶか、お電話ください。' }],
    [/這天只剩 (\d+) 位/, { en: (m) => 'Only ' + m[1] + ' seats left on this day. Please adjust the party size or choose another day.', ja: (m) => 'この日は残り ' + m[1] + ' 席です。人数を調整するか、別の日をお選びください。' }],
    [/(\d+) 位以上的訂位已滿/, { en: (m) => 'Reservations for ' + m[1] + ' or more guests are full on this day.', ja: (m) => 'この日は ' + m[1] + ' 名様以上のご予約が満席です。' }],
    [/電話有未到紀錄/, { en: 'Online reservations are unavailable for this phone number. Please call us.', ja: 'この電話番号ではオンライン予約できません。お電話ください。' }],
    [/正確的電話/, { en: 'Please enter a valid phone number.', ja: '正しい電話番号を入力してください。' }],
    [/正確的 Email/, { en: 'Please enter a valid email address.', ja: '正しいメールアドレスを入力してください。' }],
    [/請填寫姓名/, { en: 'Please enter your name (up to 40 characters).', ja: 'お名前を入力してください（40文字以内）。' }],
    [/備註請在/, { en: 'Notes must be 200 characters or fewer.', ja: '備考は200文字以内でご入力ください。' }],
    [/已有 2 筆訂位/, { en: 'This phone or email already has 2 reservations. Please cancel one first or call us.', ja: 'この電話番号またはメールですでに2件のご予約があります。先にキャンセルするか、お電話ください。' }],
    [/時段不開放|請選擇日期與時段/, { en: 'This time is not available. Please choose another.', ja: 'この時間は予約できません。別の時間をお選びください。' }],
    [/以後不接受當天訂位/, { en: 'Same-day online reservations are closed. Please call us.', ja: '本日分のオンライン予約は締め切りました。お電話ください。' }],
    [/只能訂 (\d+) 天內/, { en: (m) => 'Reservations can be made up to ' + m[1] + ' days ahead.', ja: (m) => 'ご予約は ' + m[1] + ' 日先まで可能です。' }],
    [/一組最多 (\d+) 位/, { en: (m) => 'Online reservations are for up to ' + m[1] + ' guests. Please call us for larger groups.', ja: (m) => 'オンライン予約は1組 ' + m[1] + ' 名様までです。それ以上はお電話ください。' }],
    [/這天不開放線上訂位/, { en: 'Online reservations are not available on this day.', ja: 'この日はオンライン予約を受け付けていません。' }],
    [/暫停線上訂位/, { en: D.en.paused, ja: D.ja.paused }],
    [/訂位的人很多/, { en: 'We are busy right now. Please try again shortly or call us.', ja: 'ただいま混み合っています。しばらくしてからお試しいただくか、お電話ください。' }],
    [/找不到可以取消的訂位/, { en: 'This reservation can no longer be cancelled (already cancelled or past).', ja: 'このご予約はキャンセルできません（キャンセル済みまたは過去の日付）。' }],
    [/不能更改/, { en: 'This reservation can no longer be changed.', ja: 'このご予約は変更できません。' }],
    [/更改次數太多/, { en: 'Too many change requests. Please call us.', ja: '変更の申請回数が上限に達しました。お電話ください。' }],
    [/人數請選|人數和目前一樣/, { en: 'Please choose a different number of guests (1–30).', ja: '別の人数（1〜30名）をお選びください。' }],
    [/連線失敗/, { en: D.en.netErr, ja: D.ja.netErr }],
  ];
  window.YCI = {
    lang, langs: LANGS,
    t(key, ...a) { const v = D[lang][key] ?? D.zh[key]; return typeof v === 'function' ? v(...a) : v; },
    err(msg) {
      if (lang === 'zh' || !msg) return msg;
      for (const [re, tr] of ERR) {
        const m = String(msg).match(re);
        if (m) { const v = tr[lang]; return typeof v === 'function' ? v(m) : v; }
      }
      return (lang === 'ja' ? 'エラー：' : 'Error: ') + msg;
    },
    set(l) {
      try { localStorage.setItem('yc_lang', l); } catch (_) {}
      const u = new URL(location.href); u.searchParams.set('lang', l); location.replace(u.toString());
    },
    // 顯示姓名：資料庫存「王 先生／小姐」；英文顯示 Mr./Ms. 王、日文顯示 王 様
    name(n) {
      const m = String(n || '').match(/^(.*?)\s*(先生|小姐)$/);
      if (!m || lang === 'zh') return n;
      return lang === 'en' ? (m[2] === '先生' ? 'Mr. ' : 'Ms. ') + m[1] : m[1] + ' 様';
    },
    // 語言切換列（放在頁面最上方）
    switcher() {
      const names = { zh: '中文', en: 'English', ja: '日本語' };
      return '<nav class="langs" aria-label="Language">' + LANGS.map(l =>
        '<button type="button" data-lang="' + l + '"' + (l === lang ? ' class="on" aria-current="true"' : '') + '>' + names[l] + '</button>').join('') + '</nav>';
    },
    mountSwitcher() {
      const box = document.createElement('div');
      box.innerHTML = this.switcher();
      const nav = box.firstChild;
      nav.onclick = (e) => { const b = e.target.closest('button[data-lang]'); if (b && b.dataset.lang !== lang) YCI.set(b.dataset.lang); };
      document.body.prepend(nav);
    },
    // 有 data-i18n 的元素換成目前語言
    apply(root) {
      document.documentElement.lang = this.t('htmlLang');
      (root || document).querySelectorAll('[data-i18n]').forEach(el => { el.textContent = this.t(el.dataset.i18n); });
      (root || document).querySelectorAll('[data-i18n-ph]').forEach(el => { el.placeholder = this.t(el.dataset.i18nPh); });
      (root || document).querySelectorAll('[data-i18n-aria]').forEach(el => { el.setAttribute('aria-label', this.t(el.dataset.i18nAria)); });
    },
  };
  // 日期格式、星期照語言
  if (window.YC) {
    YC.week = D[lang].week;
    YC.dateLabel = (iso) => D[lang].dateLabel(new Date(iso + 'T00:00:00'));
  }
})();
