import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/shift_templates.dart';

void main() {
  group('業態範本（ops 0152）', () {
    test('四種、順序跟資料庫 shift_template_list 一樣，預設其他', () {
      expect(shiftTemplates.map((t) => t.kind),
          ['bar', 'cafe', 'restaurant', 'other']);
      expect(defaultShiftTemplate, 'other');
      expect(shiftTemplates.every((t) => t.staffing.length == 7), isTrue);
    });

    test('班別代碼、時段都符合資料庫的格式', () {
      final code = RegExp(r'^[A-Z][A-Z0-9]{0,3}[+-]?$');
      final range = RegExp(
          r'^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$');
      for (final t in shiftTemplates) {
        for (final c in t.codes) {
          expect(code.hasMatch(c.$1) && !['V', 'O'].contains(c.$1), isTrue,
              reason: c.$1);
          expect(range.hasMatch(c.$2), isTrue, reason: c.$2);
        }
        for (final r in t.ranges) {
          expect(range.hasMatch(r), isTrue, reason: r);
        }
        for (final s in t.staffing) {
          expect(s.$2 <= s.$1, isTrue);
        }
      }
    });

    test('一句話摘要', () {
      String s(String k) =>
          shiftTemplates.firstWhere((t) => t.kind == k).summary;
      expect(s('bar'), '平日 2 人・週五六 4 人・班別 B、BL');
      expect(s('cafe'), '平日 2 人・週六日 3 人・班別 AM、PM');
      expect(s('restaurant'), '平日 4 人・週五六日 5 人・班別 L、D、F');
      expect(s('other'), '每天 2 人・用 V／休 記號');
    });

    test('隱城／小城外這一份（沒有 SELF_SIGNUP）看不到套用範本', () {
      expect(
          showApplyTemplate(
              isOwner: true, staffingEmpty: true, optionsEmpty: true),
          isFalse);
    });

    test('示範版：開店選酒吧帶入人力和班別；有資料了不能再套', () async {
      final repo = DemoRepository();
      await repo.signupCreateStore('示範酒吧', '阿酒', kind: 'bar');
      final setup = await repo.shiftPlanSetup('demo-new', DateTime(2027, 1));
      expect([for (var w = 1; w <= 7; w++) setup.staffing[w]!.need],
          [2, 2, 2, 3, 4, 4, 3]);
      expect(setup.preferRun, 5);
      await expectLater(repo.applyShiftTemplate('demo-new', 'cafe'),
          throwsA(predicate((e) => '$e'.contains('SHIFT_TEMPLATE_USED'))));
      await expectLater(repo.applyShiftTemplate('demo-new', 'zzz'),
          throwsA(predicate((e) => '$e'.contains('SHIFT_TEMPLATE_KIND'))));
    });
  });
}
