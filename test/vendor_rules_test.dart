import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/repository.dart';
import 'package:yincheng_ops/data/vendor_rules.dart';

// ---- 2026-11-28 以前 lib/config.dart 寫死的內容（原樣抄下來，用來證明搬進資料庫後結果一模一樣）----
const oldHintHidden = {'xc_ramen_misc'};
const oldPettyCashHintHidden = {'xc_bar_liquor', 'xc_ramen_food'};
const oldHintRemove = {
  'xc_cafe_food': {'柳橙汁'},
};
const oldHintRename = {'二店拉麵食材': '立成'};
const oldGroupAlias = <String, String>{'德哥': '阿德水果'};
const oldListRename = <String, Map<String, String>>{
  '小城外': {
    '小郭食材': '小郭',
    'yoyo': 'YOYO',
    '欣利': '欣利實業（茗茶酒）',
    '欣力': '欣利實業（茗茶酒）',
    '欣利實業': '欣利實業（茗茶酒）'
  },
  '隱城': {'欣利': '欣利實業（茗茶酒）', '欣力': '欣利實業（茗茶酒）', '欣利實業': '欣利實業（茗茶酒）'},
};
const oldListRemove = <String, Set<String>>{
  '小城外': {'布布拉麵', '二店拉麵食材', '小郭抽成', '廣泰', '瑪格莉特比薩', '瑪格麗特披薩', '生蠔'},
  '隱城': {'薯條', '布布拉麵', '小郭食材'},
};
const oldListAdd = <String, List<String>>{
  '隱城': ['喝酒生活'],
  '小城外': ['花都'],
};
const oldHintAdd = {
  'xc_bar_food': ['小郭'],
};

final _oldParen = RegExp(r'\s*[(（][^()（）]*[)）]\s*$');
String? oldNormalize(String raw) {
  var n = raw.trim();
  if (n.isEmpty) return null;
  final base = n.replaceFirst(_oldParen, '').trim();
  if (base.isNotEmpty) n = base;
  return oldGroupAlias[n] ?? n;
}

Map<String, List<String>> oldAdjustHints(Map<String, List<String>> hints) {
  final out = <String, List<String>>{};
  final codes = {...hints.keys, ...oldHintAdd.keys};
  for (final c in codes) {
    if (oldHintHidden.contains(c)) continue;
    final list = <String>[];
    for (final n in [...?hints[c], ...?oldHintAdd[c]]) {
      if (oldHintRemove[c]?.contains(n) ?? false) continue;
      final name = oldHintRename[n] ?? n;
      if (!list.contains(name)) list.add(name);
    }
    if (list.isNotEmpty) out[c] = list;
  }
  return out;
}

/// ops tests/71_vendor_name_rules.sql 比對資料庫內容用的同一份字串（kind|類別|名字|改成，依 kind、排序）
const sqlSeed = {
  '隱城': 'alias||德哥|阿德水果;hint_add|xc_bar_food|小郭|;hint_alias||二店拉麵食材|立成;hint_hide|xc_ramen_misc||;hint_remove|xc_cafe_food|柳橙汁|;'
      'list_add||喝酒生活|;list_alias||欣利|欣利實業（茗茶酒）;list_alias||欣力|欣利實業（茗茶酒）;list_alias||欣利實業|欣利實業（茗茶酒）;'
      'list_hide||薯條|;list_hide||布布拉麵|;list_hide||小郭食材|;petty_hint_hide|xc_bar_liquor||;petty_hint_hide|xc_ramen_food||',
  '小城外': 'alias||德哥|阿德水果;hint_add|xc_bar_food|小郭|;hint_alias||二店拉麵食材|立成;hint_hide|xc_ramen_misc||;hint_remove|xc_cafe_food|柳橙汁|;'
      'list_add||花都|;list_alias||小郭食材|小郭;list_alias||yoyo|YOYO;list_alias||欣利|欣利實業（茗茶酒）;list_alias||欣力|欣利實業（茗茶酒）;list_alias||欣利實業|欣利實業（茗茶酒）;'
      'list_hide||布布拉麵|;list_hide||二店拉麵食材|;list_hide||小郭抽成|;list_hide||廣泰|;list_hide||瑪格莉特比薩|;list_hide||瑪格麗特披薩|;list_hide||生蠔|;'
      'petty_hint_hide|xc_bar_liquor||;petty_hint_hide|xc_ramen_food||',
};

/// 把 SQL 那份字串還原成資料庫讀回來的樣子（id、排序照出現順序）
List<VendorRule> rowsFromSql(String s) {
  final seen = <String, int>{};
  return [
    for (final (i, part) in s.split(';').indexed)
      () {
        final f = part.split('|');
        final order = seen[f[0]] = (seen[f[0]] ?? -1) + 1;
        return VendorRule.fromRow({
          'id': 'r$i',
          'kind': f[0],
          'category_code': f[1].isEmpty ? null : f[1],
          'name': f[2].isEmpty ? null : f[2],
          'target': f[3].isEmpty ? null : f[3],
          'sort_order': order,
        });
      }(),
  ];
}

class _ThrowRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation i) =>
      Future<List<VendorRule>>.error(Exception('relation does not exist'));
}

class _OkRepo implements Repository {
  _OkRepo(this.rows);
  final List<VendorRule> rows;
  @override
  dynamic noSuchMethod(Invocation i) => Future<List<VendorRule>>.value(rows);
}

