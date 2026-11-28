import 'repository.dart';

/// 廠商名稱設定的一條規則（ops 0166 `vendor_name_rules`）。
/// kind：
/// - alias：寫法 name 一律當成 target（進貨區塊分組、選擇廠商清單、常用廠商提示都套用）
/// - list_alias：只在「選擇廠商」清單把 name 顯示成 target
/// - list_hide：「選擇廠商」清單不顯示 name
/// - list_add：「選擇廠商」清單一定列出 name
/// - hint_add／hint_remove：類別 category 的常用廠商提示加上／拿掉 name
/// - hint_alias：常用廠商提示裡的 name 顯示成 target
/// - hint_hide：類別 category 不顯示常用廠商提示
/// - petty_hint_hide：零用金付款時，類別 category 不自動帶入廠商、不顯示提示
class VendorRule {
  const VendorRule({
    this.id,
    required this.kind,
    this.category,
    this.name,
    this.target,
    this.sortOrder = 0,
  });
  final String? id;
  final String kind;
  final String? category;
  final String? name;
  final String? target;
  final int sortOrder;

  static const kinds = [
    'alias',
    'list_alias',
    'list_hide',
    'list_add',
    'hint_add',
    'hint_remove',
    'hint_alias',
    'hint_hide',
    'petty_hint_hide',
  ];

  /// 這種規則要填哪些欄位（跟資料庫 vendor_name_rules_shape 一樣）
  static bool needsTarget(String kind) =>
      kind == 'alias' || kind == 'list_alias' || kind == 'hint_alias';
  static bool needsCategory(String kind) =>
      kind == 'hint_add' ||
      kind == 'hint_remove' ||
      kind == 'hint_hide' ||
      kind == 'petty_hint_hide';
  static bool needsName(String kind) =>
      kind != 'hint_hide' && kind != 'petty_hint_hide';

  factory VendorRule.fromRow(Map<String, dynamic> r) => VendorRule(
    id: r['id'] as String?,
    kind: r['kind'] as String,
    category: r['category_code'] as String?,
    name: r['name'] as String?,
    target: r['target'] as String?,
    sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toRow() => {
    'kind': kind,
    'category_code': category,
    'name': name?.trim(),
    'target': target?.trim(),
    'sort_order': sortOrder,
  };

  /// 跟 SQL 測試同一種寫法：kind|類別|名字|改成
  String get signature =>
      [kind, category ?? '', name ?? '', target ?? ''].join('|');
}

/// 一家店的廠商名稱設定。進貨頁讀資料庫；讀不到（0166 還沒套用）就照以前 lib/config.dart 寫死的內容（[legacy]），之後可以拿掉。
class VendorRules {
  VendorRules(List<VendorRule> rules, {this.fromDb = false})
    : rules = List.unmodifiable(List<VendorRule>.of(rules)..sort(_order));
  final List<VendorRule> rules;
  final bool fromDb;

  static int _order(VendorRule a, VendorRule b) {
    final k = a.kind.compareTo(b.kind);
    return k != 0 ? k : a.sortOrder.compareTo(b.sortOrder);
  }

  Iterable<VendorRule> _of(String kind) => rules.where((r) => r.kind == kind);
  Map<String, String> _map(String kind) => {
    for (final r in _of(kind)) r.name!: r.target!,
  };
  Map<String, List<String>> _byCat(String kind) {
    final out = <String, List<String>>{};
    for (final r in _of(kind)) {
      out.putIfAbsent(r.category!, () => []).add(r.name!);
    }
    return out;
  }

  /// 同一家廠商的不同寫法 → 統一的名字
  late final Map<String, String> groupAlias = _map('alias');

  /// 「選擇廠商」清單：改名、不顯示、一定列出
  late final Map<String, String> listAlias = _map('list_alias');
  late final Set<String> listHide = {for (final r in _of('list_hide')) r.name!};
  late final List<String> listAdd = [for (final r in _of('list_add')) r.name!];

  /// 常用廠商提示：依類別加上、拿掉；改名；不顯示的類別
  late final Map<String, List<String>> hintAdd = _byCat('hint_add');
  late final Map<String, Set<String>> hintRemove = {
    for (final e in _byCat('hint_remove').entries) e.key: e.value.toSet(),
  };
  late final Map<String, String> hintAlias = _map('hint_alias');
  late final Set<String> hintHide = {
    for (final r in _of('hint_hide')) r.category!,
  };

  /// 零用金付款時不自動帶入廠商、不顯示提示的類別
  late final Set<String> pettyHintHide = {
    for (final r in _of('petty_hint_hide')) r.category!,
  };

  // ---------------- 讀取與暫存 ----------------
  static final _cache = <String, VendorRules>{};

  /// 這家店目前用的設定（讀過資料庫用資料庫的，還沒讀或讀不到用 [legacy]）
  static VendorRules of(String storeId, String storeName) =>
      _cache[storeId] ?? VendorRules.legacy(storeName);

  /// 從資料庫讀這家店的設定並記住；讀不到就用 [legacy]（不記住，下次再試）
  static Future<VendorRules> load(
    Repository repo,
    String storeId,
    String storeName,
  ) async {
    try {
      final r = VendorRules(await repo.vendorRules(storeId), fromDb: true);
      _cache[storeId] = r;
      return r;
    } catch (_) {
      return _cache[storeId] ?? VendorRules.legacy(storeName);
    }
  }

