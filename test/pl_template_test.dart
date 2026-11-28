// 損益範本（ops 0169，公版）：範本內容的規則、讀資料庫回的格式、示範資料的套用流程。
// 資料庫那一份在 ops 的 app.pl_template()，示範資料這一份（demoPlTemplates）要一起改。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/pl_template.dart';
import 'package:yincheng_ops/data/repository.dart';

void main() {
  group('範本內容', () {
    test('四種業態都有', () {
      expect(demoPlTemplates.map((t) => t.kind),
          ['bar', 'cafe', 'restaurant', 'other']);
      expect(demoPlTemplates.map((t) => t.accounts.length), [16, 16, 18, 9]);
    });

    for (final t in demoPlTemplates) {
      test('${t.label}：四種自動帶入各一個、大項對得上、名稱不重複', () {
        final autos = [
          for (final a in t.accounts)
            if (a.autoKind != null) a.autoKind!
        ];
        expect(autos.toSet(), plAutoKinds.keys.toSet());
        expect(autos.length, 4);
        for (final a in t.accounts.where((a) => a.autoKind != null)) {
          expect(a.category, plAutoKinds[a.autoKind]!.$2, reason: a.name);
        }
        expect(t.accounts.map((a) => a.name).toSet().length, t.accounts.length);
        for (final a in t.accounts) {
          expect(['payroll', 'rent', 'misc'], contains(a.category));
          expect(a.name.length, inInclusiveRange(1, 40));
        }
      });
    }
  });

  test('讀資料庫回的 jsonb', () {
    final t = PlTemplate.fromJson({
      'kind': 'bar',
      'label': '酒吧',
      'note': '晚上營業',
      'accounts': [
        ['薪資支出', 'payroll', 'payroll_base'],
        ['水電瓦斯費', 'misc', null],
        ['廣告費', 'misc'],
      ],
    });
    expect(t.kind, 'bar');
    expect(t.accounts.map((a) => a.autoKind), ['payroll_base', null, null]);
    expect(t.summary, '3 個科目・人事 1・雜項 2');
  });

  test('資料庫的錯誤代號拿掉、只留說明', () {
    expect(friendlyError(Exception('message: PL_TEMPLATE_USED：這家店已經有會計科目了,')),
        '這家店已經有會計科目了');
    expect(
        friendlyError(Exception(
            'duplicate key value violates unique constraint "pl_accounts_store_id_name_key"')),
        '這個科目名稱已經有了，請換一個名字。');
  });

  group('示範資料', () {
    test('新店：套範本、再套一次被擋、隱城不能套', () async {
      final repo = DemoRepository();
      expect(await repo.plAccounts('demo-new'), isEmpty);
      expect(await repo.applyPlTemplate('demo-new', 'cafe'), 16);
      final accounts = await repo.plAccounts('demo-new');
      expect(accounts.length, 16);
      expect(accounts.first.name, '薪資支出');
      await expectLater(
          repo.applyPlTemplate('demo-new', 'bar'), throwsA(anything));
      await expectLater(repo.applyPlTemplate('yc', 'bar'), throwsA(anything));
    });

    test('科目改名、停用、重複名稱被擋', () async {
      final repo = DemoRepository();
      await repo.applyPlTemplate('demo-new', 'other');
      final a = (await repo.plAccounts('demo-new'))
          .firstWhere((a) => a.autoKind == null);
      await repo.savePlAccount(
          'demo-new',
          PlAccount(
              id: a.id,
              name: '水電',
              category: a.category,
              sortOrder: a.sortOrder,
              active: false));
      final b =
          (await repo.plAccounts('demo-new')).firstWhere((x) => x.id == a.id);
      expect(b.name, '水電');
      expect(b.active, isFalse);
      await expectLater(
          repo.savePlAccount(
              'demo-new',
              const PlAccount(
                  id: '', name: '水電', category: 'misc', sortOrder: 99),
              isNew: true),
          throwsA(anything));
    });

    test('損益表抬頭：空白＝用店名', () async {
      final repo = DemoRepository();
      await repo.savePlTitle('demo-new', '一店');
      expect(await repo.plTitle('demo-new'), '一店');
      await repo.savePlTitle('demo-new', '  ');
      expect(await repo.plTitle('demo-new'), isNull);
    });
  });
}
