// 用講的改排班設定（ops 0154）：建議怎麼顯示、示範版的流程（建議 → 套用 → 改回去、被改過就不套）。示範資料都是虛構的。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/booking_assist.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/shift_planner.dart';

void main() {
  group('AssistChange 顯示（排班）', () {
    test('每天要幾人、某一天要幾人', () {
      const s = AssistChange({
        'op': 'staffing',
        'weekday': 5,
        'before': {'need': 4, 'min_full': 1},
        'after': {'need': 5, 'min_full': 0}
      });
      expect(s.label, '每週五要幾人');
      expect(s.beforeText, '4 人（正職至少 1）');
      expect(s.afterText, '5 人');
      const n = AssistChange({'op': 'staffing', 'weekday': 2, 'before': null, 'after': {'need': 3, 'min_full': 1}});
      expect(n.beforeText, '（沒設）');
      const d = AssistChange({'op': 'staffing_day', 'date': '2032-12-24', 'before': null, 'after': {'need': 6}});
      expect(d.label, '12/24（週五）要幾人');
      expect(d.beforeText, '照星期的人數');
      expect(d.afterText, '6 人');
    });

    test('排班設定、個人條件', () {
      const a = AssistChange({'op': 'setting', 'field': 'request_deadline', 'before': 20, 'after': 25});
      expect(a.label, '填班截止日');
      expect(a.afterText, '每月 25 號');
      const b = AssistChange({'op': 'setting', 'field': 'off_per_day', 'before': 1, 'after': null});
      expect(b.beforeText, '1 位');
      expect(b.afterText, '不限');
      const c = AssistChange({'op': 'setting', 'field': 'prefer_run', 'before': null, 'after': 5});
      expect(c.label, '盡量不連上');
      expect(c.afterText, '5 天');
      const r = AssistChange({'op': 'rule', 'person_id': 'p1', 'person_name': '王凱文', 'field': 'no_weekdays', 'before': [], 'after': [1, 2]});
      expect(r.label, '王凱文・固定不排的星期');
      expect(r.beforeText, '（沒有）');
      expect(r.afterText, '週一、週二');
      const m = AssistChange({'op': 'rule', 'person_id': 'f0', 'person_name': '林志明', 'field': 'month_off', 'before': 9.0, 'after': 8.5});
      expect(m.beforeText, '9 天');
      expect(m.afterText, '8.5 天');
    });
  });

  group('示範版流程', () {
    test('週五週六要 5 個人：建議 → 套用 → 讀設定看得到 → 改回去', () async {
      final repo = DemoRepository();
      final r = await repo.askShiftAssistant('yc', '週五週六要 5 個人', const []);
      expect(r.changes.map((c) => c.raw['weekday']), [5, 6]);
      expect(r.changes.first.beforeText, '4 人（正職至少 1）');
      await repo.applyShiftAssist('yc', '週五週六要 5 個人', r.changes);
      final setup = await repo.shiftPlanSetup('yc', DateTime.now());
      expect(setup.staffing[5]!.need, 5);
      final h = await repo.shiftAssistHistory('yc');
      expect(h.single.request, '週五週六要 5 個人');
      await repo.undoShiftAssist(h.single.id);
      expect((await repo.shiftPlanSetup('yc', DateTime.now())).staffing[5]!.need, 4);
      expect((await repo.shiftAssistHistory('yc')).single.undoneAt, isNotNull);
    });

    test('問完到確認之間被改過：整筆不套用', () async {
      final repo = DemoRepository();
      final r = await repo.askShiftAssistant('yc', '同一天最多 2 位指休、每月 25 號前填好班', const []);
      expect(r.changes.length, 2);
      await repo.saveShiftDeadline('yc', 22);
      await expectLater(repo.applyShiftAssist('yc', 'x', r.changes), throwsA(predicate((e) => '$e'.contains('SHIFT_ASSIST_STALE'))));
      expect((await repo.shiftPlanSetup('yc', DateTime.now())).offPerDay, 1, reason: '前一項也不能寫進去');
    });

    test('改回去時之後又被改過：整筆不動', () async {
      final repo = DemoRepository();
      final r = await repo.askShiftAssistant('yc', '阿凱每月最多上 12 天', const []);
      expect(r.changes.single.label, '王凱文・每月最多上幾天');
      await repo.applyShiftAssist('yc', 'x', r.changes);
      final r2 = await repo.askShiftAssistant('yc', '阿凱每月最多上 10 天', const []);
      await repo.applyShiftAssist('yc', 'y', r2.changes);
      final h = await repo.shiftAssistHistory('yc');
      await expectLater(repo.undoShiftAssist(h.last.id), throwsA(predicate((e) => '$e'.contains('SHIFT_ASSIST_STALE'))));
      await repo.undoShiftAssist(h.first.id);
      expect((await repo.shiftPlanSetup('yc', DateTime.now())).rules['p1']!.maxShifts, 12);
    });

    test('聽不懂時只回說明、沒有建議', () async {
      final r = await DemoRepository().askShiftAssistant('yc', '幫我把阿凱的時薪調高', const []);
      expect(r.changes, isEmpty);
      expect(r.reply, contains('示範版只認得幾種說法'));
    });
  });

  group('從 AI 助理回來時合併每日人力（Codex P2）', () {
    test('本地改過的天保留、其他天換成已存的（AI 剛改的那天不會被蓋回去）', () {
      const saved = {1: StaffingNeed(3, 1), 5: StaffingNeed(6, 2)}; // AI 把週五改成 6
      const local = {1: StaffingNeed(4, 1), 5: StaffingNeed(4, 1)}; // 本地只改了週一
      final m = mergeStaffing(saved, local, {1});
      expect(m[1]!.need, 4, reason: '週一還沒存的修改保留');
      expect(m[5]!.need, 6, reason: '週五換成 AI 存好的值');
      expect(m[5]!.minFull, 2);
      expect(m[3]!.need, 3, reason: '沒設定的天用預設');
    });
    test('沒有本地修改：全部照已存的', () {
      final m = mergeStaffing(const {2: StaffingNeed(5, 0)}, const {2: StaffingNeed(9, 0)}, {});
      expect(m[2]!.need, 5);
    });
  });
}
