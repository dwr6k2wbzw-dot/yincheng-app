import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/staff_order.dart';

typedef _P = ({String name, bool full, bool active});

void main() {
  _P p(String name, bool full, [bool active = true]) => (name: name, full: full, active: active);
  List<String> names(List<_P> l) => [for (final x in l) x.name];

  test('正職排最上面，同一類照原本順序（後來新增的正職排序數字比兼職大）', () {
    final list = [p('正1', true), p('正2', true), p('兼1', false), p('兼2', false), p('新正職', true)];
    expect(names(fullTimeFirst(list, (x) => x.full)), ['正1', '正2', '新正職', '兼1', '兼2']);
  });

  test('停用的照舊放最後：只在同一段（啟用／停用）裡調整', () {
    final list = [p('兼A', false), p('正B', true), p('兼C', false, false), p('正D', true, false)];
    expect(names(fullTimeFirst(list, (x) => x.full, group: (x) => x.active)), ['正B', '兼A', '正D', '兼C']);
  });

  test('照日期分段：不同天不會混在一起', () {
    final d1 = DateTime(2026, 11, 27), d2 = DateTime(2026, 11, 28);
    final list = [(d: d2, n: '兼1', f: false), (d: d2, n: '正1', f: true), (d: d1, n: '兼2', f: false), (d: d1, n: '正2', f: true)];
    expect([for (final x in fullTimeFirst(list, (x) => x.f, group: (x) => x.d)) x.n], ['正1', '兼1', '正2', '兼2']);
  });

  test('跨店來支援的正職：用兩家店的正職名單判斷，同一天排在本店兼職前面', () {
    final full = {'本店正職', '別店正職'};
    final list = ['本店兼職', '別店正職', '本店正職'];
    expect(fullTimeFirst(list, full.contains), ['別店正職', '本店正職', '本店兼職']);
  });

  test('空的、全是同一類', () {
    expect(fullTimeFirst(<_P>[], (x) => x.full), isEmpty);
    expect(names(fullTimeFirst([p('a', false), p('b', false)], (x) => x.full)), ['a', 'b']);
  });
}
