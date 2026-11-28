import 'shift_off_rules.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../config.dart';
import 'booking_import.dart';
import 'booking_profile.dart';
import 'models.dart';
import 'onboarding.dart';
import 'person_names.dart';
import 'purchase_items_math.dart';
import 'repository.dart';
import 'shift_links.dart';
import 'shift_templates.dart';
import 'store_features.dart';
import '../services/clock.dart';

/// 示範資料：不連線，數字全部是虛構的示範值（不是真實營收），只用來看畫面與操作流程。
/// 登入任何帳號都會以「老闆」身分進入；帳號含 staff 則以員工身分進入（可測試權限差異）。
class DemoRepository implements Repository {
  final _auth = StreamController<bool>.broadcast();
  // 截圖檢查用（ui-shots.yml）：示範版網址加 ?auto=1 直接登入
  bool _signedIn = Uri.base.queryParameters.containsKey('auto');
  // 再加 &as=kiosk 直接以隱城的打卡用帳號登入（as=kiosk-xc：小城外，打卡還沒開）
  String _email = Uri.base.queryParameters['as'] ?? '';
  int _seq = 0;

  final _categories = [
    // 0048：可選只有 酒水／餐食／雜項；舊類別停用、顯示併入（與正式資料庫相同）
    CostCategory.full(
      'yc_drink',
      '酒水',
      null,
      costGroup: 'drink',
      inMiscRate: false,
    ),
    CostCategory.full(
      'yc_food',
      '餐食',
      null,
      costGroup: 'food',
      inMiscRate: false,
    ),
    CostCategory.full(
      'yc_misc',
      '雜項',
      null,
      costGroup: 'other',
      inMiscRate: true,
    ),
    CostCategory.full(
      'liquor_monthly',
      '月結酒商',
      null,
      costGroup: 'drink',
      inMiscRate: false,
      selectable: false,
      displayAs: 'yc_drink',
    ),
    CostCategory.full(
      'liquor_cash',
      '現結酒商',
      null,
      costGroup: 'drink',
      inMiscRate: false,
      selectable: false,
      displayAs: 'yc_drink',
    ),
    CostCategory.full(
      'fruit',
      '酒水副材料-德哥',
      null,
      costGroup: 'drink',
      inMiscRate: false,
      selectable: false,
      displayAs: 'yc_drink',
    ),
    CostCategory.full(
      'ice',
      '酒水副材料-冰塊',
      null,
      costGroup: 'drink',
      inMiscRate: false,
      selectable: false,
      displayAs: 'yc_drink',
    ),
    CostCategory.full(
      'bar_misc',
      '酒水副材料-雜項',
      null,
      costGroup: 'drink',
      inMiscRate: true,
      selectable: false,
      displayAs: 'yc_misc',
    ),
    CostCategory.full(
      'food',
      '餐食進貨',
      null,
      costGroup: 'food',
      inMiscRate: false,
      selectable: false,
      displayAs: 'yc_food',
    ),
    CostCategory.full(
      'petty_misc',
      '零用金-其他雜支',
      null,
      costGroup: 'other',
      inMiscRate: true,
      selectable: false,
      displayAs: 'yc_misc',
    ),
  ];
  final _suppliers = [
    Supplier('s1', '示範酒商A', 'liquor_monthly'),
    Supplier('s2', '示範酒商B', 'liquor_monthly'),
    Supplier('s3', '示範水果行', 'fruit'),
    Supplier('s4', '示範冷凍食品', 'food'),
    Supplier('s5', '示範食材行', 'food'),
  ];
  final _products = [
    Product(
      'p1',
      "Hendrick's Gin",
      '酒水',
      '瓶',
      parLevel: 2,
      countCycle: 'daily',
    ),
    Product('p2', 'Bombay Sapphire', '酒水', '瓶', countCycle: 'weekly'),
    Product('p3', 'Campari', '酒水', '瓶', parLevel: 1),
    Product('p4', 'Chartreuse', '酒水', '瓶'),
    Product('p5', '檸檬', '餐食', '顆', parLevel: 20, countCycle: 'daily'),
    Product('p6', '薄荷葉', '餐食', '盒', countCycle: 'daily'),
  ];
  // 示範：之前盤過的（幾天前、誰盤的）
  late final Map<String, LastCount> _demoLast = {
    'p1': LastCount(
      1.4,
      _daysAgo(1),
      at: DateTime.now().subtract(const Duration(days: 1)),
      by: '示範正職',
    ),
    'p2': LastCount(
      3,
      _daysAgo(9),
      at: DateTime.now().subtract(const Duration(days: 9)),
      by: '示範店長',
    ),
    'p3': LastCount(
      0.6,
      _daysAgo(3),
      at: DateTime.now().subtract(const Duration(days: 3)),
      by: '示範正職',
    ),
    'p5': LastCount(
      34,
      _daysAgo(0),
      at: DateTime.now().subtract(const Duration(hours: 2)),
      by: '示範兼職',
    ),
  };
  static DateTime _daysAgo(int n) {
    final t = DateTime.now().subtract(Duration(hours: 6, days: n));
    return DateTime(t.year, t.month, t.day);
  }

  late final List<Purchase> _purchases = [
    Purchase(
      id: 'x1',
      purchaseDate: DateTime(2026, 9, 25),
      categoryCode: 'liquor_monthly',
      supplierName: '示範酒商',
      amount: 2000,
      paidBy: 'vendor',
      reconciled: true,
      source: 'import',
    ),
    Purchase(
      id: 'x2',
      purchaseDate: DateTime(2026, 9, 24),
      categoryCode: 'food',
      supplierName: null,
      memo: '示範食材',
      amount: 3000,
      paidBy: 'vendor',
      reconciled: true,
      source: 'import',
    ),
    Purchase(
      id: 'x3',
      purchaseDate: DateTime(2026, 9, 30),
      categoryCode: 'petty_misc',
      memo: '運費',
      amount: 300,
      paidBy: 'petty_cash',
      reconciled: false,
      source: 'import',
    ),
    // 月結廠商區塊的示範（同一類別多家廠商、同一家多筆）
    Purchase(
      id: 'x4',
      purchaseDate: DateTime(2026, 9, 12),
      categoryCode: 'food',
      supplierName: '示範水果行',
      amount: 1200,
      paidBy: 'vendor',
      reconciled: true,
      source: 'import',
    ),
    Purchase(
      id: 'x5',
      purchaseDate: DateTime(2026, 9, 26),
      categoryCode: 'food',
      supplierName: '示範水果行',
      amount: 800,
      paidBy: 'vendor',
      reconciled: false,
      source: 'import',
    ),
    Purchase(
      id: 'x6',
      purchaseDate: DateTime(2026, 9, 18),
      categoryCode: 'liquor_monthly',
      supplierName: '示範酒商',
      amount: 5400,
      paidBy: 'vendor',
      reconciled: false,
      source: 'import',
    ),
    Purchase(
      id: 'x8',
      purchaseDate: DateTime(2026, 9, 20),
      categoryCode: 'liquor_monthly',
      supplierName: '示範酒商(退酒)',
      amount: -580,
      paidBy: 'vendor',
      reconciled: true,
      source: 'import',
    ),
    Purchase(
      id: 'x7',
      purchaseDate: DateTime(2026, 9, 20),
      categoryCode: 'food',
      supplierName: '示範肉品行',
      amount: 4600,
      paidBy: 'vendor',
      reconciled: false,
      source: 'import',
    ),
    // 這個月的示範（依日期看每一筆、待確認用）
    Purchase(
      id: 'y1',
      purchaseDate: _daysAgo(1),
      categoryCode: 'yc_drink',
      supplierName: '示範酒商A',
      memo: '示範正職',
      amount: 6300,
      paidBy: 'vendor',
      reconciled: false,
      source: 'app',
    ),
    Purchase(
      id: 'y2',
      purchaseDate: _daysAgo(1),
      categoryCode: 'yc_food',
      supplierName: '全聯 檸檬',
      memo: '示範正職',
      amount: 186,
      paidBy: 'petty_cash',
      reconciled: false,
      source: 'app',
      noReceipt: true,
    ),
    Purchase(
      id: 'y3',
      purchaseDate: _daysAgo(4),
      categoryCode: 'yc_drink',
      supplierName: '示範酒商B',
      amount: 4200,
      paidBy: 'vendor',
      reconciled: true,
      source: 'import',
    ),
    Purchase(
      id: 'y4',
      purchaseDate: _daysAgo(5),
      categoryCode: 'yc_food',
      supplierName: '示範水果行',
      amount: 1260,
      paidBy: 'vendor',
      reconciled: false,
      source: 'import',
    ),
    Purchase(
      id: 'y5',
      purchaseDate: _daysAgo(9),
      categoryCode: 'yc_misc',
      supplierName: '衛生廚房用品',
      memo: '示範正職',
      amount: 628,
      paidBy: 'petty_cash',
      reconciled: false,
      source: 'app',
      excelCovered: true,
    ),
  ];
  final _counts = <StockCount>[];
  final _lines = <String, Map<String, double>>{};

  bool get _isStaff => _email.contains('staff');
  bool get _isManager =>
      !_isStaff && _email.contains('manager'); // 示範店長：看不到自己那列（薪資第一列假裝是他）
  bool get _isKiosk =>
      _email.contains('kiosk'); // 示範打卡用帳號（兼職權限）：帳號含 kiosk（含 xc＝小城外）
  bool get _kioskXc => _isKiosk && _email.contains('xc');

  @override
  Stream<bool> get signedInChanges => _auth.stream;
  @override
  bool get isSignedIn => _signedIn;
  @override
  String? get currentUserId =>
      _signedIn ? (_isKiosk ? 'demo-kiosk' : 'demo-user') : null;
  @override
  String? get currentUserEmail => _email;

  @override
  Future<void> signIn(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _email = email;
    _signedIn = true;
    _auth.add(true);
  }

  @override
  Future<List<VendorSlip>> vendorSlips(String storeId, DateTime month) async =>
      [
        VendorSlip(
            'v1',
            '示範酒商',
            'D-001',
            DateTime(month.year, month.month, 1),
            1300,
            null,
            [
              VendorSlipLine(1, 'A01', '示範琴酒 700ML', 1, '瓶', 900, 900),
              VendorSlipLine(2, 'A02', '示範蘇打水 24入', 1, '箱', 400, 400),
            ],
          )
          ..categoryCode = 'liquor_monthly'
          ..filer = 'Eason',
        VendorSlip(
          'v2',
          '示範食材行',
          'F-002',
          DateTime(month.year, month.month, 2),
          850,
          null,
          [VendorSlipLine(1, null, '示範牛肉片', 2, '包', 425, 850)],
        )..categoryCode = 'food',
        VendorSlip(
            'v3',
            '示範雜貨',
            'M-003',
            DateTime(month.year, month.month, 3),
            320,
            null,
            [],
          )
          ..categoryCode = 'petty_misc'
          ..paidBy = 'petty_cash'
          ..filer = '小郭',
      ];
  @override
  Future<List<String>> failedSlipFiles(String storeId) async => [];
  @override
  Future<String> saveVendorSlip(String storeId, VendorSlip slip) async =>
      slip.id.isEmpty ? 'v-new' : slip.id;
  @override
  Future<void> deleteVendorSlip(String slipId) async {}

  @override
  Future<List<String>> excelVendorNames(String storeId) async => [
    '示範酒商A',
    '示範酒商B',
    '示範水果行',
  ];
  @override
  Future<List<String>> memberNames(String storeId) async => [
    '示範老闆',
    '示範店長',
    '示範正職',
  ];
  @override
  Future<VendorHints> vendorHints(String storeId) async => (
    vendor: {
      'yc_drink': ['示範酒商A', '示範酒商B'],
    },
    petty: {
      'yc_misc': ['示範五金行'],
    },
  );

  @override
  Future<ShiftMonth> shiftMonth(String storeId, DateTime month) async {
    // 示範班表：這個月以前排好了；下個月以後是空的，可以試「自動排班」
    final m = DateTime(month.year, month.month, 1);
    final now = DateTime.now();
    final future = m.isAfter(DateTime(now.year, now.month, 1));
    final days = DateTime(m.year, m.month + 1, 0).day;
    final key = '${m.year}-${m.month}';
    const fulls = ['阿明', '小安', '阿哲'];
    const parts = {
      '小魚': {5, 6},
      '阿凱': {6, 7},
      '芳芳': {3, 4},
      '小白': {5, 6, 7},
      '阿樂': {1, 2, 4},
    };
    final marks = <String, Map<int, String>>{};
    if (_demoShifts.containsKey(key)) {
      marks.addAll({
        for (final e in _demoShifts[key]!.entries) e.key: {...e.value},
      });
    } else if (!future) {
      for (final (i, _) in fulls.indexed) {
        marks['f$i'] = {
          for (var d = 1; d <= days; d++) d: ((d + i * 2) % 7) < 2 ? '休' : 'V',
        };
      }
      for (final (i, wds) in parts.values.indexed) {
        marks['p$i'] = {
          for (var d = 1; d <= days; d++)
            if (wds.contains(DateTime(m.year, m.month, d).weekday) &&
                (d + i) % 3 != 0)
              d: 'V',
        };
      }
    }
    return ShiftMonth(
      m,
      [
        // 示範全名（虛構）；小白、阿樂故意沒填，示範「沒填全名」的樣子。阿明＝登入的示範帳號，阿凱已經對應好
        for (final (i, n) in fulls.indexed)
          ShiftPerson(
            id: 'f$i',
            name: n,
            fullName: _demoFullNames[n],
            sortOrder: i,
            userId: i == 0 && !_isKiosk ? 'demo-user' : null,
            userVerified: i == 0 && !_isKiosk,
            linkId: _demoLinks['f$i'],
          ),
        for (final (i, n) in parts.keys.indexed)
          ShiftPerson(
            id: 'p$i',
            name: n,
            fullName: _demoFullNames[n],
            kind: 'part',
            sortOrder: 10 + i,
            userId: i == 1 ? 'u2' : null,
            userVerified: i == 1,
            linkId: _demoLinks['p$i'],
          ),
      ],
      marks,
      future ? const {} : const {3: '月會日'},
      {
        if (!future || _demoOff.containsKey(key))
          for (final (i, _) in fulls.indexed)
            'f$i': ShiftStats(
              shouldOff: _demoOff[key]?['f$i'] ?? 9,
              prevUnused: 3,
            ),
      },
      [...?_demoPhotos[key]],
      _demoDrafts[key],
      ShiftOptions([..._markOpts]),
    );
  }

  final _demoShifts =
      <String, Map<String, Map<int, String>>>{}; // 示範：公布過的班表（只存在記憶體）
  final _demoOff = <String, Map<String, double>>{};
  final _markOpts = <ShiftMarkOption>[
    const ShiftMarkOption(id: 'r1', kind: 'range', mark: '18:00-00:30'),
    const ShiftMarkOption(id: 'r2', kind: 'range', mark: '19:00-01:30'),
  ];
  @override
  Future<void> saveShiftMarkOption(String storeId, ShiftMarkOption o) async {
    _markOpts.removeWhere((x) => x.id == o.id && o.id.isNotEmpty);
    _markOpts.add(
      ShiftMarkOption(
        id: o.id.isEmpty ? '${DateTime.now().microsecondsSinceEpoch}' : o.id,
        kind: o.kind,
        mark: o.mark,
        timeRange: o.timeRange,
      ),
    );
  }

  @override
  Future<void> deleteShiftMarkOption(String id) async =>
      _markOpts.removeWhere((x) => x.id == id);
  @override
  Future<void> setShiftMarkOptionHidden(String id, bool hidden) async {
    final i = _markOpts.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final o = _markOpts[i];
    _markOpts[i] = ShiftMarkOption(
      id: o.id,
      kind: o.kind,
      mark: o.mark,
      timeRange: o.timeRange,
      sortOrder: o.sortOrder,
      hidden: hidden,
    );
  }

  // 0113 示範：修改紀錄、還原、指定帳號
  @override
  Future<List<ShiftChange>> shiftChangeHistory(
    String storeId,
    DateTime month,
  ) async {
    final at = DateTime(month.year, month.month, 1, 13, 12);
    return [
      ShiftChange(
        changeId: 'c2',
        at: at.add(const Duration(days: 6, hours: 3)),
        actorName: '示範店長',
        source: 'manual',
        personId: 'f1',
        workDate: DateTime(month.year, month.month, 19),
        before: 'V',
        after: '休',
      ),
      for (var d = 1; d <= 3; d++)
        ShiftChange(
          changeId: 'c1',
          at: at,
          actorName: '示範老闆',
          source: 'photo',
          personId: 'f0',
          workDate: DateTime(month.year, month.month, d),
          before: null,
          after: 'V',
        ),
    ];
  }

  @override
  Future<int> undoShiftChange(String storeId, String changeId) async => 1;
  @override
  Future<void> assignShiftAccount(String personId, String? userId) async {}

  // 0098 示範：兩家店同一個人。隱城的「小安」已經連到小城外的「陳怡安」，其他人可以試著連
  final _demoLinks = <String, String>{'f1': 'L1', 'xf1': 'L1'};
  static const _demoXcPeople = [
    ('xf0', '阿豪', '吳俊豪', 'full'),
    ('xf1', '怡安', '陳怡安', 'full'),
    ('xf2', '小魚', '余曉雯', 'part'),
    ('xf3', '阿德', null, 'part'),
  ];
  @override
  Future<List<ShiftLinkStore>> shiftLinkStores(String storeId) async {
    // 只有兩家店都是老闆的人看得到（示範：隱城老闆身分；正職、店長、打卡帳號、新開的店都沒有）
    if (storeId != 'yc' || _isStaff || _isManager || _isKiosk || _isNew)
      return const [];
    return [
      ShiftLinkStore(
        storeId: 'xc',
        storeName: '小城外',
        people: [
          for (final (i, (id, nick, full, kind)) in _demoXcPeople.indexed)
            ShiftPerson(
              id: id,
              name: nick,
              fullName: full,
              kind: kind,
              sortOrder: i,
              linkId: _demoLinks[id],
            ),
        ],
      ),
    ];
  }

  @override
  Future<void> linkShiftPeople(String personId, String otherPersonId) async {
    if (_isStaff || _isManager) throw Exception('message: 只有兩家店的老闆能連結,');
    final a = _demoLinks[personId], b = _demoLinks[otherPersonId];
    if (a != null && b != null && a != b)
      throw Exception('message: 同一家店已經有另一個人連到這個人了，請先解除,');
    final v = a ?? b ?? 'L${DateTime.now().microsecondsSinceEpoch}';
    _demoLinks[personId] = v;
    _demoLinks[otherPersonId] = v;
  }

  @override
  Future<void> unlinkShiftPerson(String personId) async {
    if (_isStaff || _isManager) throw Exception('message: 只有老闆能解除連結,');
    final v = _demoLinks.remove(personId);
    if (v == null) return;
    final rest = [
      for (final e in _demoLinks.entries)
        if (e.value == v) e.key,
    ];
    if (rest.length < 2) rest.forEach(_demoLinks.remove);
  }

  /// 示範資料裡寫死的暱稱 → 顯示用的名字（全名），跟正式版從資料庫讀回來後的換法一樣
  String _dn(String id, String nick) => personLabel(nick, _demoFullNames[nick]);
  static const _demoFullNames = {
    '阿明': '林志明',
    '小安': '陳怡安',
    '阿哲': '張哲瑋',
    '小魚': '余曉雯',
    '阿凱': '王凱文',
    '芳芳': '李芳芳',
  };
  @override
  Future<List<ShiftAccountCandidate>> shiftAccountCandidates(
    String storeId,
  ) async => [
    ShiftAccountCandidate(
      userId: 'demo-user',
      name: _isManager ? '示範店長' : '示範帳號',
      role: _isManager ? 'manager' : 'owner',
      personId: 'f0',
      personName: '阿明',
      verified: true,
    ),
    const ShiftAccountCandidate(userId: 'u3', name: '小安的帳號', role: 'staff'),
    const ShiftAccountCandidate(userId: 'u4', name: '阿哲的帳號', role: 'staff'),
    const ShiftAccountCandidate(
      userId: 'u2',
      name: '阿凱的帳號',
      role: 'parttime',
      personId: 'p1',
      personName: '阿凱',
      verified: true,
    ),
    const ShiftAccountCandidate(userId: 'u5', name: '小魚的帳號', role: 'parttime'),
  ];
  @override
  Future<void> setShift(
    String storeId,
    String personId,
    DateTime date,
    String? mark,
  ) async {}
  @override
  Future<void> setShiftNote(
    String storeId,
    DateTime date,
    String? note,
  ) async {}
  @override
  Future<void> saveShiftPerson(
    String storeId,
    ShiftPerson p, {
    bool isNew = false,
  }) async {}
  @override
  Future<void> saveShiftStats(
    String storeId,
    String personId,
    DateTime month,
    ShiftStats s,
  ) async {
    if (s.shouldOff != null)
      _demoOff.putIfAbsent('${month.year}-${month.month}', () => {})[personId] =
          s.shouldOff!;
  }
  // 示範：上傳的班表照片與辨識草稿（只存在記憶體）。公版那一份（SELF_SIGNUP）示範 api 模式：上傳完直接辨識
  final _demoPhotos = <String, List<ShiftPhoto>>{};
  final _demoDrafts = <String, ShiftDraft>{};
  @override
  Future<void> uploadShiftPhoto(String storeId, DateTime month, Uint8List jpeg) async {
    final key = '${month.year}-${month.month}';
    final list = _demoPhotos.putIfAbsent(key, () => []);
    list.add(ShiftPhoto('ph${list.length + 1}', 'demo/schedules/$key-${list.length + 1}.jpg', DateTime.now()));
    _demoDrafts[key] = ShiftDraft(id: 'dr-$key-${list.length}', status: 'pending', createdAt: DateTime.now(),
        message: AppConfig.selfSignup ? '' : null);
  }
  @override
  Future<String> shiftPhotoAiMode(String storeId) async => AppConfig.selfSignup ? 'api' : 'subscription';
  @override
  Future<int?> readShiftPhotos(String storeId, DateTime month) async {
    final key = '${month.year}-${month.month}';
    final old = _demoDrafts[key];
    if (old == null || !old.isPending) throw Exception('message: 這個月沒有待辨識的照片,');
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final days = DateTime(month.year, month.month + 1, 0).day;
    final entries = <String, Map<int, String>>{
      '阿明': {for (var d = 1; d <= days; d++) d: d % 7 < 2 ? '休' : 'V'},
      '小安': {for (var d = 1; d <= days; d++) d: (d + 3) % 7 < 2 ? '休' : 'V'},
      '小魚': {for (var d = 1; d <= days; d++) if (d % 3 == 0) d: 'V'},
    };
    _demoDrafts[key] = ShiftDraft(
      id: old.id,
      status: 'ready',
      createdAt: old.createdAt,
      processedAtRaw: DateTime.now().toUtc().toIso8601String(),
      photoCount: _demoPhotos[key]?.length ?? 1,
      people: const [ShiftDraftPerson('阿明', 'full'), ShiftDraftPerson('小安', 'full'), ShiftDraftPerson('小魚', 'part')],
      entries: entries,
      warnings: const ['小魚 12 號看不清楚'],
    );
    return entries.values.fold<int>(0, (a, e) => a + e.length);
  }
  @override
  Future<void> deleteShiftPhoto(String photoId) async {
    for (final e in _demoPhotos.entries) {
      e.value.removeWhere((p) => p.id == photoId);
    }
  }
  @override
  Future<int> applyShiftDraft(ShiftDraft d) async {
    _demoDrafts.removeWhere((_, v) => v.id == d.id);
    return d.cellCount;
  }
  @override
  Future<void> dismissShiftDraft(String draftId) async => _demoDrafts.removeWhere((_, v) => v.id == draftId);
  @override
  Future<String> shiftPhotoUrl(String path) async => '';

