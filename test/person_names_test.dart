// 員工顯示用的名字（ops 0125，老闆 2026-11-17：員工一律顯示全名，暱稱放括號）
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/attendance_models.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/payroll.dart';
import 'package:yincheng_ops/data/person_names.dart';

void main() {
  test('全名（暱稱）；暱稱已經在全名裡只顯示全名；沒填全名照舊顯示暱稱', () {
    expect(personLabel('Josh', '王小明'), '王小明（Josh）');
    expect(personLabel('小明', '王小明'), '王小明');
    expect(personLabel('王小明', '王小明'), '王小明');
    expect(personLabel('Josh', null), 'Josh');
    expect(personLabel('Josh', ''), 'Josh');
  });

  test('班表人員：格子裡只放全名，其他地方放全名（暱稱）', () {
    final p = ShiftPerson.fromRow({'id': 'a1', 'name': 'Josh', 'full_name': '王小明', 'user_id': 'u', 'user_verified_at': '2026-11-17T00:00:00Z'});
    expect(p.label, '王小明（Josh）');
    expect(p.shortLabel, '王小明');
    expect(p.userVerified, isTrue);
    final q = ShiftPerson.fromRow({'id': 'a2', 'name': '阿凱', 'user_id': 'u2'});
    expect(q.label, '阿凱');
    expect(q.shortLabel, '阿凱');
    expect(q.userVerified, isFalse, reason: '以前自己選、還沒生效的');
  });

  test('出勤、薪資從資料庫只拿到暱稱：讀過班表人員之後用 id 換成全名（暱稱）；沒讀過的人照原樣', () {
    ShiftPerson.fromRow({'id': 'n1', 'name': 'Josh', 'full_name': '王小明'});
    final row = PayrollRow.fromRow({'person_id': 'n1', 'name': 'Josh'});
    expect(row.name, '王小明（Josh）');
    final pin = PinStatus.fromRow({'person_id': 'n1', 'name': 'Josh', 'active': true, 'has_pin': false, 'can_set': true, 'mine': false});
    expect(pin.name, '王小明（Josh）');
    final other = PayrollRow.fromRow({'person_id': 'someone-else', 'name': '支援的人'});
    expect(other.name, '支援的人');
  });

  test('打卡名單：名字由資料庫給（已經是全名（暱稱））', () {
    final k = KioskPerson.fromRow({'person_id': 'n1', 'name': '王小明（Josh）', 'has_pin': true});
    expect(k.name, '王小明（Josh）');
    expect(k.hasPin, isTrue);
  });
}
