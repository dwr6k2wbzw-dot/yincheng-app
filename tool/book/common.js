// 訂位頁共用：Supabase 公開函式（只能看剩餘名額、訂位、用取消碼取消；0050）
window.YC = {
  url: 'https://yfulcyeoqavqarpfnznw.supabase.co',
  key: 'sb_publishable_qRkNUf71em4UTxNaUuJ4DA_iu_KyN6Y', // 公開金鑰（publishable），本來就放在網頁裡
  async rpc(fn, args) {
    let r;
    try {
      r = await fetch(this.url + '/rest/v1/rpc/' + fn, {
        method: 'POST',
        headers: { apikey: this.key, 'Content-Type': 'application/json' },
        body: JSON.stringify(args),
      });
    } catch (_) {
      // 手機斷線、訊號不好：瀏覽器丟的是英文訊息，換成看得懂的
      throw new Error('連線失敗，請稍後再試');
    }
    const body = await r.json().catch(() => null);
    if (!r.ok) {
      const e = new Error((body && body.message) || '連線失敗，請稍後再試');
      e.code = body && body.code;
      throw e;
    }
    return body;
  },
  // 寄確認信／取消信（失敗不影響訂位本身）
  async mail(token, kind) {
    try {
      const r = await fetch(this.url + '/functions/v1/reservation-email', {
        method: 'POST',
        headers: { apikey: this.key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, kind }),
      });
      return r.ok;
    } catch (e) { return false; }
  },
  week: ['日', '一', '二', '三', '四', '五', '六'],
  dateLabel(iso) {
    const d = new Date(iso + 'T00:00:00');
    return (d.getMonth() + 1) + '/' + d.getDate() + '（週' + this.week[d.getDay()] + '）';
  },
  // 訂位頁內建的圖（logo、封面照，例 logo-xcw.png）加上這一版的版本號（部署時寫在 YC_V），網頁一換新手機就不會用到舊圖；
  // 老闆自己上傳的圖（ops 0145：{店的 id}/logo-xxxx.png）放在公開檔案區 booking-assets，換成那裡的網址
  // （每次換圖都是新檔名，不用版本號）；其他網址原樣不動（Codex 審查）
  asset(f) {
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/(logo|hero)-[a-z0-9]{6,40}\.(png|jpe?g|webp)$/.test(f)) {
      return this.url + '/storage/v1/object/public/booking-assets/' + f;
    }
    return f + (window.YC_V && /^[a-z0-9][a-z0-9-]*\.(png|jpe?g|webp)$/.test(f) ? '?v=' + window.YC_V : '');
  },
  esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); },
};