  // 自動排班（示範：只存在記憶體）
  final _shiftReq = <String, Map<int, String>>{};
  final _shiftRules = <String, ShiftRule>{};
  var _staffing = <int, StaffingNeed>{
    for (var w = 1; w <= 7; w++) w: StaffingNeed(w >= 5 && w <= 6 ? 4 : 3, 1),
  };
  final _staffDays = <int, int>{};
  var _deadline = 20;
  @override
  Future<ShiftPlanSetup> shiftPlanSetup(String storeId, DateTime month) async =>
      ShiftPlanSetup(
        staffing: _staffing,
        specialDays: _staffDays,
        deadline: _deadline,
        rules: _shiftRules,
        requests: _shiftReq,
        pairRules: [..._pairRules],
        preferRun: _preferRun,
        offPerDay: _offPerDay,
        offMonthMax: _offMonthMax,
      );
  final _pairRules = <PairRule>[];
  @override
  Future<void> addShiftPairRule(
    String storeId,
    String a,
    String b,
    String kind,
  ) async => _pairRules.add(
    PairRule(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      a: a,
      b: b,
      kind: kind,
    ),
  );
  @override
  Future<void> deleteShiftPairRule(String id) async =>
      _pairRules.removeWhere((r) => r.id == id);
  @override
  Future<Map<int, Set<String>>?> shiftOffTaken(
    String storeId,
    DateTime month,
  ) async => null; // App 自己算
  final Map<String, double> _leaveAdj = {};
  @override
  Future<Map<String, SpecialLeave>?> specialLeaveStatus(
    String storeId,
    DateTime month,
  ) async {
    final d = await shiftMonth(storeId, month);
    final now = DateTime.now();
    return {
      for (final p in d.people.where((p) => p.isFull))
        p.id: SpecialLeave(
          start: DateTime(2026, 11, 1),
          balance: (_leaveAdj[p.id] ?? 7) - d.leaveDays(p.id),
          usedInMonth: d.leaveDays(p.id),
          nextGrantDate: p.hireDate == null
              ? null
              : lsaSpecialGrants(p.hireDate!)
                    .map((g) => g.$1)
                    .where((x) => x.isAfter(now))
                    .firstOrNull,
          nextGrantDays: p.hireDate == null
              ? null
              : lsaSpecialGrants(p.hireDate!)
                    .where((g) => g.$1.isAfter(now))
                    .firstOrNull
                    ?.$2
                    .toDouble(),
        ),
    };
  }

  @override
  Future<bool> payrollAccess(String storeId) async => true;
  @override
  Future<void> setSpecialLeave(
    String personId,
    double balance, {
    String? note,
  }) async => _leaveAdj[personId] = balance;
  @override
  Future<void> setShiftRequest(
    String storeId,
    String personId,
    DateTime date,
    String? kind,
  ) async {
    final m = _shiftReq.putIfAbsent(personId, () => {});
    if (kind == null) {
      m.remove(date.day);
    } else {
      m[date.day] = kind;
    }
  }

  @override
  Future<void> saveShiftRule(String storeId, ShiftRule r) async =>
      _shiftRules[r.personId] = r;
  @override
  Future<void> saveShiftStaffing(
    String storeId,
    Map<int, StaffingNeed> staffing,
  ) async => _staffing = {...staffing};
  @override
  Future<void> setShiftStaffingDay(
    String storeId,
    DateTime day,
    int? need,
  ) async {
    if (need == null) {
      _staffDays.remove(day.day);
    } else {
      _staffDays[day.day] = need;
    }
  }

  @override
  Future<void> saveShiftDeadline(String storeId, int day) async =>
      _deadline = day;
  @override
  Future<int> applyShiftPlan(
    String storeId,
    DateTime month,
    Map<String, Map<int, String>> plan, {
    String? expected,
  }) async {
    _planDrafts.remove('$storeId|${month.year}-${month.month}');
    _demoShifts['${month.year}-${month.month}'] = {
      for (final e in plan.entries) e.key: {...e.value},
    };
    return plan.values.fold<int>(0, (a, m) => a + m.length);
  }

  final _planDrafts = <String, ShiftPlanDraft>{};
  int? _preferRun = 5;
  @override
  Future<String> shiftMonthVersion(String storeId, DateTime month) async => '';
  @override
  Future<ShiftPlanDraft?> shiftPlanDraft(
    String storeId,
    DateTime month,
  ) async => _planDrafts['$storeId|${month.year}-${month.month}'];
  @override
  Future<void> saveShiftPlanDraft(
    String storeId,
    DateTime month,
    Map<String, Map<int, String>> plan,
    Map<String, Set<int>> locked,
  ) async =>
      _planDrafts['$storeId|${month.year}-${month.month}'] = ShiftPlanDraft(
        {
          for (final e in plan.entries) e.key: {...e.value},
        },
        {
          for (final e in locked.entries) e.key: {...e.value},
        },
        '示範老闆',
        DateTime.now(),
      );
  @override
  Future<void> deleteShiftPlanDraft(String storeId, DateTime month) async =>
      _planDrafts.remove('$storeId|${month.year}-${month.month}');
  @override
  Future<void> saveShiftPreferRun(String storeId, int? days) async =>
      _preferRun = days;
  int? _offPerDay = shiftOffPerDayDefault;
  int? _offMonthMax = shiftOffMonthMaxDefault;
  @override
  Future<void> saveShiftOffLimits(
    String storeId,
    int? perDay,
    int? monthMax,
  ) async {
    _offPerDay = perDay;
    _offMonthMax = monthMax;
  }

  @override
  Future<String> remindShiftRequests(String storeId, DateTime month) async =>
      '（示範）${month.month} 月班表要開始排了';

  // 交接・提醒（示範：只存在記憶體）
  final _notes = <HandoverNote>[];
  final _reminders = <WorkReminder>[];
  final _done = <String, ReminderDone>{};
  @override
  Future<HandoverBoard> handoverBoard(
    String storeId, {
    bool withSchedule = false,
  }) async {
    final sm = withSchedule ? await shiftMonth(storeId, bizToday()) : null;
    return HandoverBoard(
      [..._notes.reversed],
      [..._reminders],
      {..._done},
      sm?.people ?? const [],
      {
        for (final p in sm?.people ?? const <ShiftPerson>[])
          p.id: sm!.mark(p.id, bizToday().day),
      },
    );
  }

  HandoverNote _copyNote(
    HandoverNote n, {
    String? body,
    List<HandoverItem>? items,
    DateTime? resolvedAt,
    bool setResolved = false,
    bool edited = false,
    bool? important,
  }) => HandoverNote(
    id: n.id,
    body: body ?? n.body,
    photoPath: n.photoPath,
    authorId: n.authorId,
    authorName: n.authorName,
    createdAt: n.createdAt,
    resolvedAt: setResolved ? resolvedAt : n.resolvedAt,
    resolvedName: setResolved
        ? (resolvedAt == null ? null : '示範老闆')
        : n.resolvedName,
    readers: n.readers,
    editedAt: edited ? DateTime.now() : n.editedAt,
    editedName: edited ? '示範老闆' : n.editedName,
    items: items ?? n.items,
    important: important ?? n.important,
  );
  @override
  Future<void> addHandover(
    String storeId,
    String body,
    List<String> items,
    Uint8List? jpeg, {
    bool important = false,
  }) async => _notes.add(
    HandoverNote(
      id: 'n${_seq++}',
      body: body,
      authorId: 'demo-user',
      authorName: '示範老闆',
      createdAt: DateTime.now(),
      important: important,
      items: [
        for (var i = 0; i < items.length; i++)
          HandoverItem(id: 'i${_seq++}', position: i + 1, body: items[i]),
      ],
    ),
  );
  final _lineOn = <String, bool>{};
  var _lineLinks = 0;
  @override
  Future<int> lineOwnerLinks() async => _lineLinks;
  @override
  Future<void> linkLineOwner(String code) async {
    if (code.trim().length != 6)
      throw Exception('message: 代碼不對或已過期，請在 LINE 私訊機器人重新打「綁定」,');
    _lineLinks = 1;
  }

  @override
  Future<void> unlinkLineOwner() async => _lineLinks = 0;
  // 0156：示範版——小城外假裝已經綁好群組，其他店還沒綁
  @override
  Future<bool> lineGroupBound(String storeId) async => storeId == 'xc';
  @override
  Future<LineBindCode> createLineGroupBindCode(String storeId) async =>
      LineBindCode((DateTime.now().millisecondsSinceEpoch % 100000000).toString().padLeft(8, '0'),
          DateTime.now().add(const Duration(minutes: 10)));
  @override
  Future<bool> lineNotifyEnabled(String storeId) async =>
      _lineOn[storeId] ?? true;
  @override
  Future<void> saveLineNotifyEnabled(String storeId, bool on) async =>
      _lineOn[storeId] = on;
  @override
  Future<void> updateHandover(
    String noteId,
    String body,
    List<String> items, {
    bool? important,
  }) async {
    final i = _notes.indexWhere((n) => n.id == noteId);
    final n = _notes[i];
    final left = [...n.items];
    final next = <HandoverItem>[];
    for (var k = 0; k < items.length; k++) {
      final j = left.indexWhere((x) => x.body == items[k]);
      final old = j < 0 ? null : left.removeAt(j);
      next.add(
        HandoverItem(
          id: old?.id ?? 'i${_seq++}',
          position: k + 1,
          body: items[k],
          doneAt: old?.doneAt,
          doneName: old?.doneName,
        ),
      );
    }
    _notes[i] = _copyNote(
      n,
      body: body,
      items: next,
      edited: body != n.body,
      important: important,
    );
  }

  @override
  Future<void> setHandoverItemDone(String itemId, bool done) async {
    final i = _notes.indexWhere((n) => n.items.any((x) => x.id == itemId));
    final n = _notes[i];
    if (n.resolved) throw Exception('message: 這則交接已處理，要改清單請先按「改回未處理」,');
    _notes[i] = _copyNote(
      n,
      items: [
        for (final x in n.items)
          x.id == itemId
              ? HandoverItem(
                  id: x.id,
                  position: x.position,
                  body: x.body,
                  doneAt: done ? DateTime.now() : null,
                  doneName: done ? '示範老闆' : null,
                )
              : x,
      ],
    );
  }

  @override
  Future<void> setHandoverResolved(String noteId, bool resolved) async {
    final i = _notes.indexWhere((n) => n.id == noteId);
    final n = _notes[i];
    if (resolved && n.itemsLeft > 0)
      throw Exception('message: 清單還有 ${n.itemsLeft} 項沒打勾，全部完成才能按已處理,');
    _notes[i] = _copyNote(
      n,
      resolvedAt: resolved ? DateTime.now() : null,
      setResolved: true,
    );
  }

