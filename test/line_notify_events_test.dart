// 哪些通知發到 LINE 群組（ops 0162，公版）：讀回來的值、存回去的順序、摘要文字。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/line_notify_events.dart';

void main() {
  test('預設只有重要交接（跟隱城、小城外原本一樣）', () {
    expect(lineNotifyDefault, {'handover_important'});
  });

  test('讀不到、不是清單就當預設', () {
    expect(parseLineNotifyEvents(null), lineNotifyDefault);
    expect(parseLineNotifyEvents('handover'), lineNotifyDefault);
  });

  test('空清單＝什麼都不發（不是預設）', () {
    expect(parseLineNotifyEvents(const []), isEmpty);
  });

  test('不認得的種類、空值丟掉', () {
    expect(parseLineNotifyEvents(['reminder', 'change_request', null, 3]),
        {'reminder'});
  });

  test('存回去照畫面順序，同一組勾選每次一樣', () {
    expect(
        lineNotifyEventsToList({'schedule', 'reminder', 'handover_important'}),
        ['handover_important', 'reminder', 'schedule']);
  });

  test('種類跟資料庫的允許清單一樣（8 種、不重複、沒有功能許願和許願單）', () {
    final keys = [for (final e in lineNotifyEvents) e.key];
    expect(keys.toSet().length, keys.length);
    expect(keys.toSet(), {
      'handover_important',
      'handover',
      'reminder',
      'schedule',
      'reservation_new',
      'reservation_phone',
      'reservation_cancel',
      'reservation_party',
    });
  });

  test('摘要', () {
    expect(lineNotifySummary({}), '目前不發任何通知到群組');
    expect(lineNotifySummary({'handover_important'}), '發到群組：重要交接');
    expect(
        lineNotifySummary({'handover_important', 'reminder'}), '發到群組：重要交接、新提醒');
    expect(
        lineNotifySummary(
            {'handover_important', 'reminder', 'reservation_new'}),
        '發到群組：重要交接、新提醒 等 3 項');
  });
}
