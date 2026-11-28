/// 每家店自己選哪些通知要發到 LINE 群組（ops 0162，公版；只有老闆能改）。
/// 小鈴鐺照舊全部都有；這裡只決定哪些「也」發到這家店綁的 LINE 群組。
/// 功能許願、許願單只有老闆、店長看得到，群組裡有兼職，所以不提供。
class LineNotifyEvent {
  const LineNotifyEvent(this.key, this.group, this.label, this.detail);
  final String key; // 跟資料庫 store_settings.line_notify_events 一樣
  final String group; // 畫面分組
  final String label;
  final String detail;
}

const lineNotifyEvents = <LineNotifyEvent>[
  LineNotifyEvent('handover_important', '交接・提醒', '重要交接', '勾了「重要」的交接'),
  LineNotifyEvent('handover', '交接・提醒', '一般交接', '沒勾「重要」的交接也發'),
  LineNotifyEvent('reminder', '交接・提醒', '新提醒', '有人新增工作提醒'),
  LineNotifyEvent('reservation_new', '訂位', '新網路訂位', '客人在訂位頁訂位'),
  LineNotifyEvent('reservation_phone', '訂位', '新電話訂位', '在 App 登記的電話訂位'),
  LineNotifyEvent('reservation_cancel', '訂位', '訂位取消', '客人或店裡取消訂位'),
  LineNotifyEvent('reservation_party', '訂位', '改人數申請', '客人申請改人數，等店裡確認'),
  LineNotifyEvent(
    'schedule',
    '班表',
    '班表更新',
    '班表有修改、班表照片辨識好了（同一個人 30 分鐘內的修改只發一則）',
  ),
];

/// 預設＝原本的行為：只有重要交接。
const lineNotifyDefault = <String>{'handover_important'};

/// 資料庫讀回來的值 → 只留認得的種類（讀不到、空值都當預設）
Set<String> parseLineNotifyEvents(Object? raw) {
  if (raw is! List) return {...lineNotifyDefault};
  final known = {for (final e in lineNotifyEvents) e.key};
  return {
    for (final v in raw)
      if (v is String && known.contains(v)) v,
  };
}

/// 存回資料庫：照畫面的順序排好（同一組勾選每次存出來都一樣）
List<String> lineNotifyEventsToList(Set<String> on) => [
  for (final e in lineNotifyEvents)
    if (on.contains(e.key)) e.key,
];

/// 一句話摘要，放在交接頁的 LINE 卡片
String lineNotifySummary(Set<String> on) {
  final names = [
    for (final e in lineNotifyEvents)
      if (on.contains(e.key)) e.label,
  ];
  if (names.isEmpty) return '目前不發任何通知到群組';
  if (names.length <= 2) return '發到群組：${names.join('、')}';
  return '發到群組：${names.take(2).join('、')} 等 ${names.length} 項';
}
