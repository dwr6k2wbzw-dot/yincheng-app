import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/services/shift_export.dart';

void main() {
  test('匯出班表：一人一列、一天一欄，時數與月休跟畫面同一算法', () {
    final a = ShiftPerson(id: 'a', name: 'Tim');
    final b = ShiftPerson(id: 'b', name: 'Luca', kind: 'part');
    final data = ShiftMonth(
      DateTime(2026, 11),
      [a, b],
      {
        'a': {1: 'B', 2: '休', 3: 'BH'},
        'b': {1: '18:00-00:30'},
      },
      {1: '包場'},
      {'a': const ShiftStats(compUnused: 2, specialTotal: 5)},
      const [],
    );
    final bytes = buildShiftXlsx(
      storeName: '小城外',
      data: data,
      marks: const ['B', 'BH', '休'],
      codeHours: const {'B': 7.5, 'BH': 8.5},
      codeTimes: const {'B': '17:00-00:30', 'BH': '17:00-01:30'},
    );
    final sh = Excel.decodeBytes(bytes)['班表'];
    String v(int c, int r) => sh.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value?.toString() ?? '';
    expect(v(0, 0), contains('2026 年 11 月'));
    expect(v(1, 3), '1'); // 日期
    expect(v(1, 4), '日'); // 2026/11/1 是星期日
    expect(v(0, 5), 'Tim');
    expect(v(1, 5), 'B');
    expect(v(2, 5), '休');
    expect(v(0, 6), 'Luca（兼）');
    expect(v(1, 6), '18:00\n00:30');
    final stat = 30 + 1; // 11 月 30 天，統計從第 31 欄開始
    expect(v(stat, 3), '總時數');
    expect(v(stat, 5), '16'); // 7.5 + 8.5
    expect(v(stat + 1, 5), '2'); // 上班天數
    expect(v(stat + 2, 5), '1'); // 月休
    expect(v(stat + 3, 5), '2');
    expect(v(stat + 4, 5), '5');
    expect(v(stat, 6), '6.5'); // 兼職時段 18:00～00:30
    expect(v(stat + 2, 6), '—');
    expect(v(0, 7), '人力');
    expect(v(1, 7), '2');
    expect(v(0, 8), '備註');
    expect(v(1, 8), '包場');
    expect(shiftFileName('小城外', DateTime(2026, 11)), '小城外班表_2026-11.xlsx');
  });
}
