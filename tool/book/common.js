// 訂位頁共用：Supabase 公開函式（只能看剩餘名額、訂位、用取消碼取消；0050）
window.YC = {
  url: 'https://yfulcyeoqavqarpfnznw.supabase.co',
  key: 'sb_publishable_qRkNUf71em4UTxNaUuJ4DA_iu_KyN6Y', // 公開金鑰（publishable），本來就放在網頁裡
  async rpc(fn, args) {
    const r = await fetch(this.url + '/rest/v1/rpc/' + fn, {
      method: 'POST',
      headers: { apikey: this.key, 'Content-Type': 'application/json' },
      body: JSON.stringify(args),
    });
    const body = await r.json().catch(() => null);
    if (!r.ok) throw new Error((body && body.message) || '連線失敗，請稍後再試');
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
  esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); },
};