  @override
  Future<void> markHandoverRead(String storeId, List<String> noteIds) async {}
  @override
  Future<void> deleteHandover(String noteId) async =>
      _notes.removeWhere((n) => n.id == noteId);
  DateTime? _notifSeen;
  @override
  Future<NotificationFeed> notifications(String storeId) async {
    final now = DateTime.now();
    return NotificationFeed([
      AppNotification(
        id: 3,
        kind: 'schedule',
        title: '班表更新',
        body: '${now.month} 月班表有 3 處修改',
        refMonth: DateTime(now.year, now.month),
        actorName: '示範店長',
        createdAt: now.subtract(const Duration(minutes: 20)),
      ),
      AppNotification(
        id: 2,
        kind: 'reminder',
        title: '新提醒',
        body: '跟大倉捷叫貨',
        actorName: '示範正職',
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      AppNotification(
        id: 1,
        kind: 'handover',
        title: '新交接',
        body: '冰塊機漏水，已叫修',
        actorName: '示範正職',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ], _notifSeen);
  }

  @override
  Future<void> markNotificationsSeen(String storeId) async =>
      _notifSeen = DateTime.now();
  @override
  Future<void> saveReminder(
    String storeId,
    WorkReminder r, {
    bool isNew = false,
  }) async {
    final x = WorkReminder(
      id: isNew ? 'r${_seq++}' : r.id,
      title: r.title,
      detail: r.detail,
      repeat: r.repeat,
      dueDate: r.dueDate,
      weekday: r.weekday,
      monthDay: r.monthDay,
      startDate: isNew ? bizToday() : r.startDate,
      assignPersonId: r.assignPersonId,
      assignOnShift: r.assignOnShift,
      active: r.active,
      createdBy: isNew ? currentUserId : r.createdBy,
    );
    _reminders.removeWhere((e) => e.id == x.id);
    _reminders.add(x);
  }

  @override
  Future<void> deleteReminder(String reminderId) async =>
      _reminders.removeWhere((e) => e.id == reminderId);
  @override
  Future<void> setReminderDone(
    String storeId,
    String reminderId,
    DateTime occurrence,
    bool done,
  ) async {
    final k = ReminderDone.keyOf(reminderId, occurrence);
    if (done) {
      _done[k] = ReminderDone(
        reminderId,
        occurrence,
        'demo-user',
        '示範老闆',
        DateTime.now(),
      );
    } else {
      _done.remove(k);
    }
  }

  @override
  Future<bool> signUp(String email, String password) async {
    await signIn(email, password);
    return true;
  }

  final _demoMembers = [
    MemberInfo(
      userId: 'demo-user',
      displayName: '示範老闆',
      role: Role.owner,
      active: true,
      email: 'owner@demo',
    ),
    MemberInfo(
      userId: 'u2',
      displayName: '示範店長',
      role: Role.manager,
      active: true,
      email: 'manager@demo',
    ),
    MemberInfo(
      userId: 'u3',
      displayName: '示範員工',
      role: Role.staff,
      active: true,
      email: 'staff@demo',
    ),
  ];
  final _demoInvites = <MemberInvite>[];
  @override
  Future<int> claimInvite(String code) async => -1;
  // 示範自助註冊：帳號含 new＝還沒有任何店；建好之後這次登入就有一家店
  bool get _isNew => _email.contains('new');
  Membership? _newStore;
  @override
  Future<String> signupCreateStore(String storeName, String displayName, {String? kind}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (const ['隱城', '小城外'].contains(storeName.trim())) {
      throw Exception('message: SIGNUP_TAKEN：這個店名已經有人用了，請換一個（例如加上地區或分店名）');
    }
    _newStore = Membership(storeId: 'demo-new', storeName: storeName.trim(), role: Role.owner, displayName: displayName.trim());
    if (kind != null) {
      // 示範：新店照範本帶入（同資料庫 0152：人力、班別／時段、設定，打開班表分頁）
      _staffing = {};
      _markOpts.clear();
      await applyShiftTemplate('demo-new', kind);
    }
    return 'demo-new';
  }

  @override
  Future<void> applyShiftTemplate(String storeId, String kind) async {
    final t = shiftTemplates.where((x) => x.kind == kind).firstOrNull;
    if (t == null) throw Exception('message: SHIFT_TEMPLATE_KIND：不認得這種店的類型');
    if (_staffing.isNotEmpty || _markOpts.isNotEmpty) {
      throw Exception('message: SHIFT_TEMPLATE_USED：這家店已經有班表或排班設定了，範本只能套在全新的店（請直接在排班條件裡改）');
    }
    _staffing = {for (var w = 1; w <= 7; w++) w: StaffingNeed(t.staffing[w - 1].$1, t.staffing[w - 1].$2)};
    var n = 0;
    for (final c in t.codes) {
      n++;
      _markOpts.add(ShiftMarkOption(id: 'tpl$n', kind: 'code', mark: c.$1, timeRange: c.$2, sortOrder: n));
    }
    for (final r in t.ranges) {
      n++;
      _markOpts.add(ShiftMarkOption(id: 'tpl$n', kind: 'range', mark: r, sortOrder: n));
    }
    _preferRun = kind == 'other' ? null : 5;
    final name = _newStore?.storeId == storeId ? _newStore!.storeName : null;
    if (name != null) StoreFeatures.remember(name, StoreFeatures(schedule: true, shiftCodes: t.codes.isNotEmpty));
  }
  @override
  Future<String> createInvite(List<String> storeIds, Role role, String name) async {
    _onboardInvites++;
    _demoInvites.insert(0, MemberInvite(id: 'i${_demoInvites.length}', displayName: name, role: role,
        createdAt: DateTime.now(), expiresAt: DateTime.now().add(const Duration(days: 14))));
    return 'DEMO2-CODE9';
  }

  @override
  Future<List<MemberInfo>> storeMembers(String storeId) async =>
      List.of(_demoMembers);
  @override
  Future<List<MemberInvite>> openInvites(String storeId) async =>
      List.of(_demoInvites);
  @override
  Future<void> revokeInvite(String inviteId) async =>
      _demoInvites.removeWhere((i) => i.id == inviteId);
  @override
  Future<void> updateMember(
    String storeId,
    String userId, {
    Role? role,
    bool? active,
  }) async {
    final i = _demoMembers.indexWhere((m) => m.userId == userId);
    final m = _demoMembers[i];
    _demoMembers[i] = MemberInfo(
      userId: m.userId,
      displayName: m.displayName,
      role: role ?? m.role,
      active: active ?? m.active,
      email: m.email,
    );
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _newStore = null;
    _auth.add(false);
  }

  // 示範模式不存上次資料
  @override
  List<Membership>? peekMemberships() => null;
  @override
  MonthlySummary? peekMonthlySummary(String storeId, DateTime month) => null;
  @override
  List<DailyRevenue>? peekDailyRevenueBetween(
    String storeId,
    DateTime from,
    DateTime to,
  ) => null;
  @override
  FixedCosts? peekFixedCosts(String storeId, DateTime month) => null;
  @override
  List<ExpenseItem>? peekExpenseItems(String storeId, DateTime month) => null;
  @override
  List<RecurringExpenseItem>? peekRecurringExpenseItems(String storeId) => null;
  @override
  double? peekCardFeeRate(String storeId) => null;
  @override
  (double?,)? peekPettyCashBalance(String storeId) => null;

  @override
  Future<List<Membership>> myMemberships() async => _isNew
      ? [if (_newStore != null) _newStore!]
      : _isKiosk
      ? [
          _kioskXc
              ? Membership(
                  storeId: 'xc',
                  storeName: '小城外',
                  role: Role.parttime,
                  displayName: '示範公用帳號',
                )
              : Membership(
                  storeId: 'yc',
                  storeName: '隱城',
                  role: Role.parttime,
                  displayName: '示範公用帳號',
                ),
        ]
      : [
          Membership(
            storeId: 'yc',
            storeName: '隱城',
            role: _isStaff
                ? Role.staff
                : (_isManager ? Role.manager : Role.owner),
            displayName: '示範',
          ),
          Membership(
            storeId: 'xc',
            storeName: '小城外',
            role: Role.staff,
            displayName: '示範',
          ),
        ];

  // 依店別分開存（示範用）：yc 有兩筆 Excel 匯入；xc 一開始沒有
  final _revenue = <String, List<RevenueEntry>>{
    'yc': [
      ..._recent,
      RevenueEntry(
        id: 'r1',
        bizDate: DateTime(2026, 9, 30),
        cash: 8000,
        creditCard: 20000,
        guests: 28,
        drinks: 24000,
        food: 4000,
        source: 'import',
      ),
      RevenueEntry(
        id: 'r2',
        bizDate: DateTime(2026, 9, 29),
        cash: 5000,
        creditCard: 16000,
        amex: 1000,
        guests: 21,
        drinks: 18000,
        food: 4000,
        source: 'import',
      ),
    ],
    'xc': [],
  };
  // 當月示範（2026-11-13，讓「當月銷售品項累計」有東西看）：昨天往回 5 天，前 4 天有 iCHEF、最早那天沒有（顯示「未計入」）
  static final _recent = [
    for (final (i, cash, card, guests, drinks, food) in const [
      (1, 3655.0, 11402.0, 17, 13746.0, 1311.0),
      (2, 4200.0, 15800.0, 22, 17300.0, 2700.0),
      (3, 3100.0, 12900.0, 18, 13900.0, 2100.0),
      (4, 2800.0, 9200.0, 13, 10400.0, 1600.0),
      (5, 3000.0, 10000.0, 15, 11500.0, 1500.0),
    ])
      RevenueEntry(
        id: 'rc$i',
        bizDate: bizToday().subtract(Duration(days: i)),
        cash: cash,
        creditCard: card,
        guests: guests,
        drinks: drinks,
        food: food,
        source: 'import',
      ),
  ];
  static final _noIchef = {'rc5'};
  List<RevenueEntry> _revList(String storeId) => _revenue[storeId] ??= [];

  @override
  Future<List<RevenueEntry>> revenueEntries(
    String storeId, {
    int limit = 60,
  }) async {
    // 0020：正職也看得到營收
    return List.of(_revList(storeId))
      ..sort((a, b) => b.bizDate.compareTo(a.bizDate));
  }

  @override
  Future<List<RevenueEntry>> revenueEntriesBetween(
    String storeId,
    DateTime from,
    DateTime to,
  ) async => [
    for (final e in await revenueEntries(storeId))
      if (!e.bizDate.isBefore(from) && !e.bizDate.isAfter(to)) e,
  ];

  @override
  Future<DateTime?> firstRevenueDate(String storeId) async =>
      (await revenueEntries(storeId))
          .map((e) => e.bizDate)
          .fold<DateTime?>(null, (a, d) => a == null || d.isBefore(a) ? d : a);

  @override
  Future<RevenueEntry?> revenueEntryFor(
    String storeId,
    DateTime bizDate,
  ) async {
    for (final e in _revList(storeId)) {
      if (e.bizDate.year == bizDate.year &&
          e.bizDate.month == bizDate.month &&
          e.bizDate.day == bizDate.day)
        return e;
    }
    return null;
  }

  @override
  Future<void> saveRevenueEntry(String storeId, RevenueEntry e) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // 0038：正職只能動自己手動登記的（source=app），不能改 Excel 匯入的那筆
    if (_isStaff && e.source == 'import')
      throw Exception('message: 沒有權限執行這個動作。,');
    final saved = RevenueEntry(
      id: e.id ?? 'rev${++_seq}',
      bizDate: e.bizDate,
      cash: e.cash,
      creditCard: e.creditCard,
      amex: e.amex,
      deposit: e.deposit,
      guests: e.guests,
      drinks: e.drinks,
      food: e.food,
      project: e.project,
      coffee: e.coffee,
      ramen: e.ramen,
      note: e.note,
      source: e.source,
    );
    final list = _revList(storeId);
    list.removeWhere((x) => x.id == saved.id);
    list.add(saved);
  }

  // 示範：最近 7 筆營收有 iCHEF 品項（假資料）
  @override
  Future<Set<DateTime>> ichefDays(
    String storeId, {
    int limit = 120,
    DateTime? from,
    DateTime? to,
  }) async {
    final list = List.of(_revList(storeId))
      ..sort((a, b) => b.bizDate.compareTo(a.bizDate));
    return {
      for (final e in list.where((e) => !_noIchef.contains(e.id)).take(7))
        if ((from == null || !e.bizDate.isBefore(from)) &&
            (to == null || !e.bizDate.isAfter(to)))
          DateTime(e.bizDate.year, e.bizDate.month, e.bizDate.day),
    };
  }

  // 示範：iCHEF 現金＝那天記的現金扣掉咖啡、拉麵（表單會再加回去，跟正式資料庫一樣）
  @override
  Future<double?> ichefCash(String storeId, DateTime bizDate) async {
    final day = DateTime(bizDate.year, bizDate.month, bizDate.day);
    if (!(await ichefDays(storeId)).contains(day)) return null;
    final e = await revenueEntryFor(storeId, day);
    return e == null
        ? null
        : (e.cash - e.coffee - e.ramen).clamp(0, double.infinity).toDouble();
  }

  @override
  Future<List<ItemSale>> itemSales(String storeId, DateTime bizDate) async {
    const base = [
      ('Long Island Iced Tea', '調酒', true, 450.0),
      ('first contact', '調酒', true, 400.0),
      ('茶徑', '調酒', true, 365.0),
      ("Bee's Knees", '調酒', true, 390.0),
      ('lychee vesper', '調酒', true, 406.0),
      ('鴨油薯條', '小郭餐點', false, 238.0),
      ('煙波', '調酒', true, 380.0),
      ('梅園', '調酒', true, 420.0),
      ('Gin Fizz', '調酒', true, 385.0),
      ('關東煮', '小郭餐點', false, 280.0),
      ('Negroni', '調酒', true, 400.0),
      ('瑞士修道院起司', '起司', false, 280.0),
    ];
    final raw = [
      for (var i = 0; i < base.length; i++)
        (base[i], ((bizDate.day * 7 + i * 3) % 7 + 1).toDouble()),
    ];
    // 同正式資料庫 0101：含服務費金額依原價比例分，同區加總＝那天的酒水／餐食（最大餘數法）
    final day = DateTime(bizDate.year, bizDate.month, bizDate.day);
    final e = _revList(storeId)
        .where(
          (x) =>
              DateTime(x.bizDate.year, x.bizDate.month, x.bizDate.day) == day,
        )
        .firstOrNull;
    final list = <ItemSale>[];
    for (final drink in [true, false]) {
      final g = [
        for (final r in raw)
          if (r.$1.$3 == drink) r,
      ];
      final listSum = g.fold<double>(0, (a, r) => a + r.$1.$4 * r.$2);
      final target = e == null
          ? listSum
          : (drink ? e.drinks : e.food).roundToDouble();
      final exact = [
        for (final r in g)
          listSum == 0 ? 0.0 : target * r.$1.$4 * r.$2 / listSum,
      ];
      final net = [for (final v in exact) v.floorToDouble()];
      final order = List.generate(g.length, (i) => i)
        ..sort((a, b) => (exact[b] - net[b]).compareTo(exact[a] - net[a]));
      var rem = (target - net.fold<double>(0, (a, v) => a + v)).round();
      for (final i in order) {
        if (rem-- <= 0) break;
        net[i] += 1;
      }
      for (var i = 0; i < g.length; i++) {
        list.add(
          ItemSale(
            name: g[i].$1.$1,
            category: g[i].$1.$2,
            isDrink: drink,
            qty: g[i].$2,
            amount: net[i],
            listAmount: g[i].$1.$4 * g[i].$2,
          ),
        );
      }
    }
    return list..sort((a, b) => b.amount.compareTo(a.amount));
  }

  @override
  Future<List<ItemSale>> monthItemSales(String storeId, DateTime month) async {
    final sums = <String, ItemSale>{};
    for (final d in await ichefDays(storeId)) {
      if (d.year != month.year || d.month != month.month) continue;
      for (final x in await itemSales(storeId, d)) {
        final o = sums[x.name];
        sums[x.name] = ItemSale(
          name: x.name,
          category: x.category,
          isDrink: x.isDrink,
          qty: x.qty + (o?.qty ?? 0),
          amount: x.amount + (o?.amount ?? 0),
          listAmount: x.listAmount + (o?.listAmount ?? 0),
          days: 1 + (o?.days ?? 0),
          net: x.net && (o?.net ?? true),
        );
      }
    }
    return sums.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
  }

  @override
  Future<DateTime?> lastExcelSync(String storeId) async => storeId == 'yc'
      ? DateTime.now().subtract(const Duration(minutes: 25))
      : null;

  final _fixed = <String, double>{};

  @override
  Future<FixedCosts> fixedCosts(String storeId, DateTime month) async {
    if (_isStaff) return const FixedCosts();
    final k = '$storeId-${month.year}-${month.month}';
    return FixedCosts(rent: _fixed['$k-rent'], payroll: _fixed['$k-payroll']);
  }

  @override
  Future<void> saveFixedCost(
    String storeId,
    DateTime month,
    String category,
    double amount,
  ) async {
    if (_isStaff) throw Exception('message: 沒有權限執行這個動作。,');
    _fixed['$storeId-${month.year}-${month.month}-$category'] = amount;
  }

  @override
  Future<void> clearFixedCost(
    String storeId,
    DateTime month,
    String category,
  ) async {
    if (_isStaff) throw Exception('message: 沒有權限執行這個動作。,');
    _fixed.remove('$storeId-${month.year}-${month.month}-$category');
  }

  final _expItems = <String, List<ExpenseItem>>{}; // 店家-年月 → 明細
  String _ek(String s, DateTime m) => '$s-${m.year}-${m.month}';
  // 0076 廠商資料（示範資料，只有老闆、店長看得到）
  final _vendors = <String, List<VendorContact>>{
    'yc': [
      const VendorContact(
        id: 'v1',
        kind: 'monthly',
        name: '示範酒商',
        items: '琴酒、伏特加、蘭姆酒',
        contact: '02-0000-0000 業務 王先生',
        bank: '示範銀行 000',
        account: '000-000-000000',
        note: '週三送貨',
        billingDay: '每月 25 日',
      ),
      const VendorContact(
        id: 'v2',
        kind: 'monthly',
        name: '示範水果行',
        items: '檸檬、萊姆、柳橙',
        contact: 'LINE：demo-fruit',
        bank: '示範銀行 000',
        account: '000-000-111111',
        billingDay: '月底',
      ),
      const VendorContact(
        id: 'v3',
        kind: 'other',
        name: '示範冰塊',
        items: '方冰、碎冰',
        contact: '0900-000-000',
      ),
    ],
  };

  @override
  Future<List<VendorContact>> vendorContacts(String storeId) async {
    if (_isStaff) return [];
    return List.of(_vendors[storeId] ?? const <VendorContact>[]);
  }

  @override
  Future<void> saveVendorContact(String storeId, VendorContact v) async {
    if (_isStaff) throw Exception('message: 沒有權限修改（只有老闆、店長可以）,');
    final list = _vendors[storeId] ??= [];
    if (list.any((x) => x.name == v.name.trim() && x.id != v.id))
      throw Exception('message: 已經有同名的廠商,');
    final saved = VendorContact(
      id: v.id ?? 'v${++_seq}',
      kind: v.kind,
      name: v.name.trim(),
      items: v.items,
      contact: v.contact,
      bank: v.bank,
      account: v.account,
      note: v.note,
      billingDay: v.billingDay,
    );
    list.removeWhere((x) => x.id == saved.id);
    list.add(saved);
  }

  @override
  Future<void> deleteVendorContact(String id) async {
    if (_isStaff) throw Exception('message: 沒有權限刪除（只有老闆、店長可以）,');
    for (final l in _vendors.values) {
      l.removeWhere((x) => x.id == id);
    }
  }

  @override
  Future<List<ExpenseItem>> expenseItems(
    String storeId,
    DateTime month,
  ) async => _isStaff ? [] : [...?_expItems[_ek(storeId, month)]];
  @override
  Future<void> saveExpenseItem(
    String storeId,
    DateTime month,
    ExpenseItem item, {
    bool isNew = false,
  }) async {
    if (_isStaff) throw Exception('message: 沒有權限,');
    final list = _expItems.putIfAbsent(_ek(storeId, month), () => []);
    list.removeWhere((e) => e.id == item.id);
    list.add(
      ExpenseItem(
        id: isNew ? 'e${_seq++}' : item.id,
        name: item.name,
        category: item.category,
        amount: item.amount,
        accountId: item.accountId,
        note: item.note,
      ),
    );
  }

  @override
  Future<void> deleteExpenseItem(String itemId) async {
    for (final l in _expItems.values) {
      l.removeWhere((e) => e.id == itemId);
    }
  }

  // 0039 刷卡手續費率（預設 0.02）＋每月固定支出（示範用，依店別）
  final _cardFeeRate = <String, double>{};
  final _recurring = <String, List<RecurringExpenseItem>>{};
  @override
  Future<double> cardFeeRate(String storeId) async =>
      _cardFeeRate[storeId] ?? 0.02;
  // ops 0142 示範：隱城的科目（照老闆的損益表）
  @override
  Future<List<PlAccount>> plAccounts(String storeId) async {
    if (_isStaff) return const [];
    const names = [
      ('薪資支出', 'payroll', 'payroll_base'),
      ('保險費-勞健保+退休金', 'payroll', null),
      ('租金支出-房屋', 'rent', 'rent_base'),
      ('租金支出-租賃稅', 'rent', null),
      ('租金支出-租賃補充保費', 'rent', null),
      ('水電瓦斯費', 'misc', null),
      ('租金支出-ICHEF', 'rent', null),
      ('其他費用-垃圾清運費', 'misc', null),
      ('其他費用-雜項', 'misc', 'purchase_misc'),
      ('職工福利', 'payroll', null),
      ('廣告費', 'misc', null),
      ('郵電費', 'misc', null),
      ('修繕費', 'misc', null),
      ('保險費', 'misc', null),
      ('手續費', 'misc', 'card_fee'),
      ('會計師', 'misc', null),
      ('內帳記帳費', 'misc', null),
    ];
    return [
      for (final (i, n) in names.indexed)
        PlAccount(
          id: 'acc$i',
          name: n.$1,
          category: n.$2,
          autoKind: n.$3,
          sortOrder: i + 1,
        ),
    ];
  }

  @override
  Future<String?> plTitle(String storeId) async =>
      storeId == 'yc' ? '隱城(二店)' : null;
  @override
  Future<void> saveCardFeeRate(String storeId, double rate) async {
    if (_isStaff) throw Exception('message: 沒有權限,');
    _cardFeeRate[storeId] = rate;
  }

  @override
  Future<List<RecurringExpenseItem>> recurringExpenseItems(
    String storeId,
  ) async => _isStaff ? [] : [...?_recurring[storeId]];
  @override
  Future<void> saveRecurringExpenseItem(
    String storeId,
    RecurringExpenseItem item, {
    bool isNew = false,
  }) async {
    if (_isStaff) throw Exception('message: 沒有權限,');
    final list = _recurring.putIfAbsent(storeId, () => []);
    final old = list.where((e) => e.id == item.id).firstOrNull;
    list.removeWhere((e) => e.id == item.id);
    list.add(
      RecurringExpenseItem(
        id: isNew ? 'rc${_seq++}' : item.id,
        name: item.name,
        category: item.category,
        amount: item.amount,
        amountsFrom: old?.amountsFrom ?? const {},
        accountId: item.accountId,
        note: item.note,
      ),
    );
  }

  @override
  Future<void> setRecurringAmountFrom(
    String itemId,
    DateTime month,
    double amount,
  ) async {
    if (_isStaff) throw Exception('message: 沒有權限,');
    for (final l in _recurring.values) {
      final i = l.indexWhere((e) => e.id == itemId);
      if (i < 0) continue;
      final e = l[i];
      l[i] = RecurringExpenseItem(
        id: e.id,
        name: e.name,
        category: e.category,
        amount: e.amount,
        accountId: e.accountId,
        note: e.note,
        amountsFrom: {
          ...e.amountsFrom,
          DateTime(month.year, month.month): amount,
        },
      );
    }
  }

  @override
  Future<void> deleteRecurringExpenseItem(String itemId) async {
    for (final l in _recurring.values) {
      l.removeWhere((e) => e.id == itemId);
    }
  }

  @override
  Future<MonthlySummary> monthlySummary(String storeId, DateTime month) async {
    if (_isStaff || storeId != 'yc') {
      return MonthlySummary(
        month: month,
        revenue: 0,
        guests: 0,
        drinksRevenue: 0,
        foodRevenue: 0,
      );
    }
    // 示範：每個月來客、客單略有不同，總覽「上個月／近 3 個月平均」才看得出差異
    final now = DateTime.now();
    final cur = month.year == now.year && month.month == now.month;
    final guests = cur ? 723 : 640 + (month.month * 47) % 150;
    final ticket = cur ? 1000.0 : 930.0 + (month.month * 53) % 130;
    final revenue = (guests * ticket).roundToDouble();
    return MonthlySummary(
      month: month,
      revenue: revenue,
      guests: guests,
      avgTicket: ticket,
      dailyAvgTicket: ticket,
      drinksRevenue: (revenue * 0.84).roundToDouble(),
      foodRevenue: revenue - (revenue * 0.84).roundToDouble(),
      targetAmount: 600000,
      targetRate: 0.8333,
      drinkCostRate: 0.2200,
      foodCostRate: 0.4000,
      totalCostRate: 0.2500,
      miscCostRate: 0.0200,
      purchaseCost: 125000,
      miscCost: 10000,
      hasCostRecords: true,
    );
  }

  @override
  Future<List<DailyRevenue>> recentDailyRevenue(
    String storeId,
    int days,
  ) async {
    if (_isStaff || storeId != 'yc') return [];
    const v = [
      20000,
      10000,
      25000,
      40000,
      50000,
      20000,
      15000,
      22000,
      24000,
      45000,
      38000,
      42000,
      21000,
      30000,
    ];
    return [
      for (var i = 0; i < v.length; i++)
        DailyRevenue(
          DateTime(2026, 9, 17).add(Duration(days: i)),
          v[i].toDouble(),
          20 + i,
        ),
    ];
  }

  @override
  Future<List<DailyRevenue>> dailyRevenueBetween(
    String storeId,
    DateTime from,
    DateTime to,
  ) async {
    if (_isStaff) return [];
    // 示範資料：每天 1.2～2.8 萬
    final out = <DailyRevenue>[];
    final today = DateTime.now();
    for (
      var d = from;
      !d.isAfter(to) && !d.isAfter(today);
      d = d.add(const Duration(days: 1))
    ) {
      out.add(
        DailyRevenue(d, 12000.0 + (d.day * 3700 % 16000), 20 + d.day % 15),
      );
    }
    return out;
  }

  @override
  Future<List<Issue>> consistencyIssues(String storeId) async {
    if (_isStaff) throw Exception('message: 只有老闆或店長可以執行一致性檢查,');
    return [
      Issue('月結請款對帳', 'error', '示範食材行：金額不符（進貨 5,000／請款 4,000）'),
      Issue('月結進貨未對應廠商', 'warning', '示範：一筆進貨未對應廠商'),
    ];
  }

  @override
  Future<double?> pettyCashBalance(String storeId) async =>
      storeId == 'yc' ? 5000 : null;

  @override
  Future<DateTime> businessDate(String storeId) async {
    final now = DateTime.now();
    final d = now.hour < 6 ? now.subtract(const Duration(days: 1)) : now;
    return DateTime(d.year, d.month, d.day);
  }

  @override
  Future<List<CostCategory>> costCategories() async => _categories;
  @override
  Future<List<Supplier>> suppliers(String storeId) async => _suppliers;
  @override
  Future<List<Purchase>> recentPurchases(
    String storeId, {
    int limit = 30,
  }) async =>
      (List.of(_purchases)
            ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate)))
          .take(limit)
          .toList();

  @override
  Future<List<Purchase>> monthPurchases(String storeId, DateTime month) async =>
      _purchases
          .where(
            (p) =>
                p.purchaseDate.year == month.year &&
                p.purchaseDate.month == month.month,
          )
          .toList()
        ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

  final _requestIds =
      <String, String>{}; // clientRequestId → 已建立的進貨 id（新增重送時接續用同一筆，0089 修復）
  final _purchaseMeta = <String, (DateTime, DateTime)>{}; // 進貨日、登記時間（算庫存用）
  final _items = <String, List<PurchaseItem>>{};
  final _itemNegate = <String, bool>{};

  @override
  Future<SlipReading> readSlip(String storeId, String image) async {
    // 示範：假裝讀到一張酒商送貨單（第二行對不到庫存品項、第三行沒把握）
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final first = _products.where((p) => !_inactive.contains(p.id)).firstOrNull;
    return SlipReading(
      vendor: '大倉捷',
      date: await businessDate(storeId),
      total: 6300,
      category: '酒水',
      notes: '第三行數量有點模糊，請核對',
      items: [
        PurchaseItem(
          name: first?.name ?? '琴酒 700ml',
          qty: 6,
          unit: first?.unit ?? '瓶',
          unitPrice: 650,
          productId: first?.id,
          stockQty: first == null ? null : 6,
          source: 'ai',
        ),
        PurchaseItem(
          name: '通寧水 200ml',
          qty: 2,
          unit: '箱',
          unitPrice: 720,
          source: 'ai',
        ),
        PurchaseItem(
          name: '檸檬',
          qty: 3,
          unit: '斤',
          unitPrice: 120,
          source: 'ai',
          sure: false,
        ),
      ],
    );
  }

  @override
  Future<List<QuoteLine>> purchaseQuoteLines(String storeId) async {
    QuoteLine q(
      String n,
      String? u,
      double price,
      int daysAgo,
      String v,
      String cat,
    ) => QuoteLine(
      name: n,
      unit: u,
      unitPrice: price,
      qty: 1,
      date: _daysAgo(daysAgo),
      vendor: v,
      categoryCode: cat,
    );
    return [
      q("Hendrick's Gin 700ml", '瓶', 1050, 20, '示範酒商A', 'yc_drink'),
      q("Hendrick's Gin 700ml", '瓶', 1080, 3, '示範酒商A', 'yc_drink'),
      q('Bombay Sapphire', '瓶', 620, 9, '示範酒商B', 'yc_drink'),
      q('Campari', '瓶', 590, 12, '示範酒商A', 'yc_drink'),
      q('Campari', '瓶', 560, 2, '示範酒商B', 'yc_drink'),
      q('通寧水', '箱', 480, 5, '示範酒商B', 'yc_drink'),
      q('檸檬', '斤', 65, 6, '示範水果行', 'yc_food'),
      q('檸檬', '斤', 72, 1, '示範水果行', 'yc_food'),
      q('薯條', '包', 135, 4, '示範冷凍食品', 'yc_food'),
      q('垃圾袋', '包', 89, 4, '示範雜貨', 'yc_misc'),
      // 新增進貨時照片讀到的（示範）
      for (final e in _items.entries)
        if (_purchaseMeta[e.key] case final m?)
          for (final it in e.value)
            QuoteLine(
              name: it.name,
              unit: it.unit,
              unitPrice: it.unitPrice,
              qty: _itemNegate[e.key] == true ? -it.qty : it.qty,
              date: m.$1,
              vendor: _purchases
                  .where((p) => p.id == e.key)
                  .firstOrNull
                  ?.supplierName,
              categoryCode:
                  _purchases
                      .where((p) => p.id == e.key)
                      .firstOrNull
                      ?.categoryCode ??
                  'yc_misc',
            ),
    ];
  }

  final _quoteEdits = <String, QuoteEdit>{};
  @override
  Future<List<QuoteEdit>> purchaseQuoteEdits(String storeId) async =>
      _quoteEdits.values.toList();
  @override
  Future<void> savePurchaseQuoteEdit(String storeId, QuoteEdit edit) async {
    if (_isStaff) throw Exception('message: 只有老闆或店長可以修改進貨報價,');
    _quoteEdits[edit.key] = edit;
  }

  @override
  Future<void> deletePurchaseQuoteEdit(String storeId, String key) async =>
      _quoteEdits.remove(key);

  @override
  Future<List<PurchaseItem>> purchaseItems(String purchaseId) async => [
    for (final it in _items[purchaseId] ?? const <PurchaseItem>[])
      PurchaseItem(
        name: it.name,
        qty: it.qty,
        unit: it.unit,
        unitPrice: it.unitPrice,
        productId: it.productId,
        stockQty: it.stockQty,
        source: it.source,
      ),
  ];

  // 主檔＋品項一次存完，全部成功才算（0089 修復：原本分兩次存，中途斷線會變成帳改了、庫存沒改）；
  // 新增時同一個 clientRequestId 重送會接續用原來那筆的 id，不會重複新增、也不會被擋住（0089 修復）
  @override
  Future<String> savePurchaseWithItems({
    String? purchaseId,
    required NewPurchase purchase,
    List<PurchaseItem>? items,
    bool negate = false,
  }) async {
    final p = purchase;
    String id;
    if (purchaseId != null) {
      final i = _purchases.indexWhere((x) => x.id == purchaseId);
      final o = _purchases[i];
      _purchases[i] = Purchase(
        id: o.id,
        purchaseDate: p.purchaseDate,
        categoryCode: p.categoryCode,
        supplierName: p.vendorName ?? o.supplierName,
        memo: p.memo,
        amount: p.amount,
        paidBy: p.paidBy,
        reconciled: o.reconciled,
        source: o.source,
        createdBy: o.createdBy,
      );
      id = purchaseId;
    } else {
      final existing = _requestIds[p.clientRequestId];
      if (existing != null) {
        id = existing;
      } else {
        if (p.amount == 0) throw Exception('message: 金額不能為 0,');
        id = 'n${_seq++}';
        _purchaseMeta[id] = (p.purchaseDate, DateTime.now());
        _purchases.add(
          Purchase(
            id: id,
            purchaseDate: p.purchaseDate,
            categoryCode: p.categoryCode,
            supplierName: _suppliers
                .where((s) => s.id == p.supplierId)
                .map((s) => s.name)
                .firstOrNull,
            memo: p.memo,
            amount: p.amount,
            paidBy: p.paidBy,
            reconciled: false,
            source: 'app',
          ),
        );
        _requestIds[p.clientRequestId] = id;
      }
    }
    if (items != null) {
      _items[id] = [
        for (final it in items)
          PurchaseItem(
            name: it.name,
            qty: it.qty,
            unit: it.unit,
            unitPrice: it.unitPrice,
            productId: it.productId,
            stockQty: it.stockQty,
            source: it.source,
          ),
      ];
      _itemNegate[id] = negate;
    }
    return id;
  }

  @override
  Future<void> deletePurchase(String purchaseId) async =>
      _purchases.removeWhere((x) => x.id == purchaseId);

  // 進貨待確認（示範）
  late final List<PurchaseMatch> _matches = [
    PurchaseMatch(
      kind: 'pair',
      appId: 'm1',
      appDate: _daysAgo(3),
      amount: 290,
      paidBy: 'petty_cash',
      appName: '小北 3M手套',
      appCategory: '雜項',
      createdName: '示範正職',
      importId: 'i1',
      importDate: _daysAgo(8),
      importName: '豆芽菜.蒜仁',
      importCategory: '餐食',
      reasons: const ['日期不同', '名稱對不上', '類別不同'],
    ),
    PurchaseMatch(
      kind: 'pair',
      appId: 'm2',
      appDate: _daysAgo(5),
      amount: 1260,
      paidBy: 'vendor',
      appName: '示範水果行',
      appCategory: '餐食',
      createdName: '示範店長',
      importId: 'i2',
      importDate: _daysAgo(4),
      importName: '示範水果行',
      importCategory: '餐食',
      reasons: const ['日期不同'],
    ),
    PurchaseMatch(
      kind: 'unmatched',
      appId: 'm3',
      appDate: _daysAgo(9),
      amount: 628,
      paidBy: 'petty_cash',
      appName: '衛生廚房用品',
      appCategory: '雜項',
      createdName: '示範正職',
      reasons: const ['日報表沒有這一筆'],
    ),
  ];
  @override
  Future<List<PurchaseMatch>> purchaseMatchQueue(String storeId) async =>
      _isStaff ? const [] : List.of(_matches);
  @override
  Future<void> confirmPurchaseMatches(List<String> appIds) async =>
      _matches.removeWhere((m) => appIds.contains(m.appId));
  @override
  Future<void> rejectPurchaseMatch(String appId) async {
    final i = _matches.indexWhere((m) => m.appId == appId);
    final m = _matches[i];
    _matches[i] = PurchaseMatch(
      kind: m.kind,
      appId: m.appId,
      appDate: m.appDate,
      amount: m.amount,
      paidBy: m.paidBy,
      appName: m.appName,
      appCategory: m.appCategory,
      createdName: m.createdName,
      importId: m.importId,
      importDate: m.importDate,
      importName: m.importName,
      importCategory: m.importCategory,
      reasons: m.reasons,
      waiting: true,
    );
  }

  @override
  Future<void> dismissUnmatchedPurchase(String appId) async =>
      _matches.removeWhere((m) => m.appId == appId);

  @override
  Future<void> setReconciled(String purchaseId, bool reconciled) async {
    if (_isStaff) throw Exception('message: 只有老闆或店長可以核銷,');
    final i = _purchases.indexWhere((p) => p.id == purchaseId);
    final p = _purchases[i];
    _purchases[i] = Purchase(
      id: p.id,
      purchaseDate: p.purchaseDate,
      categoryCode: p.categoryCode,
      supplierName: p.supplierName,
      memo: p.memo,
      amount: p.amount,
      paidBy: p.paidBy,
      reconciled: reconciled,
      source: p.source,
    );
  }

  @override
  Future<List<Product>> products(String storeId) async =>
      _products.where((p) => !_inactive.contains(p.id)).toList();
  final _inactive = <String>{}; // 停用的品項（歷史盤點照常顯示名稱）

  @override
  Future<List<StockCount>> stockCounts(String storeId) async =>
      List.of(_counts.reversed);

  @override
  Future<Map<String, StockLevel>> latestStock(String storeId) async {
    final counted = <String, (double, DateTime, DateTime)>{};
    for (final c in _counts.reversed) {
      if (c.status != CountStatus.submitted && c.status != CountStatus.approved)
        continue;
      for (final e in (_lines[c.id] ?? {}).entries) {
        counted.putIfAbsent(
          e.key,
          () => (e.value, c.bizDate, _countedAt[c.id] ?? DateTime(2000)),
        );
      }
    }
    // 盤點之後的進貨明細（同資料庫 stock_levels）
    final inflow = <String, double>{};
    for (final e in _items.entries) {
      final meta = _purchaseMeta[e.key];
      if (meta == null) continue;
      for (final it in e.value.where((x) => x.toStock)) {
        final c = counted[it.productId];
        final after =
            c == null ||
            meta.$1.isAfter(c.$2) ||
            (meta.$1 == c.$2 && meta.$2.isAfter(c.$3));
        if (after)
          inflow[it.productId!] =
              (inflow[it.productId!] ?? 0) +
              (_itemNegate[e.key] == true ? -it.stockQty! : it.stockQty!);
      }
    }
    return {
      for (final id in {...counted.keys, ...inflow.keys})
        id: StockLevel(
          (counted[id]?.$1 ?? 0) + (inflow[id] ?? 0),
          counted[id]?.$2,
          purchased: inflow[id] ?? 0,
        ),
    };
  }

  final _countedAt = <String, DateTime>{};

  @override
  Future<Map<String, LastCount>> stockLastCounts(String storeId) async {
    final out = Map.of(_demoLast);
    for (final c in _counts) {
      if (c.status != CountStatus.submitted && c.status != CountStatus.approved)
        continue;
      for (final e in (_lines[c.id] ?? {}).entries) {
        out[e.key] = LastCount(
          e.value,
          c.bizDate,
          at: _countedAt[c.id],
          by: '示範使用者',
        );
      }
    }
    return out;
  }

  final _stockRequests = <String>{};
  @override
  Future<StockSubmitResult> submitStockCount(
    String storeId,
    Map<String, double> lines, {
    required String requestId,
    DateTime? seenAt,
  }) async {
    if (!_stockRequests.add(requestId))
      return StockSubmitResult(lines.length, repeat: true);
    final id = await createStockCount(storeId, null);
    _lines[id]!.addAll(lines);
    await setCountStatus(id, CountStatus.submitted);
    return StockSubmitResult(lines.length);
  }

  @override
  Future<String> saveProduct(
    String storeId,
    Product p, {
    bool setCycle = false,
  }) async {
    // 同名的停用品項：恢復那一個（與正式資料庫一致）
    final old = p.id.isEmpty
        ? _products
              .where((x) => x.name == p.name.trim() && _inactive.contains(x.id))
              .firstOrNull
        : null;
    if (old != null) {
      _inactive.remove(old.id);
      p = Product(
        old.id,
        p.name,
        p.category,
        p.unit,
        parLevel: p.parLevel,
        countCycle: p.countCycle,
      );
    }
    final i = _products.indexWhere((x) => x.id == p.id);
    final np = Product(
      p.id.isEmpty ? 'p${_seq++}' : p.id,
      p.name,
      p.category,
      p.unit,
      parLevel: p.parLevel,
      countCycle: setCycle || i < 0 ? p.countCycle : _products[i].countCycle,
    );
    if (i < 0) {
      _products.add(np);
    } else {
      _products[i] = np;
    }
    return np.id;
  }

  @override
  Future<void> deactivateProduct(String productId) async {
    _inactive.add(productId);
  }

  @override
  Future<String> createStockCount(String storeId, String? note) async {
    final id = 'c${_seq++}';
    _counts.add(
      StockCount(
        id: id,
        bizDate: await businessDate(storeId),
        countedBy: 'demo-user',
        status: CountStatus.draft,
        note: note,
        lineCount: 0,
      ),
    );
    _lines[id] = {};
    return id;
  }

  @override
  Future<List<CountLine>> countLines(String countId) async => [
    for (final e in (_lines[countId] ?? {}).entries)
      () {
        final p = _products.firstWhere((p) => p.id == e.key);
        return CountLine(p.id, p.name, p.unit, e.value);
      }(),
  ];

  @override
  Future<void> upsertCountLine(
    String countId,
    String productId,
    double qty,
  ) async {
    final c = _counts.firstWhere((c) => c.id == countId);
    if (c.status != CountStatus.draft && c.status != CountStatus.rejected) {
      throw Exception('message: 盤點已送出或已核准，明細不能修改,');
    }
    _lines[countId]![productId] = qty;
    _replace(c, c.status);
  }

  @override
  Future<void> setCountStatus(
    String countId,
    CountStatus status, {
    String? voidReason,
  }) async {
    final c = _counts.firstWhere((c) => c.id == countId);
    if (status == CountStatus.approved && _isStaff)
      throw Exception('message: 員工不能核准盤點,');
    if (status == CountStatus.submitted) _countedAt[c.id] = DateTime.now();
    _replace(c, status);
  }

  void _replace(StockCount c, CountStatus s) {
    final i = _counts.indexOf(c);
    _counts[i] = StockCount(
      id: c.id,
      bizDate: c.bizDate,
      countedBy: c.countedBy,
      status: s,
      note: c.note,
      lineCount: _lines[c.id]?.length ?? 0,
    );
  }

  // ---------------- 訂位（示範） ----------------
  final Map<String, List<Reservation>> _demoRes = {}; // 依店家分開
  final Map<String, Map<String, dynamic>> _demoResSettings = {};
  @override
  Future<ReservationSettings?> reservationSettings(String storeId) async =>
      // 公版新店（示範）：開店精靈建好之前沒有訂位設定
      storeId == _demoNewStoreId && !_demoResSettings.containsKey(storeId)
      ? null
      : ReservationSettings.fromRow({
          'store_id': storeId,
          'slug': 'demo',
          'enabled': true,
          'display_name': '示範店',
          'first_slot': '19:00',
          'last_slot': '23:00',
          'slot_minutes': 30,
          'max_guests_per_slot': 20,
          'max_party': 6,
          'days_ahead': 7,
          'same_day_cutoff': '17:00',
          'web_burst_limit': 30,
          ...?_demoResSettings[storeId],
        });
  @override
  Future<void> saveReservationSettings(
    String storeId,
    Map<String, dynamic> values,
  ) async {
    _demoResSettings.putIfAbsent(storeId, () => {}).addAll(values);
  }

  // 訂位頁的樣子（示範）：上傳的圖只留在這支手機的記憶體
  final Map<String, BookingProfile> _demoProfiles = {};
  final Map<String, Uint8List> demoBookingAssets = {};
  @override
  Future<BookingProfile?> bookingProfile(String storeId) async =>
      _demoProfiles[storeId] ??
      (storeId == _demoNewStoreId ? null : _demoDefaultProfile);
  static const _demoDefaultProfile = BookingProfile(
    langs: ['zh', 'en'],
    title: {'zh': '示範酒吧', 'en': 'Demo Bar'},
    intro: {'zh': '老宅二樓的小酒吧', 'en': 'A small bar upstairs in an old house'},
    address: {'en': '2F, No. 15, Demo Rd., Taipei'},
    minSpend: 600,
    minSpendText: {
      'zh': '每人一杯飲品\n{amount}',
      'en': 'One drink per person.\n{amount}',
    },
    infoRows: [
      BookingInfoRow(
        label: {'zh': '營業時間', 'en': 'Hours'},
        text: {'zh': '每天 19:00～01:00', 'en': 'Daily 19:00–01:00'},
      ),
    ],
    logoUrl: 'logo-xcw.png',
    heroUrl: 'hero-xcw.jpg',
    heroPos: '22% 45%',
  );
  @override
  Future<void> saveBookingProfile(String storeId, BookingProfile p) async =>
      _demoProfiles[storeId] = p;
  // 開店精靈（示範）：照資料庫的規則走（只能建一次、代號格式、保留字、有人用了）
  static const _demoNewStoreId = 'demo-new';
  static const _demoTakenSlugs = {'lane-bar', 'xiaocheng'};
  int _onboardInvites = 0;
  @override
  Future<OnboardingStatus> onboardingStatus(String storeId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final s = await reservationSettings(storeId);
    final p = await bookingProfile(storeId);
    final isNew = storeId == _demoNewStoreId;
    return OnboardingStatus(
      booking: s != null,
      slug: s?.slug,
      page:
          p != null &&
          (p.logoUrl != null ||
              p.heroUrl != null ||
              (p.intro['zh'] ?? '').isNotEmpty),
      members: !isNew || _onboardInvites > 0,
      staffing: !isNew,
    );
  }

  @override
  Future<String> setupOnlineBooking(
    String storeId, {
    required String slug,
    required String displayName,
    String? address,
    String? phone,
    required List<String> slotTimes,
    List<int> closedWeekdays = const [],
    int? maxGroups,
    int? maxGuests,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final v = slug.trim().toLowerCase();
    if (await reservationSettings(storeId) != null) {
      throw Exception('message: ONBOARD_EXISTS：這家店已經設定過線上訂位了，請到「訂位設定」修改,');
    }
    final err = slugError(v);
    if (err != null) {
      final code = reservedBookingSlugs.contains(v)
          ? 'ONBOARD_SLUG_RESERVED'
          : 'ONBOARD_SLUG_FORMAT';
      throw Exception('message: $code：$err,');
    }
    if (_demoTakenSlugs.contains(v))
      throw Exception('message: ONBOARD_SLUG_TAKEN：這個訂位網址代號有人用了，請換一個,');
    if (displayName.trim().isEmpty)
      throw Exception('message: ONBOARD_NAME：訂位頁顯示的店名請填 1 到 40 個字,');
    final slots = normalizeSlots(slotTimes);
    if (slots.isEmpty) throw Exception('message: ONBOARD_SLOTS：至少要有一個訂位時段,');
    _demoResSettings[storeId] = {
      'slug': v,
      'display_name': displayName.trim(),
      'address': address,
      'phone': phone,
      'slot_times': slots,
      'first_slot': slots.first,
      'last_slot': slots.last,
      'closed_weekdays': ([...closedWeekdays]..sort()),
      'max_groups_per_day': maxGroups,
      'max_guests_per_day': maxGuests,
      'days_ahead': 14,
    };
    _demoProfiles.putIfAbsent(
      storeId,
      () => BookingProfile(title: {'zh': displayName.trim()}),
    );
    return v;
  }

  // 訂位的 AI 設定助理（示範）：不連 AI，只認得幾種說法，照真的流程走（建議 → 確認套用 → 可以改回去）
  final Map<String, List<AssistRecord>> _demoAssist = {};
  Map<String, dynamic> _profileRow(BookingProfile p) => {
    'langs': [...p.langs],
    'title': {...p.title},
    'short_name': {...p.shortName},
    'intro': {...p.intro},
    'address_i18n': {...p.address},
    'directions_i18n': {...p.directions},
    'min_spend': p.minSpend,
    'min_spend_text': {...p.minSpendText},
    'info_rows': [
      for (final r in p.infoRows) {'label': r.label, 'text': r.text},
    ],
    'logo_url': p.logoUrl,
    'hero_url': p.heroUrl,
    'hero_pos': p.heroPos,
    'sister_store_id': p.sisterStoreId,
  };
  @override
  Future<AssistReply> askBookingAssistant(
    String storeId,
    String message,
    List<AssistTurn> history,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final p = (await bookingProfile(storeId))!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    final changes = <Map<String, dynamic>>[];
    final parts = <String>[];
    if (RegExp(r'包場|不開放|公休|休息').hasMatch(message)) {
      final want = message.contains('日') && !message.contains('六')
          ? 7
          : message.contains('五')
          ? 5
          : 6;
      var d = today.add(const Duration(days: 1));
      while (d.weekday != want) {
        d = d.add(const Duration(days: 1));
      }
      final cur = _demoSpecial[storeId]?[iso(d)];
      final note = message.contains('包場') ? '包場' : null;
      changes.add({
        'op': 'day',
        'date': iso(d),
        'before': cur != null && cur.closed
            ? {'closed': true, 'note': cur.note}
            : null,
        'after': {'closed': true, 'note': note},
      });
      parts.add(
        '${AssistChange.dayLabel(iso(d))}改成整天不開放線上訂位${note == null ? '' : '，說明寫「$note」'}',
      );
    }
    final amount = RegExp(r'低消[^0-9]*([0-9]{2,6})').firstMatch(message);
    if (amount != null) {
      changes.add({
        'op': 'min_spend',
        'before': p.minSpend,
        'after': int.parse(amount.group(1)!),
      });
      parts.add('每人低消改成 ${amount.group(1)} 元');
    }
    if (message.contains('日文') && !p.langs.contains('ja')) {
      changes.add({
        'op': 'langs',
        'before': [...p.langs],
        'after': [
          for (final l in BookingProfile.langsAll)
            if (p.langs.contains(l) || l == 'ja') l,
        ],
      });
      changes.add({
        'op': 'text',
        'field': 'intro',
        'lang': 'ja',
        'before': p.intro['ja'],
        'after': '古い家の二階にある小さなバー',
      });
      parts.add('訂位頁加開日文，也幫你寫好日文介紹');
    }
    if (message.contains('英文') && message.contains('介紹')) {
      changes.add({
        'op': 'text',
        'field': 'intro',
        'lang': 'en',
        'before': p.intro['en'],
        'after': 'A quiet little bar upstairs in an old Taipei house',
      });
      parts.add('英文介紹改寫得更有畫面一點');
    }
    if (changes.isEmpty) {
      return const AssistReply(
        reply: '示範版只認得幾種說法，例如「這週六包場不開放」「低消改 700」「加開日文」「英文介紹改一下」。正式版可以用自己的話說。',
      );
    }
    return AssistReply(
      reply: '好，我打算：${parts.join('；')}。請看下面確認。',
      changes: [for (final c in changes) AssistChange(c)],
    );
  }

  void _demoAssistExec(
    String storeId,
    BookingProfile p,
    List<Map<String, dynamic>> changes,
  ) {
    final row = _profileRow(p);
    final days = _demoSpecial[storeId] ??= {};
    String norm(Object? v) =>
        jsonEncode(v is List ? ([...v.map((e) => '$e')]..sort()) : v);
    Object? current(Map<String, dynamic> c) => switch (c['op']) {
      'text' =>
        ((row[c['field']] as Map<String, String>)[c['lang']] ?? '').isEmpty
            ? null
            : (row[c['field']] as Map<String, String>)[c['lang']],
      'min_spend' => row['min_spend'],
      'langs' => row['langs'],
      'day' =>
        days[c['date']] == null
            ? null
            : {'closed': true, 'note': days[c['date']]!.note},
      _ => null,
    };
    // 跟正式版一樣：先全部檢查「改前」跟現在一樣，一項不對整筆不動（Codex P2）
    for (final c in changes) {
      if (norm(current(c)) != norm(c['before'])) {
        throw Exception(
          'message: BOOKING_ASSIST_STALE：設定在你按確認之前被改過了，這次沒有套用，請重新問一次,',
        );
      }
    }
    for (final c in changes) {
      switch (c['op']) {
        case 'text':
          final m = row[c['field']] as Map<String, String>;
          final a = c['after'] as String?;
          a == null || a.isEmpty
              ? m.remove(c['lang'])
              : m[c['lang'] as String] = a;
        case 'min_spend':
          row['min_spend'] = c['after'];
        case 'langs':
          row['langs'] = [for (final l in c['after'] as List) '$l'];
        case 'day':
          final a = c['after'];
          if (a == null) {
            days.remove(c['date']);
          } else {
            days[c['date'] as String] = ReservationSpecialDay(
              day: DateTime.parse(c['date'] as String),
              closed: true,
              note: (a as Map)['note'] as String?,
            );
          }
      }
    }
    _demoProfiles[storeId] = BookingProfile.fromRow(row);
  }

  @override
  Future<void> applyBookingAssist(
    String storeId,
    String request,
    List<AssistChange> changes,
  ) async {
    _demoAssistExec(storeId, (await bookingProfile(storeId))!, [
      for (final c in changes) c.raw,
    ]);
    (_demoAssist[storeId] ??= []).insert(
      0,
      AssistRecord(
        id: 'demo-${DateTime.now().microsecondsSinceEpoch}',
        appliedAt: DateTime.now(),
        request: request,
        changes: changes,
      ),
    );
  }

  @override
  Future<List<AssistRecord>> bookingAssistHistory(String storeId) async => [
    ...?_demoAssist[storeId],
  ];

  @override
  Future<void> undoBookingAssist(String id) async {
    for (final e in _demoAssist.entries) {
      final i = e.value.indexWhere((r) => r.id == id);
      if (i < 0) continue;
      final r = e.value[i];
      if (r.undoneAt != null) throw Exception('message: 這筆修改已經改回去了,');
      _demoAssistExec(e.key, (await bookingProfile(e.key))!, [
        for (final c in r.changes.reversed)
          {...c.raw, 'before': c.raw['after'], 'after': c.raw['before']},
      ]);
      e.value[i] = AssistRecord(
        id: r.id,
        appliedAt: r.appliedAt,
        request: r.request,
        changes: r.changes,
        undoneAt: DateTime.now(),
      );
      return;
    }
  }
  // 排班的 AI 設定助理（示範，ops 0154）：不連 AI，只認得幾種說法，照真的流程走（建議 → 確認套用 → 可以改回去）
  final Map<String, List<AssistRecord>> _demoShiftAssist = {};
  static const _demoAssistPeople = [('f0', '阿明'), ('f1', '小安'), ('f2', '阿哲'), ('p0', '小魚'), ('p1', '阿凱'), ('p2', '芳芳'), ('p3', '小白'), ('p4', '阿樂')];
  static const _wdNames = '一二三四五六日';
  @override
  Future<AssistReply> askShiftAssistant(String storeId, String message, List<AssistTurn> history) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final changes = <Map<String, dynamic>>[];
    final parts = <String>[];
    Map<String, int>? staffRow(int w) {
      final s = _staffing[w];
      return s == null ? null : {'need': s.need, 'min_full': s.minFull};
    }

    final need = RegExp(r'要\s*([0-9]{1,2})\s*[個位]?人').firstMatch(message);
    final days = RegExp(r'週([一二三四五六日])').allMatches(message).map((m) => _wdNames.indexOf(m.group(1)!) + 1).toSet();
    if (need != null && days.isNotEmpty) {
      final n = int.parse(need.group(1)!);
      for (final w in days.toList()..sort()) {
        final b = staffRow(w);
        final full = b?['min_full'] ?? 0;
        if (b?['need'] == n) continue;
        changes.add({'op': 'staffing', 'weekday': w, 'before': b, 'after': {'need': n, 'min_full': full > n ? n : full}});
      }
      parts.add('${days.map((w) => '週${_wdNames[w - 1]}').join('、')}改成每天 $n 人');
    } else if (need != null && RegExp(r'聖誕|跨年|([0-9]{1,2})/([0-9]{1,2})').hasMatch(message)) {
      final now = DateTime.now();
      final md = RegExp(r'([0-9]{1,2})/([0-9]{1,2})').firstMatch(message);
      var d = message.contains('跨年')
          ? DateTime(now.year, 12, 31)
          : message.contains('聖誕')
              ? DateTime(now.year, 12, 25)
              : DateTime(now.year, int.parse(md!.group(1)!), int.parse(md.group(2)!));
      if (d.isBefore(DateTime(now.year, now.month, now.day))) d = DateTime(d.year + 1, d.month, d.day);
      final iso = d.toIso8601String().substring(0, 10);
      final cur = _staffDays[d.day];
      changes.add({'op': 'staffing_day', 'date': iso, 'before': cur == null ? null : {'need': cur}, 'after': {'need': int.parse(need.group(1)!)}});
      parts.add('${AssistChange.dayLabel(iso)}要 ${need.group(1)} 人');
    }
    final perDay = RegExp(r'同一天最多\s*([0-9]{1,2})\s*[個位]').firstMatch(message);
    if (perDay != null && int.parse(perDay.group(1)!) != _offPerDay) {
      changes.add({'op': 'setting', 'field': 'off_per_day', 'before': _offPerDay, 'after': int.parse(perDay.group(1)!)});
      parts.add('同一天最多 ${perDay.group(1)} 位正職指休');
    }
    final deadline = RegExp(r'([0-9]{1,2})\s*號前').firstMatch(message);
    if (deadline != null) {
      final v = int.parse(deadline.group(1)!);
      if (v >= 1 && v <= 28 && v != _deadline) {
        changes.add({'op': 'setting', 'field': 'request_deadline', 'before': _deadline, 'after': v});
        parts.add('每月 $v 號前填好下個月的班');
      }
    }
    final maxDays = RegExp(r'最多上\s*([0-9]{1,2})\s*天').firstMatch(message);
    if (maxDays != null) {
      for (final (id, nick) in _demoAssistPeople) {
        final full = _demoFullNames[nick];
        if (!message.contains(nick) && (full == null || !message.contains(full))) continue;
        final v = int.parse(maxDays.group(1)!);
        changes.add({'op': 'rule', 'person_id': id, 'person_name': full ?? nick, 'field': 'max_shifts', 'before': _shiftRules[id]?.maxShifts, 'after': v});
        parts.add('${full ?? nick}每月最多上 $v 天');
        break;
      }
    }
    if (changes.isEmpty) {
      return const AssistReply(
          reply: '示範版只認得幾種說法，例如「週五週六要 5 個人」「聖誕節那天要 6 個人」「同一天最多 2 位指休」「每月 25 號前填好班」「阿凱每月最多上 12 天」。正式版可以用自己的話說。');
    }
    return AssistReply(reply: '好，我打算：${parts.join('；')}。請看下面確認。', changes: [for (final c in changes) AssistChange(c)]);
  }

  void _demoShiftAssistExec(List<Map<String, dynamic>> changes) {
    Object? current(Map<String, dynamic> c) => switch (c['op']) {
          'staffing' => _staffing[c['weekday']] == null
              ? null
              : {'need': _staffing[c['weekday']]!.need, 'min_full': _staffing[c['weekday']]!.minFull},
          'staffing_day' => _staffDays[DateTime.parse(c['date'] as String).day] == null
              ? null
              : {'need': _staffDays[DateTime.parse(c['date'] as String).day]},
          'setting' => switch (c['field']) {
              'request_deadline' => _deadline,
              'prefer_run' => _preferRun,
              'off_per_day' => _offPerDay,
              _ => _offMonthMax,
            },
          'rule' => switch (c['field']) {
              'max_shifts' => _shiftRules[c['person_id']]?.maxShifts,
              _ => null,
            },
          _ => null,
        };
    // 跟正式版一樣：先全部檢查「改前」跟現在一樣，一項不對整筆不動
    for (final c in changes) {
      if (jsonEncode(current(c)) != jsonEncode(c['before'])) {
        throw Exception('message: SHIFT_ASSIST_STALE：設定在你按確認之前被改過了，這次沒有套用，請重新問一次,');
      }
    }
    for (final c in changes) {
      final a = c['after'];
      switch (c['op']) {
        case 'staffing':
          final w = c['weekday'] as int;
          a == null ? _staffing.remove(w) : _staffing = {..._staffing, w: StaffingNeed((a as Map)['need'] as int, a['min_full'] as int? ?? 0)};
        case 'staffing_day':
          final d = DateTime.parse(c['date'] as String).day;
          a == null ? _staffDays.remove(d) : _staffDays[d] = (a as Map)['need'] as int;
        case 'setting':
          switch (c['field']) {
            case 'request_deadline':
              _deadline = a as int;
            case 'prefer_run':
              _preferRun = a as int?;
            case 'off_per_day':
              _offPerDay = a as int?;
            default:
              _offMonthMax = a as int?;
          }
        case 'rule':
          final id = c['person_id'] as String;
          final r = _shiftRules[id] ?? ShiftRule(personId: id);
          _shiftRules[id] = ShiftRule(
              personId: id,
              planAsPart: r.planAsPart,
              monthOff: r.monthOff,
              minShifts: r.minShifts,
              maxShifts: a as int?,
              maxConsecutive: r.maxConsecutive,
              noWeekdays: r.noWeekdays,
              marks: r.marks,
              weekdayMarks: r.weekdayMarks,
              note: r.note);
      }
    }
  }

  @override
  Future<void> applyShiftAssist(String storeId, String request, List<AssistChange> changes) async {
    _demoShiftAssistExec([for (final c in changes) c.raw]);
    (_demoShiftAssist[storeId] ??= []).insert(
        0,
        AssistRecord(
            id: 'demo-s-${DateTime.now().microsecondsSinceEpoch}', appliedAt: DateTime.now(), request: request, changes: changes));
  }

  @override
  Future<List<AssistRecord>> shiftAssistHistory(String storeId) async => [...?_demoShiftAssist[storeId]];

  @override
  Future<void> undoShiftAssist(String id) async {
    for (final e in _demoShiftAssist.entries) {
      final i = e.value.indexWhere((r) => r.id == id);
      if (i < 0) continue;
      final r = e.value[i];
      if (r.undoneAt != null) throw Exception('message: 這筆修改已經改回去了,');
      try {
        _demoShiftAssistExec([
          for (final c in r.changes.reversed) {...c.raw, 'before': c.raw['after'], 'after': c.raw['before']},
        ]);
      } catch (_) {
        throw Exception('message: SHIFT_ASSIST_STALE：這筆修改之後又被改過，不能直接改回去，請到排班條件手動調整,');
      }
      e.value[i] = AssistRecord(id: r.id, appliedAt: r.appliedAt, request: r.request, changes: r.changes, undoneAt: DateTime.now());
      return;
    }
  }
  // 許願單（示範）：先放兩則平台已經回覆過的，新寫的狀態是「平台收到了」
  final Map<String, List<PlatformWish>> _demoWishes = {};
  List<PlatformWish> _wishesOf(String storeId) =>
      _demoWishes.putIfAbsent(storeId, () {
        final now = DateTime.now();
        return [
          PlatformWish(
            id: 'pw-2',
            title: '訂位頁可以讓客人選座位區',
            body: '客人常問能不能坐吧台，希望訂位時就能選「吧台／沙發區」。\n\n為什麼需要：現在都要打電話來問，很花時間。',
            authorName: '示範老闆',
            status: PlatformWishStatus.planned,
            reply: '收到，很多店也有一樣的需求，排進下個月的待辦。做好會再通知你。',
            createdAt: now.subtract(const Duration(days: 3)),
            repliedAt: now.subtract(const Duration(days: 1)),
          ),
          PlatformWish(
            id: 'pw-1',
            title: '盤點可以掃條碼',
            body: '盤點時用手機掃酒瓶上的條碼，直接跳到那個品項。',
            authorName: '示範店長',
            status: PlatformWishStatus.done,
            reply: '已經做好了：盤點畫面右上角多一個掃描按鈕。',
            createdAt: now.subtract(const Duration(days: 20)),
            repliedAt: now.subtract(const Duration(days: 6)),
          ),
        ];
      });
  // 店家接自己的 AI（ops 0157）：示範版不連 AI；金鑰裡有 bad 就當作無效，其餘都算測試成功
  final Map<String, StoreAiSetting> _storeAi = {};
  @override
  Future<StoreAiSetting?> storeAiSetting(String storeId) async => _storeAi[storeId];
  @override
  Future<StoreAiResult> saveStoreAi(String storeId, StoreAiProvider provider, String model, String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final info = storeAiInfo(provider);
    final problem = storeAiModelProblem(model) ?? storeAiKeyProblem(key);
    if (problem != null) return StoreAiResult.fail(problem);
    if (key.contains('bad')) return StoreAiResult.fail('${info.label} 的金鑰無效或沒有權限，請到「AI 設定」檢查金鑰');
    final k = key.trim();
    _storeAi[storeId] = StoreAiSetting(
      provider: provider,
      model: model.trim().replaceFirst(RegExp(r'^models/'), ''),
      keyLast4: k.substring(k.length - 4),
      verifiedAt: DateTime.now(),
    );
    return StoreAiResult.ok(last4: k.substring(k.length - 4));
  }

  @override
  Future<StoreAiResult> testStoreAi(String storeId) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final s = _storeAi[storeId];
    if (s == null) return const StoreAiResult.fail('這家店還沒有設定自己的 AI');
    _storeAi[storeId] = StoreAiSetting(provider: s.provider, model: s.model, keyLast4: s.keyLast4, verifiedAt: DateTime.now());
    return const StoreAiResult.ok();
  }

  @override
  Future<void> clearStoreAi(String storeId) async => _storeAi.remove(storeId);

  // 0160：店家自己的 LINE 官方帳號（示範：token 含 bad＝LINE 說不能用；secret 全是 0＝secret 不對）
  final Map<String, StoreLineStatus> _storeLine = {};
  @override
  Future<StoreLineStatus> storeLineStatus(String storeId) async =>
      _storeLine[storeId] ??
      StoreLineStatus(connected: false, groupBound: await lineGroupBound(storeId), groupVia: await lineGroupBound(storeId) ? 'platform' : null);
  @override
  Future<StoreLineResult> saveStoreLine(String storeId, String secret, String token) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final problem = storeLineSecretProblem(secret) ?? storeLineTokenProblem(token);
    if (problem != null) return StoreLineResult.fail(problem);
    if (token.contains('bad')) {
      return const StoreLineResult.fail('LINE 的 Channel access token 無效或已經被撤銷，請到 LINE Developers 重新發一組再貼上');
    }
    final s = secret.trim(), t = token.trim();
    final secretWrong = RegExp(r'^0+$').hasMatch(s);
    const path = '/functions/v1/line-notify?k=3f9a1c0d5e7b2a4c6d8e0f1a2b3c4d5e';
    _storeLine[storeId] = StoreLineStatus(
      connected: true,
      botName: '示範小館通知',
      basicId: '@demo1234',
      secretLast4: s.substring(s.length - 4),
      tokenLast4: t.substring(t.length - 4),
      verifiedAt: secretWrong ? null : DateTime.now(),
      lastError: secretWrong ? 'Channel secret 不對，請到 LINE Developers 的 Basic settings 重新複製' : null,
      webhookPath: path,
    );
    return StoreLineResult.ok(
      verified: !secretWrong,
      webhookSet: true,
      webhookUrl: 'https://demo.supabase.co$path',
      warning: secretWrong ? 'Channel secret 不對，請到 LINE Developers 的 Basic settings 重新複製' : null,
    );
  }

  @override
  Future<StoreLineResult> testStoreLine(String storeId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final s = _storeLine[storeId];
    if (s == null || !s.connected) return const StoreLineResult.fail('這家店還沒有接上自己的 LINE 官方帳號');
    if (s.lastError != null) return StoreLineResult.fail(s.lastError);
    _storeLine[storeId] = StoreLineStatus(
      connected: true, botName: s.botName, basicId: s.basicId, secretLast4: s.secretLast4, tokenLast4: s.tokenLast4,
      verifiedAt: DateTime.now(), webhookPath: s.webhookPath, groupBound: s.groupBound, groupVia: s.groupVia,
    );
    return const StoreLineResult.ok();
  }

  @override
  Future<void> clearStoreLine(String storeId) async => _storeLine.remove(storeId);

  @override
  Future<List<PlatformWish>> platformWishes(String storeId) async => [
    ..._wishesOf(storeId),
  ];
  @override
  Future<String> createPlatformWish(
    String storeId,
    String title,
    String body,
  ) async {
    final list = _wishesOf(storeId);
    final err = validateWish(title, body, '');
    if (err != null) throw Exception('message: $err,');
    if (wishesThisMonth(list, toTaipei(DateTime.now())) >=
        platformWishMonthlyLimit) {
      throw Exception(
        'message: 這個月的許願單已經寫滿 $platformWishMonthlyLimit 則，下個月再寫,',
      );
    }
    final id = 'pw-${++_seq}';
    list.insert(
      0,
      PlatformWish(
        id: id,
        title: title.trim(),
        body: body.trim(),
        authorName: '示範老闆',
        status: PlatformWishStatus.received,
        createdAt: DateTime.now(),
      ),
    );
    return id;
  }

  // 平台回覆許願單（ops 0159，示範）：帳號含 platform＝平台管理者。資料是虛構的幾家店，
  // 再加上這次示範在自己店寫的許願（回覆後自己店的許願單也看得到）
  bool get _isPlatformAdmin => _email.contains('platform');
  List<PlatformAdminWish>? _adminDemo;
  List<PlatformAdminWish> get _adminOthers => _adminDemo ??= () {
    final now = DateTime.now();
    PlatformAdminWish w(String id, String store, String name, String title, String body, String author,
        PlatformWishStatus st, int daysAgo, {String? reply, int? repliedDaysAgo}) {
      final replied = repliedDaysAgo == null ? null : now.subtract(Duration(days: repliedDaysAgo));
      return PlatformAdminWish(
        storeId: store,
        storeName: name,
        repliedAtRaw: replied?.toUtc().toIso8601String(),
        wish: PlatformWish(
          id: id, title: title, body: body, authorName: author, status: st, reply: reply,
          createdAt: now.subtract(Duration(days: daysAgo, hours: 2)), repliedAt: replied,
        ),
      );
    }
    return [
      w('pa-1', 's-morning', '晨光咖啡', '會員集點換飲料', '客人消費一次蓋一點，滿十點送一杯。\n\n為什麼需要：常客一直問有沒有集點卡。', '林老闆', PlatformWishStatus.received, 0),
      w('pa-2', 's-alley', '巷口小館', '訂位時可以先付訂金', '週末大桌常常放鴿子，希望訂 6 位以上要先付訂金。', '陳店長', PlatformWishStatus.received, 1),
      w('pa-3', 's-noodle', '老街麵屋', '班表可以匯出成圖片傳 LINE', '每個月排好班要截圖好幾張，希望一鍵存成一張圖。', '王老闆', PlatformWishStatus.received, 2),
      w('pa-4', 's-morning', '晨光咖啡', '進貨可以掃發票 QR code', '電子發票上的 QR code 掃一下就帶入品項和金額。', '林老闆', PlatformWishStatus.planned, 6,
          reply: '很多店都想要，排進下個月的待辦。', repliedDaysAgo: 4),
      w('pa-5', 's-bar', '月台酒吧', '營收頁加上天氣', '想看下雨天生意差多少。', '吳老闆', PlatformWishStatus.declined, 12,
          reply: '天氣資料要另外付費，先不做；之後有免費的來源再評估。', repliedDaysAgo: 9),
      w('pa-6', 's-alley', '巷口小館', '盤點可以掃條碼', '盤點時用手機掃酒瓶上的條碼，直接跳到那個品項。', '陳店長', PlatformWishStatus.done, 25,
          reply: '已經做好了：盤點畫面右上角多一個掃描按鈕。', repliedDaysAgo: 8),
    ];
  }();
  static const _demoStoreNames = {'yc': '隱城', 'xc': '小城外'};
  List<PlatformAdminWish> _adminAll() => [
    ..._adminOthers,
    for (final e in _demoWishes.entries)
      for (final w in e.value)
        PlatformAdminWish(wish: w, storeId: e.key, storeName: _demoStoreNames[e.key] ?? '示範店',
            repliedAtRaw: w.repliedAt?.toUtc().toIso8601String()),
  ]..sort((a, b) => b.wish.createdAt.compareTo(a.wish.createdAt));

  @override
  Future<bool> platformAdminMe() async => _isPlatformAdmin;

  @override
  Future<List<PlatformAdminWish>> platformAdminWishes() async {
    if (!_isPlatformAdmin) throw Exception('message: 只有平台管理者能看所有店的許願單,');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _adminAll();
  }

  @override
  Future<Map<PlatformWishStatus, int>> platformAdminWishCounts() async {
    if (!_isPlatformAdmin) throw Exception('message: 只有平台管理者能看所有店的許願單,');
    final all = _adminAll();
    return {for (final s in PlatformWishStatus.values) s: all.where((w) => w.wish.status == s).length};
  }

  @override
  Future<void> platformAdminReply(PlatformAdminWish w, PlatformWishStatus status, String reply) async {
    if (!_isPlatformAdmin) throw Exception('message: 只有平台管理者能回覆許願單,');
    final err = validateAdminReply(reply);
    if (err != null) throw Exception('message: $err,');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final cur = _adminAll().where((x) => x.wish.id == w.wish.id).firstOrNull;
    if (cur == null) throw Exception('message: 找不到這則許願單,');
    if (cur.wish.status != w.wish.status || cur.repliedAtRaw != w.repliedAtRaw) {
      throw Exception('message: WISH_STALE：別人剛回覆過這則許願單，請重新整理,');
    }
    final r = reply.trim().isEmpty ? null : reply.trim();
    final changed = r != cur.wish.reply;
    final now = DateTime.now();
    final next = PlatformWish(
      id: cur.wish.id, title: cur.wish.title, body: cur.wish.body, authorName: cur.wish.authorName,
      status: status, reply: r, createdAt: cur.wish.createdAt,
      repliedAt: changed ? now : cur.wish.repliedAt,
    );
    final i = _adminOthers.indexWhere((x) => x.wish.id == cur.wish.id);
    if (i >= 0) {
      _adminOthers[i] = PlatformAdminWish(wish: next, storeId: cur.storeId, storeName: cur.storeName,
          repliedAtRaw: next.repliedAt?.toUtc().toIso8601String());
      return;
    }
    final list = _demoWishes[cur.storeId];
    final j = list?.indexWhere((x) => x.id == cur.wish.id) ?? -1;
    if (j >= 0) list![j] = next;
  }

  @override
  Future<String> uploadBookingAsset(
    String storeId,
    String kind,
    Uint8List bytes,
    String contentType,
  ) async {
    final path = newBookingAssetPath(
      storeId.length == 36 ? storeId : '00000000-0000-4000-8000-000000000000',
      kind,
      contentType == 'image/png'
          ? 'png'
          : contentType == 'image/webp'
          ? 'webp'
          : 'jpg',
    );
    demoBookingAssets[path] = bytes;
    return path;
  }

  @override
  Future<void> deleteBookingAsset(String path) async =>
      demoBookingAssets.remove(path);
  // 訂位搬家（ops 0148）：照資料庫的規則簡單模擬
  final _demoImports = <String, List<ImportBatch>>{};
  final _demoImportReq = <String, String>{};

  ImportResult _demoImportCheck(
    String storeId,
    List<ImportRow> rows, {
    String? batchId,
  }) {
    final n = DateTime.now().subtract(const Duration(hours: 6));
    final today = DateTime(n.year, n.month, n.day);
    final errors = <Map<String, dynamic>>[],
        skipped = <Map<String, dynamic>>[],
        ok = <(ImportRow, DateTime)>[];
    final seen = <String>{};
    final existing = _demoRes[storeId] ??= _seedReservations(storeId);
    String nameKey(String v) => v.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      String? msg;
      final d = DateTime.tryParse(r.date);
      if (r.date.isEmpty) {
        msg = '沒有日期';
      } else if (d == null ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(r.date)) {
        msg = '日期看不懂（請寫成 2026-12-24）';
      } else if (d.isBefore(today)) {
        msg = '日期已經過了（只能匯入今天以後的訂位）';
      } else if (d.isAfter(today.add(const Duration(days: 366)))) {
        msg = '日期超過一年以後';
      } else if (r.time.isEmpty) {
        msg = '沒有時間';
      } else if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(r.time)) {
        msg = '時間看不懂（請寫成 19:30）';
      } else if ((int.tryParse(r.party) ?? 0) < 1 ||
          int.parse(r.party) > 9999) {
        msg = '人數要是 1～9999 的整數';
      } else if (r.name.trim().isEmpty) {
        msg = '沒有姓名';
      } else if (r.name.trim().length > 40) {
        msg = '姓名超過 40 個字';
      } else if (r.phone.isNotEmpty &&
          !RegExp(r'^[0-9+() -]{8,20}$').hasMatch(r.phone)) {
        msg = '電話格式不對（8～20 個數字，可以有 + ( ) - 空白）';
      } else if (r.email.isNotEmpty &&
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(r.email)) {
        msg = 'Email 格式不對';
      } else if (r.note.length > 200) {
        msg = '備註超過 200 個字';
      } else if (r.lang.isNotEmpty && !['zh', 'en', 'ja'].contains(r.lang)) {
        msg = '語言只能是 zh、en、ja';
      }
      if (msg != null) {
        errors.add({'row': i + 1, 'message': msg});
        continue;
      }
      final digits = phoneDigitsOf(r.phone);
      final key =
          '${r.date} ${r.time} ${digits.isNotEmpty ? 'p:$digits' : 'n:${nameKey(r.name)}'}';
      if (!seen.add(key)) {
        skipped.add({'row': i + 1, 'reason': '檔案裡前面已經有同一筆'});
        continue;
      }
      final dup = existing.any(
        (x) =>
            x.date == d &&
            x.time == r.time &&
            (x.status == 'confirmed' || x.status == 'arrived') &&
            (digits.isNotEmpty
                ? phoneDigitsOf(x.phone) == digits
                : x.phone.isEmpty && nameKey(x.name) == nameKey(r.name)),
      );
      if (dup) {
        skipped.add({'row': i + 1, 'reason': '這個時間已經有這位客人的訂位'});
        continue;
      }
      ok.add((r, d!));
    }
    if (batchId == null || errors.isNotEmpty || ok.isEmpty) {
      return ImportResult.fromJson({
        'ready': ok.length,
        'errors': errors,
        'skipped': skipped,
      }, rows);
    }
    for (final (r, d) in ok) {
      existing.add(
        Reservation(
          id: '$storeId-imp${existing.length}',
          date: d,
          time: r.time,
          party: int.parse(r.party),
          name: r.name.trim(),
          phone: r.phone,
          email: r.email.isEmpty ? null : r.email,
          note: r.note.isEmpty ? null : r.note,
          status: 'confirmed',
          source: 'app',
          createdAt: DateTime.now(),
          lang: r.lang.isEmpty ? 'zh' : r.lang,
          importBatchId: batchId,
        ),
      );
    }
    return ImportResult.fromJson({
      'batch': batchId,
      'inserted': ok.length,
      'errors': errors,
      'skipped': skipped,
    }, rows);
  }

  @override
  Future<ImportResult> previewReservationImport(
    String storeId,
    List<ImportRow> rows,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (rows.length > 2000) throw Exception('一次最多匯入 2000 筆，請分成幾個檔案');
    return _demoImportCheck(storeId, rows);
  }

  @override
  Future<ImportResult> importReservations(
    String storeId,
    List<ImportRow> rows,
    String? fileName,
    String requestId,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final prev = _demoImportReq[requestId];
    if (prev != null) {
      final b = _demoImports[storeId]!.firstWhere((x) => x.id == prev);
      return ImportResult(batchId: b.id, inserted: b.inserted, repeat: true);
    }
    final id = 'demo-batch-${DateTime.now().microsecondsSinceEpoch}';
    final res = _demoImportCheck(storeId, rows, batchId: id);
    if (res.batchId == null) return res;
    _demoImportReq[requestId] = id;
    (_demoImports[storeId] ??= []).insert(
      0,
      ImportBatch(
        id: id,
        createdAt: DateTime.now(),
        fileName: fileName,
        total: rows.length,
        inserted: res.inserted,
        skipped: res.skipped.length,
      ),
    );
    return res;
  }

  // ---------------- 營收搬家（ops 0168，示範版：照資料庫的規則在記憶體裡檢查） ----------------
  final _demoRevImports = <String, List<RevenueImportBatch>>{
    'yc': [
      RevenueImportBatch(
        id: 'demo-rev-batch-old',
        createdAt: DateTime.now().subtract(const Duration(days: 3, hours: 2)),
        fileName: '舊系統匯出_試匯.csv',
        total: 31,
        inserted: 30,
        skipped: 1,
        dateFrom: DateTime(DateTime.now().year - 1, 1, 1),
        dateTo: DateTime(DateTime.now().year - 1, 1, 31),
        undoneAt: DateTime.now().subtract(const Duration(days: 3)),
        undoneCount: 30,
        undoneKept: 0,
      ),
    ],
  };
  final _demoRevImportReq = <String, String>{};

  RevenueImportResult _demoRevCheck(String storeId, List<RevenueImportRow> rows, {String? batchId}) {
    final multi = StoreFeatures.of(_demoStoreNames[storeId] ?? '').multiLineRevenue;
    final n = DateTime.now().subtract(const Duration(hours: 6));
    final today = DateTime(n.year, n.month, n.day);
    final have = {for (final e in _revList(storeId)) DateTime(e.bizDate.year, e.bizDate.month, e.bizDate.day)};
    const labels = {
      'cash': '現金', 'credit_card': '刷卡', 'amex': 'AE', 'deposit': '訂金', 'drinks_revenue': '酒水',
      'food_revenue': '餐食', 'project_amount': '專案', 'coffee_revenue': '咖啡', 'ramen_revenue': '拉麵',
    };
    final errors = <Map<String, dynamic>>[], skipped = <Map<String, dynamic>>[], warnings = <Map<String, dynamic>>[];
    final ok = <(RevenueImportRow, DateTime, Map<String, double>, int)>[];
    final seen = <DateTime>{};
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      String? msg;
      final d = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(r.date) ? DateTime.tryParse(r.date) : null;
      if (r.date.isEmpty) {
        msg = '沒有日期';
      } else if (d == null) {
        msg = '日期看不懂（請寫成 2026-10-24）';
      } else if (d.isAfter(today)) {
        msg = '日期還沒到（只能匯入今天以前的營收）';
      } else if (d.year < 2000) {
        msg = '日期太早（2000 年以後）';
      }
      final g = r.v('guests').isEmpty ? 0 : int.tryParse(r.v('guests'));
      if (msg == null && (g == null || g < 0 || g > 99999)) msg = '來客數要是 0～99999 的整數';
      final amounts = <String, double>{};
      if (msg == null) {
        for (final k in labels.keys) {
          final raw = r.v(k);
          final v = raw.isEmpty ? 0.0 : double.tryParse(raw);
          if (v == null) {
            msg = '${labels[k]}看不懂（請填數字）';
            break;
          }
          if (v < 0 || v > 100000000 || (v * 100).roundToDouble() != v * 100) {
            msg = '${labels[k]}要是 0～1 億、最多兩位小數';
            break;
          }
          amounts[k] = v;
        }
      }
      if (msg == null && !multi && ((amounts['coffee_revenue'] ?? 0) != 0 || (amounts['ramen_revenue'] ?? 0) != 0)) {
        msg = '這家店的營收沒有分咖啡、拉麵，請把那兩欄留空';
      }
      if (msg == null && r.v('note').length > 200) msg = '備註超過 200 個字';
      if (msg != null) {
        errors.add({'row': i + 1, 'message': msg});
        continue;
      }
      final pay = ['cash', 'credit_card', 'amex', 'deposit'].fold<double>(0, (a, k) => a + amounts[k]!);
      final lines = ['drinks_revenue', 'food_revenue', 'project_amount', 'coffee_revenue', 'ramen_revenue']
          .fold<double>(0, (a, k) => a + amounts[k]!);
      if (pay == 0 && lines == 0 && g == 0) {
        skipped.add({'row': i + 1, 'reason': '這天全部是 0（公休不用匯入）'});
        continue;
      }
      if (seen.contains(d)) {
        skipped.add({'row': i + 1, 'reason': '檔案裡前面已經有這一天'});
        continue;
      }
      seen.add(d!);
      if (have.contains(d)) {
        skipped.add({'row': i + 1, 'reason': '這天已經有營收資料（不會蓋掉）'});
        continue;
      }
      if (lines > 0 && lines != pay) {
        warnings.add({'row': i + 1, 'message': '營收分類合計 ${_fmtNum(lines)} 跟收款合計 ${_fmtNum(pay)} 不一樣（照樣匯入）'});
      }
      ok.add((r, d, amounts, g!));
    }
    DateTime? from, to;
    for (final o in ok) {
      if (from == null || o.$2.isBefore(from)) from = o.$2;
      if (to == null || o.$2.isAfter(to)) to = o.$2;
    }
    if (from != null && to!.difference(from).inDays > 732) {
      errors.add({'row': 0, 'message': '檔案的日期從 ${_ymd(from)} 到 ${_ymd(to)}，一次最多 2 年，請分成幾個檔案'});
    }
    String? day(DateTime? d) => d == null ? null : _ymd(d);
    if (batchId == null || errors.isNotEmpty || ok.isEmpty) {
      return RevenueImportResult.fromJson({
        'batch': null,
        'ready': errors.isEmpty ? ok.length : 0,
        'errors': errors,
        'skipped': skipped,
        'warnings': warnings,
        'date_from': day(from),
        'date_to': day(to),
      }, rows);
    }
    final list = _revList(storeId);
    for (final o in ok) {
      final a = o.$3;
      list.add(RevenueEntry(
        id: 'rev${++_seq}',
        bizDate: o.$2,
        guests: o.$4,
        cash: a['cash']!,
        creditCard: a['credit_card']!,
        amex: a['amex']!,
        deposit: a['deposit']!,
        drinks: a['drinks_revenue']!,
        food: a['food_revenue']!,
        project: a['project_amount']!,
        coffee: a['coffee_revenue']!,
        ramen: a['ramen_revenue']!,
        note: o.$1.v('note').isEmpty ? null : o.$1.v('note'),
        fileImportId: batchId,
      ));
    }
    return RevenueImportResult.fromJson({
      'batch': batchId,
      'inserted': ok.length,
      'skipped': skipped,
      'warnings': warnings,
      'date_from': day(from),
      'date_to': day(to),
    }, rows);
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _fmtNum(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  Future<RevenueImportResult> previewRevenueImport(String storeId, List<RevenueImportRow> rows) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (rows.length > revenueImportMax) throw Exception('一次最多匯入 $revenueImportMax 天，請分成幾個檔案');
    return _demoRevCheck(storeId, rows);
  }

  @override
  Future<RevenueImportResult> importRevenue(
      String storeId, List<RevenueImportRow> rows, String? fileName, String requestId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final prev = _demoRevImportReq[requestId];
    if (prev != null) {
      final b = _demoRevImports[storeId]!.firstWhere((x) => x.id == prev);
      return RevenueImportResult(batchId: b.id, inserted: b.inserted, repeat: true);
    }
    final id = 'demo-rev-batch-${DateTime.now().microsecondsSinceEpoch}';
    final res = _demoRevCheck(storeId, rows, batchId: id);
    if (res.batchId == null) return res;
    _demoRevImportReq[requestId] = id;
    (_demoRevImports[storeId] ??= []).insert(
      0,
      RevenueImportBatch(
        id: id,
        createdAt: DateTime.now(),
        fileName: fileName,
        total: rows.length,
        inserted: res.inserted,
        skipped: res.skipped.length,
        dateFrom: res.dateFrom!,
        dateTo: res.dateTo!,
      ),
    );
    return res;
  }

  @override
  Future<List<RevenueImportBatch>> revenueImports(String storeId) async => [...?_demoRevImports[storeId]];

  @override
  Future<(int, int)> undoRevenueImport(String batchId) async {
    for (final e in _demoRevImports.entries) {
      final i = e.value.indexWhere((b) => b.id == batchId);
      if (i < 0) continue;
      final b = e.value[i];
      if (b.undoneAt != null) throw Exception('這一批已經復原過了');
      final list = _revList(e.key);
      final before = list.length;
      list.removeWhere((x) => x.fileImportId == batchId);
      final deleted = before - list.length;
      final kept = (b.inserted - deleted).clamp(0, b.inserted);
      e.value[i] = RevenueImportBatch(
        id: b.id,
        createdAt: b.createdAt,
        fileName: b.fileName,
        total: b.total,
        inserted: b.inserted,
        skipped: b.skipped,
        dateFrom: b.dateFrom,
        dateTo: b.dateTo,
        undoneAt: DateTime.now(),
        undoneCount: deleted,
        undoneKept: kept,
      );
      return (deleted, kept);
    }
    throw Exception('找不到這一批匯入，或你沒有權限');
  }

  @override
  Future<List<RevenueEntry>> allRevenueEntries(String storeId) async =>
      List.of(_revList(storeId))..sort((a, b) => a.bizDate.compareTo(b.bizDate));

  @override
  Future<List<ImportBatch>> reservationImports(String storeId) async => [
    ...?_demoImports[storeId],
  ];

  @override
  Future<int> undoReservationImport(String batchId) async {
    final n = DateTime.now().subtract(const Duration(hours: 6));
    final today = DateTime(n.year, n.month, n.day);
    for (final e in _demoImports.entries) {
      final i = e.value.indexWhere((b) => b.id == batchId);
      if (i < 0) continue;
      final b = e.value[i];
      if (b.undoneAt != null) throw Exception('這一批已經復原過了');
      var count = 0;
      final list = _demoRes[e.key] ?? [];
      for (var k = 0; k < list.length; k++) {
        final r = list[k];
        if (r.importBatchId == batchId &&
            r.status == 'confirmed' &&
            !r.date.isBefore(today)) {
          list[k] = r.copyWith(status: 'cancelled', hiddenAt: DateTime.now());
          count++;
        }
      }
      e.value[i] = ImportBatch(
        id: b.id,
        createdAt: b.createdAt,
        fileName: b.fileName,
        total: b.total,
        inserted: b.inserted,
        skipped: b.skipped,
        undoneAt: DateTime.now(),
        undoneCount: count,
      );
      return count;
    }
    throw Exception('找不到這一批匯入，或你沒有權限');
  }

  @override
  Future<List<Reservation>> allReservations(String storeId) async => [
    ...(_demoRes[storeId] ??= _seedReservations(storeId)),
  ];

  @override
  Future<List<Reservation>> reservations(
    String storeId,
    DateTime from,
    DateTime to,
  ) async => (_demoRes[storeId] ??= _seedReservations(
    storeId,
  )).where((r) => !r.date.isBefore(from) && !r.date.isAfter(to)).toList();

  /// 示範用的今天訂位（時間軸、座位圖看得到東西；2026-11-01）
  List<Reservation> _seedReservations(String storeId) {
    final n = DateTime.now().subtract(const Duration(hours: 6));
    final day = DateTime(n.year, n.month, n.day);
    final now = DateTime.now();
    Reservation mk(
      int i,
      String time,
      int party,
      String name,
      List<String> tables, {
      DateTime? seated,
      bool walkIn = false,
      String? note,
      String? ref,
    }) => Reservation(
      id: '$storeId-seed$i',
      date: day,
      time: time,
      party: party,
      name: name,
      phone: '0912-000-00$i',
      status: seated != null ? 'arrived' : 'confirmed',
      source: walkIn ? 'app' : 'web',
      createdAt: now,
      tableIds: tables,
      seatedAt: seated,
      walkIn: walkIn,
      note: note,
      ref: ref,
    );
    return [
      mk(
        1,
        '19:00',
        2,
        '林小姐',
        ['A1', 'A2'],
        seated: now.subtract(const Duration(minutes: 40)),
        ref: 'google',
      ),
      mk(
        2,
        '19:30',
        4,
        '陳先生',
        ['S1'],
        seated: now.subtract(const Duration(minutes: 15)),
        note: '慶生，要蛋糕盤',
        ref: 'ig',
      ),
      mk(3, '20:00', 2, '王先生', ['A5'], ref: 'google'),
      mk(4, '20:30', 3, 'Kenji', ['S3']),
      mk(5, '21:00', 1, '現場', ['A8'], walkIn: true),
      mk(6, '21:30', 2, '張小姐', const []),
    ];
  }

  @override
  Future<void> addReservation(
    String storeId, {
    required DateTime date,
    required String time,
    required int party,
    required String name,
    required String phone,
    String? email,
    String? note,
    List<String> tableIds = const [],
  }) async {
    final list = _demoRes.putIfAbsent(storeId, () => []);
    list.add(
      Reservation(
        id: '$storeId-${list.length}',
        date: date,
        time: time,
        party: party,
        name: name,
        phone: phone,
        email: email,
        note: note,
        status: 'confirmed',
        source: 'app',
        createdAt: DateTime.now(),
        tableIds: tableIds,
      ),
    );
  }

  final _demoSpecial = <String, Map<String, ReservationSpecialDay>>{};
  final _demoGuests = <String, Map<String, GuestProfile>>{};
  @override
  Future<List<ReservationSpecialDay>> specialDays(
    String storeId,
    DateTime from,
    DateTime to,
  ) async =>
      (_demoSpecial[storeId]?.values ?? const <ReservationSpecialDay>[])
          .where((d) => !d.day.isBefore(from) && !d.day.isAfter(to))
          .toList()
        ..sort((a, b) => a.day.compareTo(b.day));
  @override
  Future<void> saveSpecialDay(String storeId, ReservationSpecialDay d) async =>
      (_demoSpecial[storeId] ??= {})[d.day.toIso8601String().substring(0, 10)] =
          d;
  @override
  Future<void> deleteSpecialDay(String storeId, DateTime day) async =>
      _demoSpecial[storeId]?.remove(day.toIso8601String().substring(0, 10));
  @override
  Future<Map<String, GuestStats>> guestStats(
    String storeId,
    Set<String> phoneDigits,
  ) async {
    final all = _demoRes[storeId] ?? const <Reservation>[];
    final out = <String, GuestStats>{};
    for (final p in phoneDigits) {
      final prof = _demoGuests[storeId]?[p];
      final reset = prof?.noshowResetAt;
      final resetDay = reset == null
          ? null
          : DateTime(reset.year, reset.month, reset.day);
      out[p] = GuestStats(
        all
            .where((r) => phoneDigitsOf(r.phone) == p && r.status == 'arrived')
            .length,
        all
            .where(
              (r) =>
                  phoneDigitsOf(r.phone) == p &&
                  r.status == 'no_show' &&
                  (resetDay == null || r.date.isAfter(resetDay)),
            )
            .length,
        prof,
      );
    }
    return out;
  }

  @override
  Future<void> saveGuestProfile(
    String storeId,
    GuestProfile g, {
    bool resetNoshow = false,
  }) async {
    final m = _demoGuests[storeId] ??= {};
    // 和正式資料庫一樣：解除時記下現在時間，之後只算那天以後的未到；沒解除就保留原本的解除時間（Codex 審查）
    m[g.phoneDigits] = GuestProfile(
      phoneDigits: g.phoneDigits,
      tags: g.tags,
      note: g.note,
      noshowResetAt: resetNoshow
          ? DateTime.now()
          : m[g.phoneDigits]?.noshowResetAt,
    );
  }

  @override
  Future<void> decidePartyRequest(
    String id,
    bool approve,
    int expectedParty,
  ) async {
    for (final list in _demoRes.values) {
      final i = list.indexWhere((r) => r.id == id);
      if (i < 0) continue;
      final r = list[i];
      list[i] = r.copyWith(
        party: approve ? (r.requestedParty ?? r.party) : r.party,
        partyRequestStatus: approve ? 'approved' : 'rejected',
      );
      return;
    }
  }

  @override
  Future<void> updateReservation(String id, Map<String, dynamic> values) async {
    for (final list in _demoRes.values) {
      final i = list.indexWhere((r) => r.id == id);
      if (i < 0) continue;
      final r = list[i];
      final status = values['status'] as String? ?? r.status;
      final seated = status == 'arrived';
      list[i] = r.copyWith(
        status: status,
        note: values['note'] as String?,
        clearNote: values.containsKey('note') && values['note'] == null,
        tableIds: values.containsKey('table_ids')
            ? [for (final x in values['table_ids'] as List) x as String]
            : null,
        seatedAt: seated && r.seatedAt == null ? DateTime.now() : null,
        clearSeated: !seated,
        clearedAt: values['cleared_at'] != null && r.clearedAt == null
            ? DateTime.now()
            : null,
        clearCleared:
            !seated ||
            (values.containsKey('cleared_at') && values['cleared_at'] == null),
        hiddenAt:
            status == 'cancelled' &&
                values['hidden_at'] != null &&
                r.hiddenAt == null
            ? DateTime.now()
            : null,
        clearHidden:
            status != 'cancelled' ||
            (values.containsKey('hidden_at') && values['hidden_at'] == null),
      );
      return;
    }
  }

  final Map<String, List<ReservationTable>> _demoTables = {};
  @override
  Future<List<ReservationTable>> reservationTables(String storeId) async =>
      [
        ...(_demoTables[storeId] ??= [
          // 照隱城 iCHEF 座位表的樣子排（2026-11-01）：吧台 A1～A8 一排、A9～A12 方桌一直排、B／C／D／E 小圓桌
          for (var i = 1; i <= 8; i++)
            ReservationTable(
              id: 'A$i',
              name: 'A$i',
              seats: 1,
              combinable: true,
              sort: i,
              posX: 8 - i,
              posY: 2,
              floor: '2F',
            ),
          for (var i = 9; i <= 12; i++)
            ReservationTable(
              id: 'A$i',
              name: 'A$i',
              seats: 2,
              sort: i,
              posX: 4,
              posY: i - 6,
              shape: 'square',
              floor: '2F',
            ),
          const ReservationTable(
            id: 'F1',
            name: 'F1',
            seats: 2,
            sort: 71,
            posX: 1,
            posY: 0,
            shape: 'square',
            floor: '2F',
          ),
          for (var i = 1; i <= 4; i++)
            ReservationTable(
              id: 'B$i',
              name: 'B$i',
              seats: 1,
              combinable: true,
              sort: 20 + i,
              posX: 5 + i,
              posY: 0,
              floor: '2F',
            ),
          const ReservationTable(
            id: 'B5',
            name: 'B5',
            seats: 1,
            combinable: true,
            sort: 25,
            posX: 8,
            posY: 1,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'B6',
            name: 'B6',
            seats: 1,
            combinable: true,
            sort: 26,
            posX: 9,
            posY: 1,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'C1',
            name: 'C1',
            seats: 1,
            combinable: true,
            sort: 31,
            posX: 8,
            posY: 4,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'C2',
            name: 'C2',
            seats: 1,
            combinable: true,
            sort: 32,
            posX: 9,
            posY: 3,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'C3',
            name: 'C3',
            seats: 1,
            combinable: true,
            sort: 33,
            posX: 9,
            posY: 4,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'D1',
            name: 'D1',
            seats: 1,
            combinable: true,
            sort: 41,
            posX: 8,
            posY: 5,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'D2',
            name: 'D2',
            seats: 1,
            combinable: true,
            sort: 42,
            posX: 9,
            posY: 5,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'D3',
            name: 'D3',
            seats: 1,
            combinable: true,
            sort: 43,
            posX: 8,
            posY: 6,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'D4',
            name: 'D4',
            seats: 1,
            combinable: true,
            sort: 44,
            posX: 9,
            posY: 6,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'E1',
            name: 'E1',
            seats: 1,
            combinable: true,
            sort: 51,
            posX: 6,
            posY: 5,
            floor: '2F',
          ),
          const ReservationTable(
            id: 'E2',
            name: 'E2',
            seats: 1,
            combinable: true,
            sort: 52,
            posX: 6,
            posY: 6,
            floor: '2F',
          ),
          // 一樓：沙發區 S1～S4、小圓桌 S5～S7（照 iCHEF 一樓座位表）
          const ReservationTable(
            id: 'S1',
            name: 'S1',
            seats: 10,
            combinable: true,
            sort: 61,
            posX: 3,
            posY: 3,
            floor: '1F',
          ),
          const ReservationTable(
            id: 'S2',
            name: 'S2',
            seats: 10,
            combinable: true,
            sort: 62,
            posX: 5,
            posY: 3,
            floor: '1F',
          ),
          const ReservationTable(
            id: 'S3',
            name: 'S3',
            seats: 10,
            combinable: true,
            sort: 63,
            posX: 3,
            posY: 5,
            floor: '1F',
          ),
          const ReservationTable(
            id: 'S4',
            name: 'S4',
            seats: 10,
            combinable: true,
            sort: 64,
            posX: 5,
            posY: 5,
            floor: '1F',
          ),
          for (var i = 5; i <= 7; i++)
            ReservationTable(
              id: 'S$i',
              name: 'S$i',
              seats: 1,
              combinable: true,
              sort: 60 + i,
              posX: i - 2,
              posY: 0,
              floor: '1F',
            ),
          // 只有後天加開的一張（ops 0133 示範）
          ReservationTable(
            id: 'X1',
            name: '加開1',
            seats: 6,
            sort: 90,
            floor: '1F',
            onlyDate: _demoDay(2),
          ),
        ]),
      ]..sort(
        (a, b) => a.sort != b.sort
            ? a.sort.compareTo(b.sort)
            : a.name.compareTo(b.name),
      );
  @override
  Future<void> saveReservationTable(String storeId, ReservationTable t) async {
    final list = _demoTables[storeId] ??= [];
    final i = list.indexWhere((x) => x.id == t.id);
    final old = i >= 0 ? list[i] : null;
    final v = ReservationTable(
      id: t.id.isEmpty ? 'T${list.length + 1}' : t.id,
      name: t.name,
      seats: t.seats,
      combinable: t.combinable,
      sort: t.sort,
      active: t.active,
      posX: old?.floor == t.floor ? old?.posX : null,
      posY: old?.floor == t.floor ? old?.posY : null,
      w: old?.w ?? 1,
      h: old?.h ?? 1,
      shape: old?.shape ?? 'round',
      floor: t.floor,
      onlyDate: old?.onlyDate ?? t.onlyDate,
    );
    if (i < 0) {
      list.add(v);
    } else {
      list[i] = v;
    }
  }

  @override
  Future<void> deleteReservationTable(String tableId) async {
    for (final list in _demoTables.values) {
      final i = list.indexWhere((x) => x.id == tableId);
      if (i < 0) continue;
      final t = list[i];
      list[i] = ReservationTable(
        id: t.id,
        name: t.name,
        seats: t.seats,
        combinable: t.combinable,
        sort: t.sort,
        active: false,
        posX: t.posX,
        posY: t.posY,
        w: t.w,
        h: t.h,
        shape: t.shape,
        floor: t.floor,
        deleted: true,
        onlyDate: t.onlyDate,
      );
    }
  }

  static DateTime _demoDay(int plus) {
    final n = taipeiNow();
    return DateTime(n.year, n.month, n.day + plus);
  }

  late final List<TableDayOff> _demoDaysOff = [
    TableDayOff('A12', _demoDay(2)),
    TableDayOff('A12', _demoDay(5)),
  ];
  @override
  Future<List<TableDayOff>> tableDaysOff(
    String storeId,
    DateTime from,
    DateTime to,
  ) async {
    final ids = {
      for (final t in _demoTables[storeId] ?? const <ReservationTable>[]) t.id,
    };
    final f = DateTime(from.year, from.month, from.day),
        e = DateTime(to.year, to.month, to.day);
    return [
      for (final o in _demoDaysOff)
        if (ids.contains(o.tableId) &&
            !o.date.isBefore(f) &&
            !o.date.isAfter(e))
          o,
    ]..sort((a, b) => a.date.compareTo(b.date));
  }

  @override
  Future<void> setTableDayOff(String tableId, DateTime date, bool off) async {
    final d = DateTime(date.year, date.month, date.day);
    _demoDaysOff.removeWhere((o) => o.tableId == tableId && o.date == d);
    if (off) _demoDaysOff.add(TableDayOff(tableId, d));
  }

  @override
  Future<void> saveTableLayout(
    String storeId,
    List<ReservationTable> tables,
  ) async {
    final list = _demoTables[storeId] ??= [];
    for (final t in tables) {
      final i = list.indexWhere((x) => x.id == t.id);
      if (i >= 0)
        list[i] = list[i].copyWith(
          posX: t.posX,
          posY: t.posY,
          w: t.w,
          h: t.h,
          shape: t.shape,
          floor: t.floor,
          clearPos: !t.placed,
        );
    }
  }

  @override
  Future<void> addWalkIn(
    String storeId, {
    required DateTime date,
    required String time,
    required int party,
    required String name,
    required List<String> tableIds,
  }) async {
    final list = _demoRes.putIfAbsent(storeId, () => []);
    list.add(
      Reservation(
        id: '$storeId-${list.length}',
        date: date,
        time: time,
        party: party,
        name: name,
        phone: '',
        status: 'arrived',
        source: 'app',
        createdAt: DateTime.now(),
        tableIds: tableIds,
        seatedAt: DateTime.now(),
        walkIn: true,
      ),
    );
  }

  @override
  Future<List<AppNotification>> reservationEvents(String storeId) async => [
    AppNotification(
      id: 901,
      kind: 'reservation',
      title: '新訂位',
      body: '王 先生・10/19 20:00・2 位',
      actorName: '客人',
      createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    ),
  ];

  // ---------------- 功能許願（0069）示範：送出後幾秒變成「修改好了」 ----------------
  final List<ChangeRequest> _changes = [];
  final Map<String, List<ChangeMessage>> _changeMsgs = {};
  int _changeUsed = 0;
  void _changeMsg(String id, String kind, String who, String body) =>
      (_changeMsgs[id] ??= []).add(
        ChangeMessage(
          id: ++_seq,
          kind: kind,
          authorName: who,
          body: body,
          createdAt: DateTime.now(),
        ),
      );
  void _changeSet(String id, ChangeRequest Function(ChangeRequest) f) {
    final i = _changes.indexWhere((c) => c.id == id);
    if (i >= 0) _changes[i] = f(_changes[i]);
  }

  void _changeRun(String id) {
    _changeSet(
      id,
      (c) => c.copyWith(status: ChangeStatus.running, runCount: c.runCount + 1),
    );
    Future.delayed(const Duration(seconds: 4), () {
      _changeSet(
        id,
        (c) => c.copyWith(
          status: ChangeStatus.ready,
          previewUrl: 'https://example.com/preview/',
          prNumber: 1,
        ),
      );
      _changeMsg(id, 'claude', '後臺', '（示範）已照需求修改，請點「看預覽」確認。');
    });
  }

  @override
  Future<List<ChangeRequest>> changeRequests(String storeId) async =>
      _changes.where((c) => c.storeId == storeId).toList().reversed.toList();
  @override
  Future<List<ChangeMessage>> changeMessages(String requestId) async =>
      List.of(_changeMsgs[requestId] ?? const []);
  @override
  Future<ChangeQuota> changeQuota(String storeId) async =>
      ChangeQuota(_changeUsed, 10);
  @override
  Future<String> createChangeRequest(
    String storeId,
    String body, {
    List<String> photos = const [],
  }) async {
    final id = 'cr-${++_seq}';
    _changeUsed++;
    _changes.add(
      ChangeRequest(
        id: id,
        storeId: storeId,
        title: body.trim().split('\n').first,
        requestedBy: 'demo',
        requesterName: '示範老闆',
        status: ChangeStatus.queued,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    _changeMsg(id, 'request', '示範老闆', body.trim());
    _changeRun(id);
    return id;
  }

  @override
  Future<Uint8List> changePhoto(String photoId) async => Uint8List(0);
  @override
  Future<void> followupChangeRequest(
    String requestId,
    String body, {
    List<String> photos = const [],
  }) async {
    _changeUsed++;
    _changeMsg(requestId, 'followup', '示範老闆', body.trim());
    _changeRun(requestId);
  }

  @override
  Future<void> submitChangeRequest(String requestId) async {
    _changeSet(requestId, (c) => c.copyWith(status: ChangeStatus.review));
    _changeMsg(requestId, 'system', '示範店長', '已送審，等老闆核准上線');
  }

  @override
  Future<void> approveChangeRequest(String requestId) async {
    _changeSet(requestId, (c) => c.copyWith(status: ChangeStatus.merged));
    _changeMsg(requestId, 'system', '後臺', '已上線（示範）');
  }

  @override
  Future<void> returnChangeRequest(String requestId, String reason) async {
    _changeSet(requestId, (c) => c.copyWith(status: ChangeStatus.ready));
    _changeMsg(requestId, 'system', '示範老闆', '老闆退回：$reason');
  }

  @override
  Future<void> cancelChangeRequest(String requestId) async =>
      _changeSet(requestId, (c) => c.copyWith(status: ChangeStatus.cancelled));
  @override
  Future<void> kickChangeRequests() async {}

  // ---------------- 打卡、員工資料（示範：只有隱城開放；資料都是虛構的） ----------------
  final _att = <MyAttendanceRecord>[];
  final _kiosks = <KioskInfo>[];
  final _hr = <String, Map<String, dynamic>>{};
  final _hire = <String, DateTime?>{};
  final _rates = <String, List<PayRate>>{};
  final _ident = <String, Map<String, String?>>{};
  // 班表名字綁定的帳號：f0＝示範帳號（老闆已確認）、f1＝小安的帳號（還沒確認）
  final _bound = <String, ({String user, String name})>{
    'f0': (user: 'demo-user', name: '示範'),
    'f1': (user: 'demo-f1', name: '小安'),
  };
  final _verified = <String>{'f0'};
  final _reviews = <String, List<PunchHistoryEntry>>{};
  bool get _bindingPending => _email.contains('unverified');

  @override
  Future<AttendanceMe?> attendanceMe(String storeId) async {
    final last = _att.where((r) => r.isPunch).lastOrNull;
    return AttendanceMe(
      enabled: storeId == 'yc',
      canManage: !_isStaff, // 小城外沒開打卡，老闆照樣管員工資料
      personId: _bindingPending ? null : 'f0',
      personName: _bindingPending ? null : _dn('f0', '阿明'),
      lastPunchType: last?.punchType,
      lastPunchedAt: last?.at,
      onShift: last?.punchType == 'in',
      serverTime: DateTime.now(),
      bindingPending: _bindingPending,
    );
  }

  @override
  Future<PunchResult> punch(PunchLink link) async {
    if (_bindingPending) throw Exception('message: 你在班表上的名字還沒經老闆確認，這次沒有打到卡,');
    final now = DateTime.now();
    final last = _att.where((r) => r.isPunch).lastOrNull;
    final dup = last != null && now.difference(last.at).inMinutes < 2;
    final type = dup
        ? last.punchType
        : (last?.punchType == 'in' ? 'out' : 'in');
    final biz = DateTime(now.year, now.month, now.day - (now.hour < 6 ? 1 : 0));
    final r = PunchResult(
      punchId: 'pu${_seq++}',
      storeName: '隱城',
      punchType: type,
      punchedAt: now,
      businessDate: biz,
      status: dup ? 'pending' : 'ok',
      flags: dup ? const ['duplicate'] : const [],
    );
    _att.add(
      MyAttendanceRecord(
        kind: 'punch',
        id: r.punchId,
        punchType: type,
        at: now,
        businessDate: biz,
        storeName: '隱城',
        status: r.status,
        flags: r.flags,
      ),
    );
    return r;
  }

  @override
  Future<List<MyAttendanceRecord>> myAttendance(
    String storeId,
    DateTime from,
    DateTime to,
  ) async => _att.reversed.toList();

  @override
  Future<String> requestAmendment(
    String storeId,
    String personId,
    String punchType,
    DateTime at,
    String reason, {
    bool fromSchedule = false,
  }) async {
    if (at.isAfter(DateTime.now())) throw Exception('message: 補登時間不能在未來,');
    final id = 'am${_seq++}';
    _att.add(
      MyAttendanceRecord(
        kind: 'amendment',
        id: id,
        punchType: punchType,
        at: at,
        storeName: '隱城',
        status: 'pending',
        note: reason,
      ),
    );
    return id;
  }

  void _setAmendment(String id, String status) {
    final i = _att.indexWhere((r) => r.id == id);
    if (i < 0) return;
    final a = _att[i];
    _att[i] = MyAttendanceRecord(
      kind: a.kind,
      id: a.id,
      punchType: a.punchType,
      at: a.at,
      storeName: a.storeName,
      status: status,
      note: a.note,
    );
  }

  @override
  Future<void> cancelAmendment(String id) async =>
      _setAmendment(id, 'cancelled');

  @override
  Future<void> decideAmendment(String id, bool approve, {String? note}) async =>
      _setAmendment(id, approve ? 'approved' : 'rejected');

  @override
  Future<void> reviewPunch(String punchId, bool confirm, String reason) async =>
      (_reviews[punchId] ??= []).add(
        PunchHistoryEntry(
          at: DateTime.now(),
          action: 'review',
          decision: confirm ? 'confirmed' : 'rejected',
          reason: reason,
          actorName: '示範',
        ),
      );

  String? _lastReview(String id) => _reviews[id]?.lastOrNull?.decision;

  @override
  Future<List<PunchHistoryEntry>> punchHistory(String punchId) async {
    final r = (await attendanceExport(
      'yc',
      _daysAgo(31),
      _daysAgo(0),
    )).where((e) => e.punchId == punchId).firstOrNull;
    return [
      if (r != null)
        PunchHistoryEntry(
          at: r.punchedAt,
          action: r.source == 'amendment' ? 'amendment_punch' : 'punch',
          decision: r.status,
          reason: r.flags,
          actorName: r.personName,
        ),
      ...?_reviews[punchId],
    ];
  }

  @override
  Future<List<AttendancePerson>> attendancePeople(
    String storeId,
    DateTime from,
    DateTime to,
  ) async {
    final m = await shiftMonth(storeId, DateTime.now());
    return [
      for (final p in m.people)
        if (p.active) AttendancePerson(personId: p.id, name: p.label),
      const AttendancePerson(
        personId: 'xc-demo',
        name: '阿傑',
        homeStoreName: '小城外',
        crossStore: true,
      ),
    ];
  }

  @override
  Future<List<AttendanceAnomaly>> attendanceAnomalies(
    String storeId,
    DateTime from,
    DateTime to,
  ) async => [
    AttendanceAnomaly(
      kind: 'missing_out',
      businessDate: _daysAgo(1),
      personId: 'f1',
      personName: _dn('f1', '小安'),
      punchId: 'demo1',
      at: DateTime.now().subtract(const Duration(hours: 30)),
      punchType: 'in',
      detail: '上班後 14 小時內沒有下班',
    ),
    AttendanceAnomaly(
      kind: 'pending',
      businessDate: _daysAgo(0),
      personId: 'p0',
      personName: _dn('p0', '小魚'),
      punchId: 'demo2',
      at: DateTime.now().subtract(const Duration(hours: 3)),
      punchType: 'in',
      detail: 'QR 碼過期',
    ),
    for (final a in _att.where(
      (r) => r.kind == 'amendment' && r.status == 'pending',
    ))
      AttendanceAnomaly(
        kind: 'amendment',
        businessDate:
            a.businessDate ?? DateTime(a.at.year, a.at.month, a.at.day),
        personId: 'f0',
        personName: _dn('f0', '阿明'),
        amendmentId: a.id,
        at: a.at,
        punchType: a.punchType,
        detail: a.note,
      ),
  ];

  @override
  Future<List<AttendanceSession>> attendanceSessions(
    String storeId,
    DateTime from,
    DateTime to,
  ) async {
    final d = _daysAgo(1);
    DateTime at(int h, int m) => DateTime(d.year, d.month, d.day, h, m);
    final demo2 = _lastReview('demo2') == 'confirmed';
    return [
      AttendanceSession(
        personId: 'f0',
        personName: _dn('f0', '阿明'),
        businessDate: d,
        inAt: at(18, 0),
        outAt: at(23, 30),
        minutes: 330,
      ),
      AttendanceSession(
        personId: 'p0',
        personName: _dn('p0', '小魚'),
        businessDate: d,
        inAt: at(19, 2),
        outAt: at(23, 0),
        minutes: 238,
        pending: !demo2,
      ),
    ];
  }

  // ---------- 打卡跟班表比對、加班申請（ops 0127） ----------
  /// 示範：班的時間（隱城的 V 平常 18:00-00:30、週五六 19:00-01:30）
  final _markTimes = <ShiftMarkTime>[
    const ShiftMarkTime(mark: 'V', timeRange: '18:00-00:30'),
    const ShiftMarkTime(mark: 'V', weekday: 5, timeRange: '19:00-01:30'),
    const ShiftMarkTime(mark: 'V', weekday: 6, timeRange: '19:00-01:30'),
  ];
  late final List<OvertimeRequest> _ot = [
    OvertimeRequest(
      id: 'ot1',
      personId: 'f1',
      personName: _dn('f1', '小安'),
      businessDate: _daysAgo(1),
      hours: 1.5,
      reason: '客人留到快兩點，收店晚了',
      afterTheFact: true,
      requestedByName: '小安',
      requestedAt: DateTime.now().subtract(const Duration(hours: 9)),
    ),
    OvertimeRequest(
      id: 'ot2',
      personId: 'f0',
      personName: _dn('f0', '阿明'),
      businessDate: _daysAgo(3),
      hours: 2.5,
      reason: '包場活動，事先排好',
      status: 'approved',
      approvedHours: 2.5,
      requestedByName: '示範',
      requestedAt: DateTime.now().subtract(const Duration(days: 5)),
      decidedByName: '示範店長',
      decidedAt: DateTime.now().subtract(const Duration(days: 4)),
      mine: true,
    ),
    OvertimeRequest(
      id: 'ot3',
      personId: 'p0',
      personName: _dn('p0', '小魚'),
      businessDate: _daysAgo(6),
      hours: 1,
      reason: '留下來盤點',
      afterTheFact: true,
      status: 'rejected',
      requestedByName: '小魚',
      requestedAt: DateTime.now().subtract(const Duration(days: 6)),
      decidedByName: '示範店長',
      decidedAt: DateTime.now().subtract(const Duration(days: 5)),
      decisionNote: '盤點排在上班時間內',
    ),
  ];

  DateTime _at(DateTime day, String hm) {
    final h = int.parse(hm.substring(0, 2)), m = int.parse(hm.substring(3));
    return DateTime(day.year, day.month, day.day + (h < 6 ? 1 : 0), h, m);
  }

  @override
  Future<List<ScheduleCheckRow>> scheduleCheck(
    String storeId,
    DateTime from,
    DateTime to,
  ) async {
    if (_isStaff) throw Exception('message: 只有老闆或店長能看打卡比對,');
    double? approved(String person, DateTime d) {
      final v = _ot
          .where(
            (o) =>
                o.personId == person &&
                o.businessDate == d &&
                o.status == 'approved',
          )
          .fold<double>(0, (a, o) => a + (o.approvedHours ?? 0));
      return v == 0 ? null : v;
    }

    bool pending(String person, DateTime d) => _ot.any(
      (o) => o.personId == person && o.businessDate == d && o.pending,
    );
    ScheduleCheckRow row(
      String id,
      String nick,
      int ago,
      String? mark,
      String? plan,
      String? inHm,
      String? outHm,
      List<String> issues, {
      int? ei,
      int? li,
      int? eo,
      int? lo,
    }) {
      final d = _daysAgo(ago);
      final p = plan?.split('-');
      return ScheduleCheckRow(
        businessDate: d,
        personId: id,
        personName: _dn(id, nick),
        mark: mark,
        planStart: p == null ? null : _at(d, p[0]),
        planEnd: p == null ? null : _at(d, p[1]),
        firstIn: inHm == null ? null : _at(d, inHm),
        lastOut: outHm == null ? null : _at(d, outHm),
        issues: issues,
        earlyInMin: ei,
        lateInMin: li,
        earlyOutMin: eo,
        lateOutMin: lo,
        otApproved: approved(id, d),
        otPending: pending(id, d),
      );
    }

    final vTime = markTimeOn(_markTimes, 'V', _daysAgo(1));
    final rows = [
      if (vTime != null)
        row('f1', '小安', 1, 'V', vTime, '18:02', '02:05', ['late_out'], lo: 95),
      if (vTime != null)
        row(
          'f0',
          '阿明',
          3,
          'V',
          markTimeOn(_markTimes, 'V', _daysAgo(3)),
          '17:55',
          '03:00',
          ['late_out'],
          lo: 150,
        ),
      row('p0', '小魚', 2, '19:00-00:30', '19:00-00:30', '19:45', '00:30', [
        'late_in',
      ], li: 45),
      row(
        'f2',
        '阿哲',
        4,
        'V',
        vTime == null ? null : markTimeOn(_markTimes, 'V', _daysAgo(4)),
        null,
        null,
        ['no_punch'],
      ),
      row('p1', '阿凱', 5, '休', null, '18:30', '23:40', ['no_schedule']),
      if (vTime != null)
        row(
          'f1',
          '小安',
          6,
          'V',
          markTimeOn(_markTimes, 'V', _daysAgo(6)),
          '17:20',
          '23:55',
          ['early_in', 'early_out'],
          ei: 40,
          eo: 35,
        ),
    ];
    return [
      for (final r in rows)
        if (!r.businessDate.isBefore(from) && !r.businessDate.isAfter(to)) r,
    ];
  }

  @override
  Future<List<OvertimeRequest>> overtimeList(
    String storeId,
    DateTime from,
    DateTime to,
  ) async => [
    for (final o in _ot)
      if (_isStaff
          ? o.personId == 'f0'
          : (o.pending ||
                (!o.businessDate.isBefore(from) &&
                    !o.businessDate.isAfter(to))))
        OvertimeRequest(
          id: o.id,
          personId: o.personId,
          personName: o.personName,
          businessDate: o.businessDate,
          hours: o.hours,
          reason: o.reason,
          afterTheFact: o.afterTheFact,
          status: o.status,
          approvedHours: o.approvedHours,
          requestedByName: o.requestedByName,
          requestedAt: o.requestedAt,
          decidedByName: o.decidedByName,
          decidedAt: o.decidedAt,
          decisionNote: o.decisionNote,
          mine: o.mine,
          canDecide: !_isStaff && o.pending && !(_isManager && o.mine),
        ),
  ];

  void _otSet(String id, String status, {double? approved, String? note}) {
    final i = _ot.indexWhere((o) => o.id == id);
    if (i < 0) return;
    final o = _ot[i];
    if (!o.pending) throw Exception('message: 這筆加班申請已經處理過了,');
    _ot[i] = OvertimeRequest(
      id: o.id,
      personId: o.personId,
      personName: o.personName,
      businessDate: o.businessDate,
      hours: o.hours,
      reason: o.reason,
      afterTheFact: o.afterTheFact,
      status: status,
      approvedHours: approved,
      requestedByName: o.requestedByName,
      requestedAt: o.requestedAt,
      decidedByName: '示範',
      decidedAt: DateTime.now(),
      decisionNote: note,
      mine: o.mine,
    );
  }

  @override
  Future<String> requestOvertime(
    String storeId,
    String personId,
    DateTime day,
    double hours,
    String reason,
  ) async {
    if (!isHalfHour(hours) || hours <= 0 || hours > 12)
      throw Exception('message: 加班時數以 0.5 小時為單位，一天最多 12 小時,');
    if (reason.trim().length < 2) throw Exception('message: 請寫加班的原因,');
    if (_ot.any(
      (o) => o.personId == personId && o.businessDate == day && o.pending,
    )) {
      throw Exception('message: 這天已經有一筆待審核的加班申請,');
    }
    final id = 'otn${_seq++}'; // 跟示範資料的 ot1～ot3 分開（Codex P2）
    final names = {
      for (final p in (await shiftMonth(storeId, day)).people) p.id: p.label,
    };
    _ot.add(
      OvertimeRequest(
        id: id,
        personId: personId,
        personName: names[personId] ?? _dn('f0', '阿明'),
        businessDate: day,
        hours: hours,
        reason: reason.trim(),
        afterTheFact: day.isBefore(_daysAgo(0)),
        requestedByName: '示範',
        requestedAt: DateTime.now(),
        mine: true,
      ),
    );
    return id;
  }

  @override
  Future<void> decideOvertime(
    String id,
    bool approve, {
    double? hours,
    String? note,
  }) async {
    if (_isStaff) throw Exception('message: 只有老闆或店長能審核加班,');
    final o = _ot.firstWhere((x) => x.id == id);
    if (_isManager && o.mine) throw Exception('message: 自己的加班要請老闆或另一位店長核准,');
    if (!approve && (note ?? '').trim().length < 2)
      throw Exception('message: 退回要寫原因,');
    _otSet(
      id,
      approve ? 'approved' : 'rejected',
      approved: approve ? hours ?? o.hours : null,
      note: note,
    );
    // 核准當下就帶進那個月還沒發布的薪資（月薪制、手動改過的不蓋掉）
    final month = DateTime(o.businessDate.year, o.businessDate.month);
    final k = _payKey(_otStore, month), r = _payRows[k]?[o.personId];
    if (approve &&
        r != null &&
        r.payType == 'monthly' &&
        _payStatus[k] == 'draft') {
      final a = _demoOt(o.personId, month);
      _payRows[k]![o.personId] = _payCalc(
        PayrollRow(
          personId: r.personId,
          name: r.name,
          slipName: r.slipName,
          kind: r.kind,
          status: r.status,
          payType: r.payType,
          baseAmount: r.baseAmount,
          autoDays: r.autoDays,
          autoHours: r.autoHours,
          daysOverride: r.daysOverride,
          hoursOverride: r.hoursOverride,
          otHours: r.otManual ? r.otHours : a.h1,
          otHours2: r.otManual ? r.otHours2 : a.h2,
          otMode: r.otMode,
          otRate: r.otRate,
          bonus: r.bonus,
          insurance: r.insurance,
          deduction: r.deduction,
          extras: r.extras,
          note: r.note,
          autoOtHours: a.h1,
          autoOtHours2: a.h2,
          otManual: r.otManual,
        ),
      );
    }
  }

  static const _otStore = 'yc'; // 示範：加班只在隱城

  @override
  Future<void> cancelOvertime(String id) async => _otSet(id, 'cancelled');

  @override
  Future<List<ShiftMarkTime>> shiftMarkTimes(String storeId) async =>
      storeId == 'yc' ? List.of(_markTimes) : const [];

  @override
  Future<void> saveShiftMarkTime(String storeId, ShiftMarkTime t) async {
    if (_isStaff) throw Exception('message: 只有老闆或店長能設班的時間,');
    _markTimes
      ..removeWhere((x) => x.mark == t.mark && x.weekday == t.weekday)
      ..add(t);
  }

  @override
  Future<void> deleteShiftMarkTime(
    String storeId,
    String mark,
    int weekday,
  ) async =>
      _markTimes.removeWhere((x) => x.mark == mark && x.weekday == weekday);

  @override
  Future<List<AttendanceExportRow>> attendanceExport(
    String storeId,
    DateTime from,
    DateTime to,
  ) async {
    final d = _daysAgo(1);
    final demo2 = _lastReview('demo2');
    return [
      AttendanceExportRow(
        businessDate: d,
        personName: _dn('f0', '阿明'),
        punchType: 'in',
        punchedAt: DateTime(d.year, d.month, d.day, 18),
        storeName: '隱城',
        source: 'qr',
        status: 'ok',
        flags: '',
        review: _lastReview('demo0'),
        counted: _lastReview('demo0') != 'rejected',
        punchId: 'demo0',
      ),
      AttendanceExportRow(
        businessDate: d,
        personName: _dn('p0', '小魚'),
        punchType: 'in',
        punchedAt: DateTime(d.year, d.month, d.day, 19, 2),
        storeName: '隱城',
        source: 'qr',
        status: 'pending',
        flags: 'code_expired',
        review: demo2,
        counted: demo2 == 'confirmed',
        punchId: 'demo2',
      ),
      for (final r in _att.where((r) => r.isPunch))
        AttendanceExportRow(
          businessDate: r.businessDate ?? r.at,
          personName: _dn('f0', '阿明'),
          punchType: r.punchType,
          punchedAt: r.at,
          storeName: '隱城',
          source: 'qr',
          status: r.status,
          flags: r.flags.join(' '),
          review: _lastReview(r.id),
          counted:
              _lastReview(r.id) == 'confirmed' ||
              (r.status == 'ok' && _lastReview(r.id) != 'rejected'),
          punchId: r.id,
        ),
      ..._pinPunches,
    ];
  }

  @override
  Future<List<KioskInfo>> kiosks(String storeId) async => List.of(_kiosks);

  @override
  Future<({String id, String secret})> registerKiosk(
    String storeId,
    String name,
  ) async {
    final id =
        '00000000-0000-4000-8000-${(_seq++).toString().padLeft(12, '0')}';
    _kiosks.add(
      KioskInfo(id: id, name: name, active: true, createdAt: DateTime.now()),
    );
    return (id: id, secret: 'demo-secret');
  }

  @override
  Future<void> disableKiosk(String kioskId) async {
    final i = _kiosks.indexWhere((k) => k.id == kioskId);
    final k = i < 0 ? null : _kiosks[i];
    if (k != null) {
      _kiosks[i] = KioskInfo(
        id: kioskId,
        name: k.name,
        active: false,
        createdAt: k.createdAt,
        accountUserId: k.accountUserId,
        accountName: k.accountName,
      );
    }
  }

  @override
  Future<List<KioskAccountCandidate>> kioskAccountCandidates(
    String storeId,
  ) async => [
    KioskAccountCandidate(
      userId: 'demo-kiosk',
      displayName: '示範公用帳號',
      role: 'parttime',
      blocked: _kiosks.any((k) => k.active && k.accountUserId == 'demo-kiosk')
          ? '已經是打卡用帳號'
          : null,
    ),
    const KioskAccountCandidate(
      userId: 'u3',
      displayName: '示範員工',
      role: 'staff',
      blocked: '已連到員工資料「示範員工」，要先解除',
    ),
  ];

  @override
  Future<void> setKioskAccount(String storeId, String userId) async {
    if (_kiosks.any((k) => k.active && k.accountUserId == userId)) return;
    final id =
        '00000000-0000-4000-8000-${(_seq++).toString().padLeft(12, '0')}';
    _kiosks.add(
      KioskInfo(
        id: id,
        name: '示範公用帳號',
        active: true,
        createdAt: DateTime.now(),
        accountUserId: userId,
        accountName: '示範公用帳號',
      ),
    );
  }

  // 示範打卡密碼（虛構）：阿哲 2580、小魚 3691；阿明（示範員工自己）還沒設，班表頁會請他先設定。正式資料庫只存雜湊
  final _pins = <String, String>{'f2': '2580', 'p0': '3691'};
  final _pinLast = <String, String>{}; // 每個人上一次打的是上班還是下班
  final _pinPunches = <AttendanceExportRow>[];
  int _pinFails = 0;
  DateTime? _pinLockedUntil;

  @override
  Future<KioskMine?> kioskMine() async {
    if (!_isKiosk) return null;
    return _kioskXc
        ? const KioskMine(
            kioskId: 'demo-kiosk-xc',
            storeId: 'xc',
            storeName: '小城外',
            kioskName: '示範公用帳號',
            error: '小城外打卡尚未開啟',
          )
        : const KioskMine(
            kioskId: 'demo-kiosk-yc',
            storeId: 'yc',
            storeName: '隱城',
            kioskName: '示範公用帳號',
          );
  }

  @override
  Future<PinPunchResult> pinPunch(String pin) async {
    if (!_isKiosk) throw Exception('message: 只有店裡的打卡用帳號可以用密碼打卡,');
    if (_kioskXc) throw Exception('message: 小城外打卡尚未開啟,');
    final now = DateTime.now();
    final lock = _pinLockedUntil;
    if (lock != null && lock.isAfter(now)) {
      return PinPunchResult(
        result: 'locked',
        lockedUntil: lock,
        message: '密碼連錯 5 次，請 ${lock.difference(now).inSeconds + 1} 秒後再試',
      );
    }
    // ops 0131：靠密碼認人（同店不會重複）
    final active = {
      for (final p in (await shiftMonth('yc', now)).people)
        if (p.active) p.id: p.label,
    };
    final personId = _pins.entries
        .where((e) => e.value == pin && active.containsKey(e.key))
        .firstOrNull
        ?.key;
    if (personId == null) {
      _pinFails++;
      if (_pinFails >= 5) {
        _pinFails = 0;
        _pinLockedUntil = now.add(const Duration(minutes: 1));
        return PinPunchResult(
          result: 'locked',
          lockedUntil: _pinLockedUntil,
          message: '密碼連錯 5 次，請 1 分鐘後再試',
        );
      }
      return PinPunchResult(
        result: 'wrong',
        remaining: 5 - _pinFails,
        message: '找不到這組密碼，還可以試 ${5 - _pinFails} 次。忘記密碼請找店長重設',
      );
    }
    final name = active[personId]!;
    _pinFails = 0;
    final type = _pinLast[personId] == 'in' ? 'out' : 'in';
    _pinLast[personId] = type;
    final biz = DateTime(now.year, now.month, now.day - (now.hour < 6 ? 1 : 0));
    _pinPunches.add(
      AttendanceExportRow(
        businessDate: biz,
        personName: name,
        punchType: type,
        punchedAt: now,
        storeName: '隱城',
        source: 'pin',
        status: 'ok',
        flags: '',
        counted: true,
        punchId: 'pin${_seq++}',
      ),
    );
    return PinPunchResult(
      result: 'ok',
      personName: name,
      punchType: type,
      punchedAt: now,
      status: 'ok',
      remaining: 5,
    );
  }

  @override
  Future<List<PinStatus>?> pinStatus(String storeId) async {
    if (_isKiosk) return const [];
    final m = await shiftMonth(storeId, DateTime.now());
    return [
      for (final p in m.people)
        if (!_isStaff || p.id == 'f0')
          PinStatus(
            personId: p.id,
            name: p.label,
            active: p.active,
            hasPin: _pins.containsKey(p.id),
            // 示範：阿明（f0）是登入的這個人；店長不能設自己的；員工本人只有還沒設的時候能自己設
            canSet: _isStaff
                ? !_pins.containsKey(p.id)
                : !(_isManager && p.id == 'f0'),
            mine: p.id == 'f0',
          ),
    ];
  }

  @override
  Future<PinSetResult> pinSet(String personId, String? pin) async {
    if (_isManager && personId == 'f0')
      throw Exception('message: 店長的打卡密碼請老闆設定,');
    if (_isStaff && personId != 'f0')
      throw Exception('message: 沒有權限設定這個人的打卡密碼,');
    if (pin != null && !RegExp(r'^[0-9]{4}$').hasMatch(pin))
      throw Exception('message: 打卡密碼要是 4 位數字,');
    // ops 0131：同店不能跟別人一樣；本人設過之後要店長重設
    if (_isStaff && _pins.containsKey(personId)) {
      return const PinSetResult(
        result: 'reset_needed',
        message: '已經設過打卡密碼了。忘記或想換，請找店長重設',
      );
    }
    if (pin != null && isWeakPunchPin(pin)) {
      return const PinSetResult(
        result: 'rejected',
        message: '這組太好猜了，請換一組（不能四個數字都一樣，也不能是連號）',
      );
    }
    if (pin != null &&
        _pins.entries.any((e) => e.key != personId && e.value == pin)) {
      return const PinSetResult(result: 'rejected', message: '這組密碼不能用，請換一組');
    }
    var v = pin;
    while (v == null ||
        isWeakPunchPin(v) ||
        _pins.entries.any((e) => e.key != personId && e.value == v)) {
      v = (1000 + DateTime.now().microsecond % 9000).toString();
    }
    _pins[personId] = v;
    return PinSetResult(result: 'ok', pin: pin == null ? v : null);
  }

  @override
  Future<void> pinClear(String personId) async {
    if (_isStaff || (_isManager && personId == 'f0'))
      throw Exception('message: 沒有權限,');
    _pins.remove(personId);
  }

  @override
  Future<KioskCode> kioskCode(String kioskId, String secret) async {
    final now = DateTime.now();
    final w = now.millisecondsSinceEpoch ~/ 30000;
    return KioskCode(
      storeName: '隱城',
      kioskName: '示範打卡機',
      window: w,
      code: w.toRadixString(16).padLeft(16, '0'),
      serverTime: now,
      validUntil: DateTime.fromMillisecondsSinceEpoch((w + 1) * 30000),
    );
  }

  final Set<String> _punchExempt = {};
  @override
  Future<Set<String>> punchExemptIds(String storeId) async => {..._punchExempt};
  @override
  Future<void> setPunchExempt(
    String storeId,
    String personId,
    bool exempt,
  ) async {
    if (_isStaff || _isManager) throw Exception('message: 不用打卡只有老闆能設,');
    exempt ? _punchExempt.add(personId) : _punchExempt.remove(personId);
  }

  @override
  Future<List<StaffEntry>> staffDirectory(String storeId) async {
    final m = await shiftMonth(storeId, DateTime.now());
    // 示範一位已停用（離職）的人：員工資料頁只有停用或已填離職日的人才顯示離職日
    final left = ShiftPerson(
      id: 'x0',
      name: '示範已離職',
      kind: 'part',
      sortOrder: 99,
      active: false,
    );
    return [
      for (final p in [...m.people, left])
        if (!_isStaff || p.id == 'f0')
          StaffEntry(
            personId: p.id,
            name: p.label,
            kind: p.kind,
            active: p.active,
            hireDate: _hire.containsKey(p.id) ? _hire[p.id] : p.hireDate,
            phone: _hr[p.id]?['phone'] as String?,
            emergencyContact: _hr[p.id]?['ec'] as String?,
            emergencyPhone: _hr[p.id]?['ep'] as String?,
            leaveDate: _hr.containsKey(p.id)
                ? _hr[p.id]!['leave'] as DateTime?
                : (p == left ? DateTime(2026, 10, 31) : null),
            payType: _hr[p.id]?['pay'] as String?,
            nationalId: _ident[p.id]?['id'],
            bankCode: _ident[p.id]?['bank'],
            bankAccount: _ident[p.id]?['acct'],
            rateEffectiveFrom: _rates[p.id]?.firstOrNull?.effectiveFrom,
            ratePayType: _rates[p.id]?.firstOrNull?.payType,
            rateAmount: _rates[p.id]?.firstOrNull?.amount,
            canSeePay: !_isStaff,
            userId: _bound[p.id]?.user,
            userName: _bound[p.id]?.name,
            userVerified: _verified.contains(p.id),
          ),
    ];
  }

  @override
  Future<void> verifyBinding(
    String personId,
    String userId, {
    bool verify = true,
  }) async {
    if (_isStaff) throw Exception('message: 只有老闆能確認帳號綁定,');
    if (_bound[personId]?.user != userId)
      throw Exception('message: 這個名字綁定的帳號已經換了，請重新整理,');
    verify ? _verified.add(personId) : _verified.remove(personId);
  }

  @override
  Future<void> saveStaffHr(
    String storeId,
    String personId, {
    String? phone,
    String? emergencyContact,
    String? emergencyPhone,
    DateTime? leaveDate,
    String? payType,
  }) async {
    _hr[personId] = {
      'phone': phone,
      'ec': emergencyContact,
      'ep': emergencyPhone,
      'leave': leaveDate,
      'pay': payType ?? _hr[personId]?['pay'],
    };
  }

  @override
  Future<void> saveHireDate(
    String storeId,
    String personId,
    DateTime? hireDate,
  ) async {
    if (_isStaff) throw Exception('message: 沒有權限修改到職日,');
    _hire[personId] = hireDate;
  }

  @override
  Future<List<PayRate>> payRates(String personId) async =>
      List.of(_rates[personId] ?? const []);

  @override
  Future<void> addPayRate(String storeId, String personId, PayRate r) async {
    final list = _rates.putIfAbsent(personId, () => []);
    if (list.any((x) => x.effectiveFrom == r.effectiveFrom)) {
      throw Exception(
        'message: duplicate key value violates unique constraint "staff_pay_rates_person_id_effective_from_key",',
      );
    }
    list.add(
      PayRate(
        id: 'r${_seq++}',
        effectiveFrom: r.effectiveFrom,
        payType: r.payType,
        amount: r.amount,
        insuredSalary: r.insuredSalary,
        pensionSelfRate: r.pensionSelfRate,
        note: r.note,
      ),
    );
    list.sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom));
  }

  @override
  Future<void> updatePayRate(PayRate r) async {
    for (final list in _rates.values) {
      final i = list.indexWhere((x) => x.id == r.id);
      if (i < 0) continue;
      if (list.any((x) => x.id != r.id && x.effectiveFrom == r.effectiveFrom)) {
        throw Exception(
          'message: duplicate key value violates unique constraint "staff_pay_rates_person_id_effective_from_key",',
        );
      }
      list[i] = r;
      list.sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom));
      return;
    }
    throw Exception('message: 沒有權限修改這筆薪資,');
  }

  @override
  Future<void> deletePayRate(String id) async {
    for (final l in _rates.values) {
      l.removeWhere((r) => r.id == id);
    }
  }

  @override
  Future<void> saveStaffIdentity(
    String storeId,
    String personId, {
    String? nationalId,
    String? bankCode,
    String? bankAccount,
  }) async {
    _ident[personId] = {
      'id': nationalId,
      'bank': bankCode,
      'acct': bankAccount,
    };
  }

  // ---------------- 薪資（示範：人名、金額都是虛構的） ----------------
  var _payOt = const PayrollSettings();
  final _payRows =
      <String, Map<String, PayrollRow>>{}; // 'store|yyyy-mm' → 人 → 列
  final _payStatus = <String, String>{};
  // 示範：一位還沒有薪率的在職人員（應計薪名單會缺他，老闆設成不計薪或補薪率後才能發布）
  static const _payNoRateId = 'demo-no-rate', _payNoRateName = '新來的（示範）';
  final _payExempt = <String>{};
  bool _payNoRateMissing(String storeId) =>
      storeId == 'yc' && !_payExempt.contains(_payNoRateId);
  // 已發布的月份用發布當時的名單：之後才出現的人不算缺漏、也不列出
  bool _payNoRateShown(String k, String storeId) =>
      storeId == 'yc' && _payStatus[k] == 'draft';
  String _payKey(String storeId, DateTime m) => '$storeId|${m.year}-${m.month}';
  String? _paySelf(String k) =>
      _isManager ? _payRows[k]?.keys.firstOrNull : null;
  void _payNeedManager() {
    if (_isStaff) throw Exception('message: 只有老闆、店長能看薪資,');
  }

  PayrollRow _payCalc(PayrollRow r, {String? status}) {
    final days = r.daysOverride ?? r.autoDays,
        hours = r.hoursOverride ?? r.autoHours;
    final g = payrollTotal(
      payType: r.payType,
      base: r.baseAmount,
      days: days,
      hours: hours,
      otHours: r.otHours,
      otHours2: r.otHours2,
      otMode: r.otMode,
      otRate: r.otRate,
      bonus: r.bonus,
      insurance: r.insurance,
      deduction: r.deduction,
      extras: r.extras,
    );
    return PayrollRow(
      personId: r.personId,
      name: r.name,
      kind: r.kind,
      status: status ?? r.status,
      payType: r.payType,
      baseAmount: r.baseAmount,
      autoDays: r.autoDays,
      autoHours: r.autoHours,
      daysOverride: r.daysOverride,
      hoursOverride: r.hoursOverride,
      days: days,
      hours: hours,
      otHours: r.otHours,
      otHours2: r.otHours2,
      otMode: r.otMode,
      otRate: r.otRate,
      bonus: r.bonus,
      insurance: r.insurance,
      deduction: r.deduction,
      extras: r.extras,
      slipName: r.slipName,
      note: r.note,
      autoOtHours: r.autoOtHours,
      autoOtHours2: r.autoOtHours2,
      otManual: r.otManual,
      gross: g?.toDouble(),
      editable: (status ?? r.status) == 'draft',
      missingRate: r.baseAmount == null,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<PayrollSettings> payrollSettings(String storeId) async {
    _payNeedManager();
    return _payOt;
  }

  @override
  Future<void> setPayrollOvertime(
    String storeId,
    String mode,
    double rate,
  ) async {
    _payNeedManager();
    _payOt = PayrollSettings(
      otMode: mode,
      otRate: rate,
      companyName: _payOt.companyName,
    );
  }

  @override
  Future<int> preparePayroll(String storeId, DateTime month) async {
    _payNeedManager();
    final k = _payKey(storeId, month);
    if (_payStatus[k] == 'published')
      throw Exception('message: 這個月已經發布，要先由老闆重新開啟,');
    final people = (await shiftMonth(storeId, month)).people;
    final rows = _payRows.putIfAbsent(k, () => {});
    for (final (i, p) in people.indexed) {
      final old = rows[p.id];
      if (old == null && _payExempt.contains(p.id))
        continue; // 不計薪的人不帶入（已有的列保留）
      // 示範：正職月薪、兼職時薪，第一位是日薪；隱城的時數假裝從打卡帶入
      final type = i == 0 ? 'daily' : (p.kind == 'part' ? 'hourly' : 'monthly');
      final base = switch (type) {
        'daily' => 1800.0,
        'monthly' => 36000.0 + i * 1000,
        _ => 200.0,
      };
      final auto = storeId == 'yc';
      // 示範：勞保、健保、眷屬健保跟正式的一樣先帶上個月的（這裡第一次帶入就給一組數字，畫面才看得到新格式）
      final ex =
          old?.extras ??
          (type == 'monthly'
              ? PayExtras(
                  attendanceBonus: 1000,
                  laborIns: 916,
                  healthIns: 568,
                  dependentsIns: i == 1 ? 568 : 0,
                )
              : type == 'hourly'
              ? const PayExtras(laborIns: 277, healthIns: 172)
              : const PayExtras());
      rows[p.id] = _payCalc(
        PayrollRow(
          personId: p.id,
          name: p.label,
          slipName: p.shortLabel,
          kind: p.kind,
          payType: type,
          baseAmount: base,
          extras: ex,
          autoDays: auto && type == 'daily' ? 10 : null,
          autoHours: auto && type == 'hourly' ? 60.0 + i * 4.5 : null,
          daysOverride: old?.daysOverride,
          hoursOverride: old?.hoursOverride,
          // 示範：月薪制帶入核准的加班（每天前 2 小時、第 3 小時起分開；手動改過的不蓋掉）
          autoOtHours: auto && type == 'monthly'
              ? _demoOt(p.id, month).h1
              : null,
          autoOtHours2: auto && type == 'monthly'
              ? _demoOt(p.id, month).h2
              : null,
          otManual: old?.otManual ?? false,
          otHours: type == 'monthly'
              ? (auto && !(old?.otManual ?? false)
                    ? _demoOt(p.id, month).h1
                    : old?.otHours ?? 0)
              : 0,
          otHours2: type == 'monthly'
              ? (auto && !(old?.otManual ?? false)
                    ? _demoOt(p.id, month).h2
                    : old?.otHours2 ?? 0)
              : 0,
          otMode: _payOt.otMode,
          otRate: _payOt.otRate,
          bonus: old?.bonus ?? 0,
          insurance: type == 'daily' ? 0 : old?.insurance ?? 0,
          deduction: old?.deduction ?? 0,
          note: old?.note,
        ),
        status: 'draft',
      );
    }
    _payStatus[k] = 'draft';
    return rows.length;
  }

  ({double h1, double h2}) _demoOt(String person, DateTime month) {
    final byDay = <DateTime, double>{};
    for (final o in _ot) {
      if (o.personId == person &&
          o.status == 'approved' &&
          o.businessDate.year == month.year &&
          o.businessDate.month == month.month) {
        byDay[o.businessDate] =
            (byDay[o.businessDate] ?? 0) + (o.approvedHours ?? 0);
      }
    }
    var h1 = 0.0, h2 = 0.0;
    for (final h in byDay.values) {
      h1 += h < 2 ? h : 2;
      h2 += h > 2 ? h - 2 : 0;
    }
    return (h1: h1, h2: h2);
  }

  @override
  Future<List<PayrollRow>> payrollMonth(String storeId, DateTime month) async {
    _payNeedManager();
    final k = _payKey(storeId, month), self = _paySelf(k);
    return [
      for (final r in _payRows[k]?.values ?? const <PayrollRow>[])
        r.personId == self
            ? PayrollRow(
                personId: r.personId,
                name: r.name,
                payType: r.payType,
                hidden: true,
              )
            : r,
      if (_payNoRateShown(k, storeId))
        PayrollRow(
          personId: _payNoRateId,
          name: _payNoRateName,
          payType: 'hourly',
          missingRate: _payNoRateMissing(storeId),
          exempt: !_payNoRateMissing(storeId),
        ),
    ];
  }

  @override
  Future<void> setPayrollExempt(
    String storeId,
    String personId,
    bool exempt,
  ) async {
    if (_isStaff || _isManager) throw Exception('message: 不計薪只有老闆能設,');
    exempt ? _payExempt.add(personId) : _payExempt.remove(personId);
  }

  @override
  PayrollEstimate? peekPayrollEstimate(String storeId, DateTime month) => null;

  /// 示範：照班表算（月薪整月、日薪×上班天數、時薪×上班天數×8 小時；O 當作沒設時間）
  @override
  Future<PayrollEstimate> payrollEstimate(
    String storeId,
    DateTime month,
  ) async {
    _payNeedManager();
    final k = _payKey(storeId, month), sm = await shiftMonth(storeId, month);
    final pub = _payStatus[k] == 'published',
        self = _isManager && sm.people.isNotEmpty ? sm.people.first.id : null;
    return PayrollEstimate([
      for (final (i, p) in sm.people.indexed)
        if (!_payExempt.contains(p.id))
          () {
            final type = i == 0
                ? 'daily'
                : (p.kind == 'part' ? 'hourly' : 'monthly');
            final base = switch (type) {
              'daily' => 1800.0,
              'monthly' => 36000.0 + i * 1000,
              _ => 200.0,
            };
            final marks = (sm.marks[p.id] ?? const <int, String>{}).values
                .where(ShiftMonth.isOn)
                .toList();
            final untimed = marks.where((m) => m == 'O').length,
                days = marks.length;
            final hours = (days - untimed) * 8.0;
            final row = _payRows[k]?[p.id];
            final extra = type == 'monthly'
                ? (row?.bonus ?? 0) + (row?.extras.attendanceBonus ?? 1000)
                : 0.0;
            final est =
                switch (type) {
                  'daily' => base * days,
                  'hourly' => base * hours,
                  _ => base,
                } +
                extra;
            final hide = p.id == self;
            return PayrollEstimateRow(
              personId: p.id,
              name: p.label,
              payType: type,
              rate: hide ? null : base,
              basis: type == 'monthly' ? 'monthly' : 'schedule',
              days: hide || type != 'daily' ? null : days.toDouble(),
              hours: hide || type != 'hourly' ? null : hours,
              schedDays: days,
              schedHours: hours,
              untimed: untimed,
              extra: hide ? null : extra,
              estimate: hide ? null : est,
              actual: !hide && pub ? row?.gross : null,
              published: pub,
              hidden: hide,
            );
          }(),
    ]);
  }

  @override
  Future<PayrollReport> payrollReport(String storeId, DateTime month) async {
    _payNeedManager();
    final k = _payKey(storeId, month),
        rows = _payRows[k]?.values.toList() ?? const <PayrollRow>[];
    if (_payStatus[k] == null) return const PayrollReport();
    final names = [
      for (final r in rows)
        if (r.gross == null) r.name,
      if (_payNoRateShown(k, storeId) && _payNoRateMissing(storeId))
        _payNoRateName,
    ];
    final missing = names.length, self = _paySelf(k);
    final total = rows.fold<double>(0, (a, r) => a + (r.gross ?? 0));
    final visible = rows.fold<double>(
      0,
      (a, r) => a + (r.personId == self ? 0 : r.gross ?? 0),
    );
    const revenue = 600000.0;
    final show = missing == 0 && self == null; // 店長少了自己那一列：不給總計、成本率
    return PayrollReport(
      status: _payStatus[k],
      people: rows.length,
      total: show ? total : null,
      revenue: revenue,
      costRate: show ? (total / revenue * 10000).round() / 10000 : null,
      complete: true,
      missingRate: missing,
      visibleTotal: visible,
      missingNames: names,
    );
  }

  @override
  Future<double?> savePayrollEntry(
    String storeId,
    String personId,
    DateTime month, {
    double? days,
    double? hours,
    double otHours = 0,
    double otHours2 = 0,
    double bonus = 0,
    double insurance = 0,
    double deduction = 0,
    PayExtras? extras,
    String? note,
    String? reason,
  }) async {
    _payNeedManager();
    final k = _payKey(storeId, month), r = _payRows[k]?[personId];
    if (r == null) throw Exception('message: 這個人這個月還沒有薪資，請先帶入,');
    if (personId == _paySelf(k)) throw Exception('message: 你自己的薪資由老闆處理,');
    if (_payStatus[k] == 'published') throw Exception('message: 這個月已經發布，不能再改,');
    if (r.payType != 'monthly' && otHours + otHours2 > 0)
      throw Exception('message: 只有月薪制可以填加班時數,');
    if (r.payType == 'daily' && insurance != 0)
      throw Exception('message: 日薪制不扣勞健保,');
    if ([hours, otHours, otHours2].any((v) => v != null && !isHalfHour(v))) {
      throw Exception('message: 時數只能填 0.5 小時的倍數,');
    }
    final ex = extras ?? r.extras;
    if (r.payType == 'daily' &&
        ex.laborIns + ex.healthIns + ex.dependentsIns != 0)
      throw Exception('message: 日薪制不扣勞健保,');
    final n = _payCalc(
      PayrollRow(
        personId: r.personId,
        name: r.name,
        slipName: r.slipName,
        kind: r.kind,
        status: r.status,
        payType: r.payType,
        baseAmount: r.baseAmount,
        autoDays: r.autoDays,
        autoHours: r.autoHours,
        daysOverride: days,
        hoursOverride: hours,
        otHours: otHours,
        otHours2: otHours2,
        otMode: r.otMode,
        otRate: r.otRate,
        bonus: bonus,
        insurance: insurance,
        deduction: deduction,
        extras: ex,
        note: note,
        autoOtHours: r.autoOtHours,
        autoOtHours2: r.autoOtHours2,
        otManual: r.autoOtHours == null
            ? r.otManual
            : r.otMode == 'lsa'
            ? (otHours != r.autoOtHours || otHours2 != (r.autoOtHours2 ?? 0))
            : otHours + otHours2 != r.autoOtHours! + (r.autoOtHours2 ?? 0),
      ),
    );
    if (ex.cashPaid > (n.gross ?? 0)) {
      throw Exception('message: 領現金額不能比實發金額多（實發 ${(n.gross ?? 0).round()} 元）,');
    }
    _payRows[k]![personId] = n;
    return n.gross;
  }

  @override
  Future<void> setPayrollCompany(String storeId, String name) async {
    if (_isStaff || _isManager) throw Exception('message: 公司名稱只有老闆能改,');
    _payOt = PayrollSettings(
      otMode: _payOt.otMode,
      otRate: _payOt.otRate,
      companyName: name.trim().isEmpty ? null : name.trim(),
    );
  }

  @override
  Future<void> publishPayroll(String storeId, DateTime month) async {
    _payNeedManager();
    final k = _payKey(storeId, month), rows = _payRows[k];
    if (rows == null) throw Exception('message: 這個月還沒有薪資,');
    final names = (await payrollReport(storeId, month)).missingNames;
    if (names.isNotEmpty)
      throw Exception('message: 還有人沒有薪資或還沒帶入，不能發布：${names.join('、')},');
    _payStatus[k] = 'published';
    rows.updateAll((_, r) => _payCalc(r, status: 'published'));
  }

  @override
  Future<void> reopenPayroll(
    String storeId,
    DateTime month,
    String reason,
  ) async {
    if (_isStaff || _isManager) throw Exception('message: 只有老闆能重新開啟,');
    final k = _payKey(storeId, month);
    _payStatus[k] = 'draft';
    _payRows[k]?.updateAll((_, r) => _payCalc(r, status: 'draft'));
  }

  @override
  Future<List<PayrollSlip>> myPayslips(String storeId) async {
    if (_bindingPending) return const [];
    final m = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
    return [
      PayrollSlip(
        month: m,
        storeName: storeId == 'yc' ? '隱城' : '小城外',
        companyName: _payOt.companyName ?? '示範餐飲股份有限公司',
        personName: _demoFullNames['阿明'] ?? '阿明',
        payType: 'hourly',
        baseAmount: 200,
        hours: 82.5,
        bonus: 500,
        extras: const PayExtras(
          attendanceBonus: 1000,
          laborIns: 277,
          healthIns: 172,
          dependentsIns: 172,
          incomeTax: 0,
          cashPaid: 5000,
          items: [
            PayItem(income: true, label: '交通津貼', amount: 600),
            PayItem(income: false, label: '制服', amount: 300),
          ],
        ),
        note: '11/3 支援小城外一天',
        gross: 17679,
        publishedAt: DateTime(m.year, m.month + 1, 5),
      ),
    ];
  }
}