void expectSameAsOld(VendorRules r, String store) {
  expect(r.groupAlias, oldGroupAlias);
  expect(r.listAlias, oldListRename[store] ?? const <String, String>{});
  expect(r.listHide, oldListRemove[store] ?? const <String>{});
  expect(r.listAdd, oldListAdd[store] ?? const <String>[]);
  expect(r.hintAdd, oldHintAdd);
  expect(r.hintRemove, oldHintRemove);
  expect(r.hintAlias, oldHintRename);
  expect(r.hintHide, oldHintHidden);
  expect(r.pettyHintHide, oldPettyCashHintHidden);
}

void main() {
  setUp(VendorRules.clearCache);

  group('讀不到資料庫時（legacy）跟以前 config.dart 一模一樣', () {
    for (final store in ['隱城', '小城外']) {
      test(store, () => expectSameAsOld(VendorRules.legacy(store), store));
    }
    test('其他店只有以前的全域設定',
        () => expectSameAsOld(VendorRules.legacy('公版小館'), '公版小館'));
  });

  group('資料庫填好的內容（ops 0166）跟 legacy 一樣', () {
    for (final store in ['隱城', '小城外']) {
      test('$store：逐條跟 SQL 測試同一份字串', () {
        expect(
            VendorRules.legacy(store).rules.map((r) => r.signature).join(';'),
            sqlSeed[store]);
      });
      test('$store：從資料庫讀回來的結果跟以前一樣', () {
        expectSameAsOld(
            VendorRules(rowsFromSql(sqlSeed[store]!), fromDb: true), store);
      });
    }
  });

  group('畫面上的結果改前改後一樣', () {
    final names = [
      '德哥',
      '德哥(水果)',
      '阿德水果',
      '大倉捷(退酒)',
      '大倉捷（退酒）',
      ' 小郭 ',
      '欣利',
      '(只有括號)',
      '',
      '   '
    ];
    for (final store in ['隱城', '小城外']) {
      test('$store：進貨區塊的廠商統一名稱', () {
        final r = VendorRules(rowsFromSql(sqlSeed[store]!), fromDb: true);
        for (final n in names) {
          expect(normalizeVendorName(n, r), oldNormalize(n), reason: n);
        }
      });
      test('$store：常用廠商提示（以前的名字沒有合併寫法）', () {
        final r = VendorRules(rowsFromSql(sqlSeed[store]!), fromDb: true);
        final hints = {
          'xc_bar_food': ['YO姊', '小郭'],
          'xc_cafe_food': ['柳橙汁', '鮮奶'],
          'xc_ramen_food': ['二店拉麵食材', '信功'],
          'xc_ramen_misc': ['全聯'],
          'yc_drink': ['大倉捷'],
        };
        expect(adjustVendorHints(hints, r), oldAdjustHints(hints));
      });
    }
  });

  test('公版：常用廠商提示也照合併寫法', () {
    final r = VendorRules(const [
      VendorRule(kind: 'alias', name: '大倉', target: '大倉捷'),
      VendorRule(kind: 'hint_add', category: 'drink', name: '喝酒生活'),
    ]);
    expect(
        adjustVendorHints({
          'drink': ['大倉', '大倉捷']
        }, r),
        {
          'drink': ['大倉捷', '喝酒生活']
        });
  });

  test('新開的店（資料庫沒有規則）什麼都不調整', () {
    final r = VendorRules(const [], fromDb: true);
    expect(normalizeVendorName('德哥', r), '德哥');
    expect(
        adjustVendorHints({
          'a': ['x']
        }, r),
        {
          'a': ['x']
        });
  });

  group('讀取', () {
    test('讀不到資料庫用 legacy、不記住', () async {
      final r = await VendorRules.load(_ThrowRepo(), 'yc', '隱城');
      expect(r.fromDb, isFalse);
      expectSameAsOld(r, '隱城');
      expect(VendorRules.of('yc', '隱城').fromDb, isFalse);
    });
    test('讀到就記住，之後同步拿得到', () async {
      final r = await VendorRules.load(
          _OkRepo(const [VendorRule(kind: 'list_add', name: '花都')]),
          'new',
          '公版小館');
      expect(r.fromDb, isTrue);
      expect(VendorRules.of('new', '公版小館').listAdd, ['花都']);
      expect(VendorRules.of('new', '公版小館').groupAlias, isEmpty);
    });
  });

  group('設定畫面', () {
    test('檢查跟資料庫一樣', () {
      expect(validateVendorRule('alias', null, '德哥', ''), '請填要改成的名字');
      expect(validateVendorRule('alias', null, 'A', ' A '), '兩個名字一樣，不用設定');
      expect(validateVendorRule('hint_add', null, '小郭', ''), '請選類別');
      expect(validateVendorRule('list_hide', null, '  ', ''), '請填廠商名稱');
      expect(validateVendorRule('list_hide', null, '長' * 61, ''), '名稱最多 60 個字');
      expect(validateVendorRule('hint_hide', 'yc_food', '', ''), isNull);
      expect(validateVendorRule('alias', null, '德哥', '阿德水果'), isNull);
    });
    test('一句話說明', () {
      final cats = {'xc_bar_food': '餐食'};
      expect(
          describeVendorRule(
              const VendorRule(kind: 'alias', name: '德哥', target: '阿德水果'),
              cats),
          '德哥 → 阿德水果');
      expect(
          describeVendorRule(
              const VendorRule(
                  kind: 'hint_add', category: 'xc_bar_food', name: '小郭'),
              cats),
          '餐食：小郭');
      expect(
          describeVendorRule(
              const VendorRule(
                  kind: 'petty_hint_hide', category: 'xc_ramen_food'),
              cats),
          '其他店的類別：零用金時不帶廠商');
    });
    test('每一種都有中文說明', () {
      for (final k in VendorRule.kinds) {
        expect(vendorRuleLabels[k], isNotNull, reason: k);
      }
    });
  });
}
