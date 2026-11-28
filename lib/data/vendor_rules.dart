import 'models.dart';
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
    this.userMade = false,
  });
  final String? id;
  final String kind;
  final String? category;
  final String? name;
  final String? target;
  final int sortOrder;

  /// 店長、老闆在設定畫面自己新增的（資料庫 created_by 有值）。
  /// 0166 從以前寫死的設定搬進來的（created_by 空白）和讀不到資料庫時的 [VendorRules.legacy] 都是 false。
  final bool userMade;

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
    userMade: r['created_by'] != null,
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

  /// 上面那些裡面，店長、老闆在設定畫面自己新增的（自動帶入廠商時也看畫面上選的類別，見 [autoSupplierNames]）
  late final Set<String> pettyHintHideUserMade = {
    for (final r in _of('petty_hint_hide'))
      if (r.userMade) r.category!,
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

/// 新增進貨畫面某個類別的常用廠商提示（最多 [limit] 個）。
/// [hints] 是依來源類別分的原始提示；[displayAs] 是舊類別 → 合併後的類別（0048）。
/// 排除規則兩層都看（Codex P2）：來源類別的（以前就有的設定，例如 xc_ramen_misc）
/// 和畫面上選的類別本身的（設定畫面只能選目前的類別，店長設「這類不提示」「提示拿掉」「零用金不帶廠商」都是設在這裡）。
/// [sourceHidden]：這個來源類別在目前付款方式下要不要整個排除（隱城依付款方式隱藏的舊類別等）。
List<String> vendorHintsForCategory(
  Map<String, List<String>> hints,
  VendorRules rules,
  Map<String, String> displayAs,
  String category, {
  required bool petty,
  bool Function(String code)? sourceHidden,
  int limit = 6,
}) {
  if (rules.hintHide.contains(category)) return const [];
  if (petty && rules.pettyHintHide.contains(category)) return const [];
  final removed = <String>{
    for (final n in rules.hintRemove[category] ?? const <String>{}) ...[
      n,
      rules.hintAlias[n] ?? rules.groupAlias[n] ?? n,
    ],
  };
  final out = <String>[];
  for (final e in adjustVendorHints(hints, rules).entries) {
    if ((displayAs[e.key] ?? e.key) != category) continue;
    if (petty && rules.pettyHintHide.contains(e.key)) continue;
    if (sourceHidden?.call(e.key) ?? false) continue;
    for (final n in e.value) {
      if (removed.contains(n) || out.contains(n)) continue;
      out.add(n);
    }
  }
  return out.take(limit).toList();
}

/// 新增進貨畫面選了類別 [category] 時，可以自動帶入的廠商（依合併後的類別比對，[displayAs] 同上）。
/// 排除：來源類別在目前付款方式不適用的（[sourceHidden]）、零用金付款時來源類別設了「零用金不帶廠商」的。
/// 畫面上選的類別本身設的「零用金不帶廠商」只算店長、老闆在設定畫面自己新增的那幾條（[VendorRules.pettyHintHideUserMade]）：
/// 0166 從以前寫死的設定搬進來的那幾條維持只看來源類別——小城外的 xc_bar_liquor（酒水）那條如果也看選的類別，
/// 零用金選「酒水」時併進來的酒水副材料、咖啡吧-酒水廠商就不會再自動帶入，兩家店的結果會變（Codex 第二輪）。
List<String> autoSupplierNames(
  Iterable<Supplier> sups,
  VendorRules rules,
  Map<String, String> displayAs,
  String category, {
  required bool petty,
  bool Function(String code)? sourceHidden,
}) {
  if (petty && rules.pettyHintHideUserMade.contains(category)) return const [];
  return [
    for (final s in sups)
      if ((displayAs[s.defaultCategory] ?? s.defaultCategory) == category &&
          !_autoSourceHidden(s.defaultCategory, rules, petty, sourceHidden))
        s.name,
  ];
}

bool _autoSourceHidden(
  String? code,
  VendorRules rules,
  bool petty,
  bool Function(String code)? sourceHidden,
) =>
    code != null &&
    ((sourceHidden?.call(code) ?? false) ||
        (petty && rules.pettyHintHide.contains(code)));

/// 每一種規則在畫面上怎麼稱呼、什麼意思
const vendorRuleLabels = <String, (String, String)>{
  'alias': ('合併寫法', '這個寫法一律當成同一家：進貨區塊、選擇廠商、常用廠商都會合併'),
  'list_alias': ('清單改名', '只在新增進貨「選擇廠商」清單裡換成另一個名字'),
  'list_hide': ('清單不顯示', '「選擇廠商」清單不列出這個名字'),
  'list_add': ('清單一定列出', '就算最近沒進貨，「選擇廠商」清單也列出來'),
  'hint_add': ('常用廠商', '選了這個類別時，提示這家廠商'),
  'hint_remove': ('提示拿掉', '這個類別不提示這家廠商'),
  'hint_alias': ('提示改名', '提示裡的這個名字換成另一個'),
  'hint_hide': ('這類不提示', '這個類別不顯示常用廠商'),
  'petty_hint_hide': ('零用金不帶廠商', '用零用金付款時，這個類別不自動帶入、不提示廠商'),
};

/// 一條規則用一句話講出來（清單上顯示）
String describeVendorRule(VendorRule r, Map<String, String> catName) {
  // 這家店沒有的類別（例如從舊設定帶過來、只有另一家店才有的類別）不露出代碼
  final cat = r.category == null ? '' : (catName[r.category] ?? '其他店的類別');
  return switch (r.kind) {
    'alias' => '${r.name} → ${r.target}',
    'list_alias' => '清單裡 ${r.name} → ${r.target}',
    'list_hide' => '清單不顯示 ${r.name}',
    'list_add' => '清單一定列出 ${r.name}',
    'hint_add' => '$cat：${r.name}',
    'hint_remove' => '$cat：不提示 ${r.name}',
    'hint_alias' => '提示裡 ${r.name} → ${r.target}',
    'hint_hide' => '$cat：不顯示常用廠商',
    'petty_hint_hide' => '$cat：零用金時不帶廠商',
    _ => [r.category, r.name, r.target].whereType<String>().join(' '),
  };
}

/// 檢查一條規則（跟資料庫的格式檢查一樣）；沒問題回傳 null
String? validateVendorRule(
    String kind, String? category, String name, String target) {
  if (VendorRule.needsCategory(kind) &&
      (category == null || category.isEmpty)) {
    return '請選類別';
  }
  if (VendorRule.needsName(kind) && name.trim().isEmpty) return '請填廠商名稱';
  if (name.trim().length > 60 || target.trim().length > 60) return '名稱最多 60 個字';
  // 合併寫法、清單改名、清單不顯示比對的是去掉最後括號說明之後的名字（[normalizeVendorName]），
  // 填「欣利實業（茗茶酒）」永遠對不到，所以直接請店長改填括號前面的名字（Codex 第三輪）
  if (const {'alias', 'list_alias', 'list_hide'}.contains(kind)) {
    final n = name.trim();
    final base = n.replaceFirst(_vendorParen, '').trim();
    if (base.isNotEmpty && base != n) {
      return '最後的括號說明會自動去掉，請填「$base」就好';
    }
  }
  if (VendorRule.needsTarget(kind)) {
    if (target.trim().isEmpty) return '請填要改成的名字';
    if (target.trim() == name.trim()) return '兩個名字一樣，不用設定';
  }
  return null;
}