  /// 在設定畫面改過之後更新暫存
  static void put(String storeId, VendorRules rules) => _cache[storeId] = rules;

  /// 測試用：清掉暫存
  static void clearCache() => _cache.clear();

  /// 資料庫讀不到時的內容＝以前 lib/config.dart 寫死的（2026-11-28），跟 ops 0166 `app.vendor_rules_seed_legacy` 填的一模一樣。
  factory VendorRules.legacy(String storeName) =>
      VendorRules(legacySeed(storeName));

  static List<VendorRule> legacySeed(String storeName) {
    // config.dart 的全域設定（不分店）：vendorGroupAlias、vendorHintHidden、pettyCashHintHidden、
    // vendorHintRemove、vendorHintRename、vendorHintAdd
    const global = [
      VendorRule(kind: 'alias', name: '德哥', target: '阿德水果'),
      VendorRule(kind: 'hint_hide', category: 'xc_ramen_misc'),
      VendorRule(kind: 'petty_hint_hide', category: 'xc_bar_liquor'),
      VendorRule(
        kind: 'petty_hint_hide',
        category: 'xc_ramen_food',
        sortOrder: 1,
      ),
      VendorRule(kind: 'hint_remove', category: 'xc_cafe_food', name: '柳橙汁'),
      VendorRule(kind: 'hint_alias', name: '二店拉麵食材', target: '立成'),
      VendorRule(kind: 'hint_add', category: 'xc_bar_food', name: '小郭'),
    ];
    const xinli = '欣利實業（茗茶酒）';
    // vendorListRename／vendorListRemove／vendorListAdd（依店名）
    switch (storeName) {
      case '小城外':
        return [
          ...global,
          const VendorRule(kind: 'list_alias', name: '小郭食材', target: '小郭'),
          const VendorRule(
            kind: 'list_alias',
            name: 'yoyo',
            target: 'YOYO',
            sortOrder: 1,
          ),
          const VendorRule(
            kind: 'list_alias',
            name: '欣利',
            target: xinli,
            sortOrder: 2,
          ),
          const VendorRule(
            kind: 'list_alias',
            name: '欣力',
            target: xinli,
            sortOrder: 3,
          ),
          const VendorRule(
            kind: 'list_alias',
            name: '欣利實業',
            target: xinli,
            sortOrder: 4,
          ),
          for (final (i, n) in const [
            '布布拉麵',
            '二店拉麵食材',
            '小郭抽成',
            '廣泰',
            '瑪格莉特比薩',
            '瑪格麗特披薩',
            '生蠔',
          ].indexed)
            VendorRule(kind: 'list_hide', name: n, sortOrder: i),
          const VendorRule(kind: 'list_add', name: '花都'),
        ];
      case '隱城':
        return [
          ...global,
          const VendorRule(kind: 'list_alias', name: '欣利', target: xinli),
          const VendorRule(
            kind: 'list_alias',
            name: '欣力',
            target: xinli,
            sortOrder: 1,
          ),
          const VendorRule(
            kind: 'list_alias',
            name: '欣利實業',
            target: xinli,
            sortOrder: 2,
          ),
          for (final (i, n) in const ['薯條', '布布拉麵', '小郭食材'].indexed)
            VendorRule(kind: 'list_hide', name: n, sortOrder: i),
          const VendorRule(kind: 'list_add', name: '喝酒生活'),
        ];
      default:
        // 以前 config.dart 的全域設定對每一家店都有效（包括公版的店）；資料庫裡新開的店沒有任何規則
        return [...global];
    }
  }
}

// ---------------- 廠商名稱的共用算法 ----------------
final _vendorParen = RegExp(r'\s*[(（][^()（）]*[)）]\s*$');

/// 廠商的統一名稱（進貨區塊分組、新增進貨的廠商清單共用）：去掉名稱最後的括號說明（大倉捷(退酒) → 大倉捷），
/// 再照「同一家的不同寫法」合併（德哥 → 阿德水果）。只影響畫面，資料不改。
String? normalizeVendorName(String raw, VendorRules rules) {
  var n = raw.trim();
  if (n.isEmpty) return null;
  final base = n.replaceFirst(_vendorParen, '').trim();
  if (base.isNotEmpty) n = base;
  return rules.groupAlias[n] ?? n;
}

/// 常用廠商提示的調整：不顯示的類別、拿掉、改名、加入（去除重複）
Map<String, List<String>> adjustVendorHints(
  Map<String, List<String>> hints,
  VendorRules rules,
) {
  final out = <String, List<String>>{};
  final codes = {...hints.keys, ...rules.hintAdd.keys};
  for (final c in codes) {
    if (rules.hintHide.contains(c)) continue;
    final list = <String>[];
    for (final n in [...?hints[c], ...?rules.hintAdd[c]]) {
      if (rules.hintRemove[c]?.contains(n) ?? false) continue;
      final name = rules.hintAlias[n] ?? rules.groupAlias[n] ?? n;
      if (!list.contains(name)) list.add(name);
    }
    if (list.isNotEmpty) out[c] = list;
  }
  return out;
}
