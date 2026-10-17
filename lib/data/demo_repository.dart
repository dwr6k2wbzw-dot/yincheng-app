import 'dart:async';
import 'dart:typed_data';

import 'models.dart';
import 'repository.dart';

/// 示範資料：不連線，數字全部是虛構的示範值（不是真實營收），只用來看畫面與操作流程。
/// 登入任何帳號都會以「老闆」身分進入；帳號含 staff 則以員工身分進入（可測試權限差異）。
class DemoRepository implements Repository {
  final _auth = StreamController<bool>.broadcast();
  bool _signedIn = false;
  String _email = '';
  int _seq = 0;

  final _categories = [
    // 0048：可選只有 酒水／餐食／雜項；舊類別停用、顯示併入（與正式資料庫相同）
    CostCategory.full('yc_drink', '酒水', null, costGroup: 'drink', inMiscRate: false),
    CostCategory.full('yc_food', '餐食', null, costGroup: 'food', inMiscRate: false),
    CostCategory.full('yc_misc', '雜項', null, costGroup: 'other', inMiscRate: true),
    CostCategory.full('liquor_monthly', '月結酒商', null, costGroup: 'drink', inMiscRate: false, selectable: false, displayAs: 'yc_drink'),
    CostCategory.full('liquor_cash', '現結酒商', null, costGroup: 'drink', inMiscRate: false, selectable: false, displayAs: 'yc_drink'),
    CostCategory.full('fruit', '酒水副材料-德哥', null, costGroup: 'drink', inMiscRate: false, selectable: false, displayAs: 'yc_drink'),
    CostCategory.full('ice', '酒水副材料-冰塊', null, costGroup: 'drink', inMiscRate: false, selectable: false, displayAs: 'yc_drink'),
    CostCategory.full('bar_misc', '酒水副材料-雜項', null, costGroup: 'drink', inMiscRate: true, selectable: false, displayAs: 'yc_misc'),
    CostCategory.full('food', '餐食進貨', null, costGroup: 'food', inMiscRate: false, selectable: false, displayAs: 'yc_food'),
    CostCategory.full('petty_misc', '零用金-其他雜支', null, costGroup: 'other', inMiscRate: true, selectable: false, displayAs: 'yc_misc'),
  ];
  final _suppliers = [
    Supplier('s1', '示範酒商A', 'liquor_monthly'),
    Supplier('s2', '示範酒商B', 'liquor_monthly'),
    Supplier('s3', '示範水果行', 'fruit'),
    Supplier('s4', '示範冷凍食品', 'food'),
    Supplier('s5', '示範食材行', 'food'),
  ];
  final _products = [
    Product('p1', "Hendrick's Gin", '酒水', '瓶', parLevel: 2),
    Product('p2', 'Bombay Sapphire', '酒水', '瓶'),
    Product('p3', 'Campari', '酒水', '瓶'),
    Product('p4', 'Chartreuse', '酒水', '瓶'),
    Product('p5', '檸檬', '餐食', '顆', parLevel: 20),
  ];
  late final List<Purchase> _purchases = [
    Purchase(id: 'x1', purchaseDate: DateTime(2026, 9, 25), categoryCode: 'liquor_monthly', supplierName: '示範酒商', amount: 2000, paidBy: 'vendor', reconciled: true, source: 'import'),
    Purchase(id: 'x2', purchaseDate: DateTime(2026, 9, 24), categoryCode: 'food', supplierName: null, memo: '示範食材', amount: 3000, paidBy: 'vendor', reconciled: true, source: 'import'),
    Purchase(id: 'x3', purchaseDate: DateTime(2026, 9, 30), categoryCode: 'petty_misc', memo: '運費', amount: 300, paidBy: 'petty_cash', reconciled: false, source: 'import'),
  ];
  final _counts = <StockCount>[];
  final _lines = <String, Map<String, double>>{};

  bool get _isStaff => _email.contains('staff');

  @override
  Stream<bool> get signedInChanges => _auth.stream;
  @override
  bool get isSignedIn => _signedIn;
  @override
  String? get currentUserId => _signedIn ? 'demo-user' : null;
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
  Future<List<VendorSlip>> vendorSlips(String storeId, DateTime month) async => [
        VendorSlip('v1', '示範酒商', 'D-001', DateTime(month.year, month.month, 1), 1300, null, [
          VendorSlipLine(1, 'A01', '示範琴酒 700ML', 1, '瓶', 900, 900),
          VendorSlipLine(2, 'A02', '示範蘇打水 24入', 1, '箱', 400, 400),
        ])
          ..categoryCode = 'liquor_monthly'
          ..filer = 'Eason',
        VendorSlip('v2', '示範食材行', 'F-002', DateTime(month.year, month.month, 2), 850, null, [
          VendorSlipLine(1, null, '示範牛肉片', 2, '包', 425, 850),
        ])
          ..categoryCode = 'food',
        VendorSlip('v3', '示範雜貨', 'M-003', DateTime(month.year, month.month, 3), 320, null, [])
          ..categoryCode = 'petty_misc'
          ..paidBy = 'petty_cash'
          ..filer = '小郭',
      ];
  @override
  Future<List<String>> failedSlipFiles(String storeId) async => [];
  @override
  Future<String> saveVendorSlip(String storeId, VendorSlip slip) async => slip.id.isEmpty ? 'v-new' : slip.id;
  @override
  Future<void> deleteVendorSlip(String slipId) async {}

  @override
  Future<List<String>> excelVendorNames(String storeId) async => ['示範酒商A', '示範酒商B', '示範水果行'];
  @override
  Future<List<String>> memberNames(String storeId) async => ['示範老闆', '示範店長', '示範正職'];
  @override
  Future<VendorHints> vendorHints(String storeId) async => (
        vendor: {'yc_drink': ['示範酒商A', '示範酒商B']},
        petty: {'yc_misc': ['示範五金行']},
      );

  @override
  Future<ShiftMonth> shiftMonth(String storeId, DateTime month) async => ShiftMonth(
        DateTime(month.year, month.month, 1),
        [ShiftPerson(id: 'p1', name: '示範正職'), ShiftPerson(id: 'p2', name: '示範兼職', kind: 'part', sortOrder: 10)],
        {'p1': {1: 'V', 2: '休', 3: '指休'}, 'p2': {1: 'V', 3: 'O'}},
        {3: '月會日'},
        {'p1': const ShiftStats(shouldOff: 8, prevUnused: 3)},
        null,
      );
  @override
  Future<void> setShift(String storeId, String personId, DateTime date, String? mark) async {}
  @override
  Future<void> setShiftNote(String storeId, DateTime date, String? note) async {}
  @override
  Future<void> saveShiftPerson(String storeId, ShiftPerson p, {bool isNew = false}) async {}
  @override
  Future<void> saveShiftStats(String storeId, String personId, DateTime month, ShiftStats s) async {}
  @override
  Future<void> uploadShiftPhoto(String storeId, DateTime month, Uint8List jpeg) async {}
  @override
  Future<String> shiftPhotoUrl(String path) async => '';

  // 交接・提醒（示範：只存在記憶體）
  final _notes = <HandoverNote>[];
  final _reminders = <WorkReminder>[];
  final _done = <String, ReminderDone>{};
  @override
  Future<HandoverBoard> handoverBoard(String storeId, {bool withSchedule = false}) async {
    final sm = withSchedule ? await shiftMonth(storeId, bizToday()) : null;
    return HandoverBoard([..._notes.reversed], [..._reminders], {..._done}, sm?.people ?? const [],
        {for (final p in sm?.people ?? const <ShiftPerson>[]) p.id: sm!.mark(p.id, bizToday().day)});
  }
  HandoverNote _copyNote(HandoverNote n, {String? body, List<HandoverItem>? items, DateTime? resolvedAt, bool setResolved = false, bool edited = false}) =>
      HandoverNote(
          id: n.id, body: body ?? n.body, photoPath: n.photoPath, authorId: n.authorId, authorName: n.authorName,
          createdAt: n.createdAt, resolvedAt: setResolved ? resolvedAt : n.resolvedAt,
          resolvedName: setResolved ? (resolvedAt == null ? null : '示範老闆') : n.resolvedName, readers: n.readers,
          editedAt: edited ? DateTime.now() : n.editedAt, editedName: edited ? '示範老闆' : n.editedName, items: items ?? n.items);
  @override
  Future<void> addHandover(String storeId, String body, List<String> items, Uint8List? jpeg) async => _notes.add(HandoverNote(
      id: 'n${_seq++}', body: body, authorId: 'demo-user', authorName: '示範老闆', createdAt: DateTime.now(),
      items: [for (var i = 0; i < items.length; i++) HandoverItem(id: 'i${_seq++}', position: i + 1, body: items[i])]));
  @override
  Future<void> updateHandover(String noteId, String body, List<String> items) async {
    final i = _notes.indexWhere((n) => n.id == noteId);
    final n = _notes[i];
    final left = [...n.items];
    final next = <HandoverItem>[];
    for (var k = 0; k < items.length; k++) {
      final j = left.indexWhere((x) => x.body == items[k]);
      final old = j < 0 ? null : left.removeAt(j);
      next.add(HandoverItem(id: old?.id ?? 'i${_seq++}', position: k + 1, body: items[k], doneAt: old?.doneAt, doneName: old?.doneName));
    }
    _notes[i] = _copyNote(n, body: body, items: next, edited: body != n.body);
  }
  @override
  Future<void> setHandoverItemDone(String itemId, bool done) async {
    final i = _notes.indexWhere((n) => n.items.any((x) => x.id == itemId));
    final n = _notes[i];
    if (n.resolved) throw Exception('message: 這則交接已處理，要改清單請先按「改回未處理」,');
    _notes[i] = _copyNote(n, items: [
      for (final x in n.items)
        x.id == itemId
            ? HandoverItem(id: x.id, position: x.position, body: x.body, doneAt: done ? DateTime.now() : null, doneName: done ? '示範老闆' : null)
            : x
    ]);
  }
  @override
  Future<void> setHandoverResolved(String noteId, bool resolved) async {
    final i = _notes.indexWhere((n) => n.id == noteId);
    final n = _notes[i];
    if (resolved && n.itemsLeft > 0) throw Exception('message: 清單還有 ${n.itemsLeft} 項沒打勾，全部完成才能按已處理,');
    _notes[i] = _copyNote(n, resolvedAt: resolved ? DateTime.now() : null, setResolved: true);
  }
  @override
  Future<void> markHandoverRead(String storeId, List<String> noteIds) async {}
  @override
  Future<void> deleteHandover(String noteId) async => _notes.removeWhere((n) => n.id == noteId);
  DateTime? _notifSeen;
  @override
  Future<NotificationFeed> notifications(String storeId) async {
    final now = DateTime.now();
    return NotificationFeed([
      AppNotification(id: 3, kind: 'schedule', title: '班表更新', body: '${now.month} 月班表有 3 處修改',
          refMonth: DateTime(now.year, now.month), actorName: '示範店長', createdAt: now.subtract(const Duration(minutes: 20))),
      AppNotification(id: 2, kind: 'reminder', title: '新提醒', body: '跟大倉捷叫貨', actorName: '示範正職',
          createdAt: now.subtract(const Duration(hours: 3))),
      AppNotification(id: 1, kind: 'handover', title: '新交接', body: '冰塊機漏水，已叫修', actorName: '示範正職',
          createdAt: now.subtract(const Duration(days: 1))),
    ], _notifSeen);
  }
  @override
  Future<void> markNotificationsSeen(String storeId) async => _notifSeen = DateTime.now();
  @override
  Future<void> saveReminder(String storeId, WorkReminder r, {bool isNew = false}) async {
    final x = WorkReminder(
        id: isNew ? 'r${_seq++}' : r.id, title: r.title, detail: r.detail, repeat: r.repeat, dueDate: r.dueDate,
        weekday: r.weekday, monthDay: r.monthDay, startDate: isNew ? bizToday() : r.startDate,
        assignPersonId: r.assignPersonId, assignOnShift: r.assignOnShift, active: r.active,
        createdBy: isNew ? currentUserId : r.createdBy);
    _reminders.removeWhere((e) => e.id == x.id);
    _reminders.add(x);
  }
  @override
  Future<void> deleteReminder(String reminderId) async => _reminders.removeWhere((e) => e.id == reminderId);
  @override
  Future<void> setReminderDone(String storeId, String reminderId, DateTime occurrence, bool done) async {
    final k = ReminderDone.keyOf(reminderId, occurrence);
    if (done) {
      _done[k] = ReminderDone(reminderId, occurrence, 'demo-user', '示範老闆', DateTime.now());
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
    MemberInfo(userId: 'demo-user', displayName: '示範老闆', role: Role.owner, active: true, email: 'owner@demo'),
    MemberInfo(userId: 'u2', displayName: '示範店長', role: Role.manager, active: true, email: 'manager@demo'),
    MemberInfo(userId: 'u3', displayName: '示範員工', role: Role.staff, active: true, email: 'staff@demo'),
  ];
  final _demoInvites = <MemberInvite>[];
  @override
  Future<int> claimInvite(String code) async => -1;
  @override
  Future<String> createInvite(List<String> storeIds, Role role, String name) async {
    _demoInvites.insert(0, MemberInvite(id: 'i${_demoInvites.length}', displayName: name, role: role,
        createdAt: DateTime.now(), expiresAt: DateTime.now().add(const Duration(days: 14))));
    return 'DEMO2-CODE9';
  }
  @override
  Future<List<MemberInfo>> storeMembers(String storeId) async => List.of(_demoMembers);
  @override
  Future<List<MemberInvite>> openInvites(String storeId) async => List.of(_demoInvites);
  @override
  Future<void> revokeInvite(String inviteId) async => _demoInvites.removeWhere((i) => i.id == inviteId);
  @override
  Future<void> updateMember(String storeId, String userId, {Role? role, bool? active}) async {
    final i = _demoMembers.indexWhere((m) => m.userId == userId);
    final m = _demoMembers[i];
    _demoMembers[i] = MemberInfo(userId: m.userId, displayName: m.displayName, role: role ?? m.role,
        active: active ?? m.active, email: m.email);
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _auth.add(false);
  }

  // 示範模式不存上次資料
  @override
  List<Membership>? peekMemberships() => null;
  @override
  MonthlySummary? peekMonthlySummary(String storeId, DateTime month) => null;
  @override
  List<DailyRevenue>? peekDailyRevenueBetween(String storeId, DateTime from, DateTime to) => null;
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
  Future<List<Membership>> myMemberships() async => [
        Membership(storeId: 'yc', storeName: '隱城', role: _isStaff ? Role.staff : Role.owner, displayName: '示範'),
        Membership(storeId: 'xc', storeName: '小城外', role: Role.staff, displayName: '示範'),
      ];

  // 依店別分開存（示範用）：yc 有兩筆 Excel 匯入；xc 一開始沒有
  final _revenue = <String, List<RevenueEntry>>{
    'yc': [
      RevenueEntry(id: 'r1', bizDate: DateTime(2026, 9, 30), cash: 8000, creditCard: 20000, guests: 28, drinks: 24000, food: 4000, source: 'import'),
      RevenueEntry(id: 'r2', bizDate: DateTime(2026, 9, 29), cash: 5000, creditCard: 16000, amex: 1000, guests: 21, drinks: 18000, food: 4000, source: 'import'),
    ],
    'xc': [],
  };
  List<RevenueEntry> _revList(String storeId) => _revenue[storeId] ??= [];

  @override
  Future<List<RevenueEntry>> revenueEntries(String storeId, {int limit = 60}) async {
    // 0020：正職也看得到營收
    return List.of(_revList(storeId))..sort((a, b) => b.bizDate.compareTo(a.bizDate));
  }

  @override
  Future<RevenueEntry?> revenueEntryFor(String storeId, DateTime bizDate) async {
    for (final e in _revList(storeId)) {
      if (e.bizDate.year == bizDate.year && e.bizDate.month == bizDate.month && e.bizDate.day == bizDate.day) return e;
    }
    return null;
  }

  @override
  Future<void> saveRevenueEntry(String storeId, RevenueEntry e) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // 0038：正職只能動自己手動登記的（source=app），不能改 Excel 匯入的那筆
    if (_isStaff && e.source == 'import') throw Exception('message: 沒有權限執行這個動作。,');
    final saved = RevenueEntry(
      id: e.id ?? 'rev${++_seq}', bizDate: e.bizDate, cash: e.cash, creditCard: e.creditCard, amex: e.amex,
      deposit: e.deposit, guests: e.guests, drinks: e.drinks, food: e.food, project: e.project,
      coffee: e.coffee, ramen: e.ramen, note: e.note, source: e.source,
    );
    final list = _revList(storeId);
    list.removeWhere((x) => x.id == saved.id);
    list.add(saved);
  }

  @override
  Future<DateTime?> lastExcelSync(String storeId) async =>
      storeId == 'yc' ? DateTime.now().subtract(const Duration(minutes: 25)) : null;

  final _fixed = <String, double>{};

  @override
  Future<FixedCosts> fixedCosts(String storeId, DateTime month) async {
    if (_isStaff) return const FixedCosts();
    final k = '$storeId-${month.year}-${month.month}';
    return FixedCosts(rent: _fixed['$k-rent'], payroll: _fixed['$k-payroll']);
  }

  @override
  Future<void> saveFixedCost(String storeId, DateTime month, String category, double amount) async {
    if (_isStaff) throw Exception('message: 沒有權限執行這個動作。,');
    _fixed['$storeId-${month.year}-${month.month}-$category'] = amount;
  }

  final _expItems = <String, List<ExpenseItem>>{};  // 店家-年月 → 明細
  String _ek(String s, DateTime m) => '$s-${m.year}-${m.month}';
  @override
  Future<List<ExpenseItem>> expenseItems(String storeId, DateTime month) async =>
      _isStaff ? [] : [...?_expItems[_ek(storeId, month)]];
  @override
  Future<void> saveExpenseItem(String storeId, DateTime month, ExpenseItem item, {bool isNew = false}) async {
    if (_isStaff) throw Exception('message: 沒有權限,');
    final list = _expItems.putIfAbsent(_ek(storeId, month), () => []);
    list.removeWhere((e) => e.id == item.id);
    list.add(ExpenseItem(id: isNew ? 'e${_seq++}' : item.id, name: item.name, category: item.category, amount: item.amount));
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
  Future<double> cardFeeRate(String storeId) async => _cardFeeRate[storeId] ?? 0.02;
  @override
  Future<void> saveCardFeeRate(String storeId, double rate) async {
    if (_isStaff) throw Exception('message: 沒有權限,');
    _cardFeeRate[storeId] = rate;
  }
  @override
  Future<List<RecurringExpenseItem>> recurringExpenseItems(String storeId) async =>
      _isStaff ? [] : [...?_recurring[storeId]];
  @override
  Future<void> saveRecurringExpenseItem(String storeId, RecurringExpenseItem item, {bool isNew = false}) async {
    if (_isStaff) throw Exception('message: 沒有權限,');
    final list = _recurring.putIfAbsent(storeId, () => []);
    list.removeWhere((e) => e.id == item.id);
    list.add(RecurringExpenseItem(
        id: isNew ? 'rc${_seq++}' : item.id, name: item.name, category: item.category, amount: item.amount));
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
      return MonthlySummary(month: month, revenue: 0, guests: 0, drinksRevenue: 0, foodRevenue: 0);
    }
    return MonthlySummary(
      month: month,
      revenue: 500000,
      guests: 723,
      avgTicket: 1000,
      dailyAvgTicket: 1000,
      drinksRevenue: 420000,
      foodRevenue: 80000,
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
  Future<List<DailyRevenue>> recentDailyRevenue(String storeId, int days) async {
    if (_isStaff || storeId != 'yc') return [];
    const v = [20000, 10000, 25000, 40000, 50000, 20000, 15000, 22000, 24000, 45000, 38000, 42000, 21000, 30000];
    return [for (var i = 0; i < v.length; i++) DailyRevenue(DateTime(2026, 9, 17).add(Duration(days: i)), v[i].toDouble(), 20 + i)];
  }

  @override
  Future<List<DailyRevenue>> dailyRevenueBetween(String storeId, DateTime from, DateTime to) async {
    if (_isStaff) return [];
    // 示範資料：每天 1.2～2.8 萬
    final out = <DailyRevenue>[];
    final today = DateTime.now();
    for (var d = from; !d.isAfter(to) && !d.isAfter(today); d = d.add(const Duration(days: 1))) {
      out.add(DailyRevenue(d, 12000.0 + (d.day * 3700 % 16000), 20 + d.day % 15));
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
  Future<double?> pettyCashBalance(String storeId) async => storeId == 'yc' ? 5000 : null;

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
  Future<List<Purchase>> recentPurchases(String storeId, {int limit = 30}) async =>
      (List.of(_purchases)..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate))).take(limit).toList();

  @override
  Future<List<Purchase>> monthPurchases(String storeId, DateTime month) async => _purchases
      .where((p) => p.purchaseDate.year == month.year && p.purchaseDate.month == month.month)
      .toList()
    ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

  final _requestIds = <String>{};
  @override
  Future<void> addPurchase(NewPurchase p) async {
    if (!_requestIds.add(p.clientRequestId)) throw Exception('duplicate key client_request');
    if (p.amount == 0) throw Exception('message: 金額不能為 0,');
    _purchases.add(Purchase(
      id: 'n${_seq++}',
      purchaseDate: p.purchaseDate,
      categoryCode: p.categoryCode,
      supplierName: _suppliers.where((s) => s.id == p.supplierId).map((s) => s.name).firstOrNull,
      memo: p.memo,
      amount: p.amount,
      paidBy: p.paidBy,
      reconciled: false,
      source: 'app',
    ));
  }

  @override
  Future<void> updatePurchase(String purchaseId, NewPurchase p) async {
    final i = _purchases.indexWhere((x) => x.id == purchaseId);
    final o = _purchases[i];
    _purchases[i] = Purchase(
        id: o.id, purchaseDate: p.purchaseDate, categoryCode: p.categoryCode,
        supplierName: p.vendorName ?? o.supplierName, memo: p.memo, amount: p.amount, paidBy: p.paidBy,
        reconciled: o.reconciled, source: o.source, createdBy: o.createdBy);
  }

  @override
  Future<void> deletePurchase(String purchaseId) async => _purchases.removeWhere((x) => x.id == purchaseId);

  @override
  Future<void> setReconciled(String purchaseId, bool reconciled) async {
    if (_isStaff) throw Exception('message: 只有老闆或店長可以核銷,');
    final i = _purchases.indexWhere((p) => p.id == purchaseId);
    final p = _purchases[i];
    _purchases[i] = Purchase(
        id: p.id, purchaseDate: p.purchaseDate, categoryCode: p.categoryCode, supplierName: p.supplierName,
        memo: p.memo, amount: p.amount, paidBy: p.paidBy, reconciled: reconciled, source: p.source);
  }

  @override
  Future<List<Product>> products(String storeId) async => _products.where((p) => !_inactive.contains(p.id)).toList();
  final _inactive = <String>{}; // 停用的品項（歷史盤點照常顯示名稱）

  @override
  Future<List<StockCount>> stockCounts(String storeId) async => List.of(_counts.reversed);

  @override
  Future<Map<String, StockLevel>> latestStock(String storeId) async {
    final out = <String, StockLevel>{};
    for (final c in _counts.reversed) {
      if (c.status != CountStatus.submitted && c.status != CountStatus.approved) continue;
      for (final e in (_lines[c.id] ?? {}).entries) {
        out.putIfAbsent(e.key, () => StockLevel(e.value, c.bizDate));
      }
    }
    return out;
  }

  @override
  Future<void> saveProduct(String storeId, Product p) async {
    final i = _products.indexWhere((x) => x.id == p.id);
    final np = Product(p.id.isEmpty ? 'p${_seq++}' : p.id, p.name, p.category, p.unit, parLevel: p.parLevel);
    if (i < 0) {
      _products.add(np);
    } else {
      _products[i] = np;
    }
  }

  @override
  Future<void> deactivateProduct(String productId) async {
    _inactive.add(productId);
  }

  @override
  Future<String> createStockCount(String storeId, String? note) async {
    final id = 'c${_seq++}';
    _counts.add(StockCount(id: id, bizDate: await businessDate(storeId), countedBy: 'demo-user',
        status: CountStatus.draft, note: note, lineCount: 0));
    _lines[id] = {};
    return id;
  }

  @override
  Future<List<CountLine>> countLines(String countId) async => [
        for (final e in (_lines[countId] ?? {}).entries)
          () {
            final p = _products.firstWhere((p) => p.id == e.key);
            return CountLine(p.id, p.name, p.unit, e.value);
          }()
      ];

  @override
  Future<void> upsertCountLine(String countId, String productId, double qty) async {
    final c = _counts.firstWhere((c) => c.id == countId);
    if (c.status != CountStatus.draft && c.status != CountStatus.rejected) {
      throw Exception('message: 盤點已送出或已核准，明細不能修改,');
    }
    _lines[countId]![productId] = qty;
    _replace(c, c.status);
  }

  @override
  Future<void> setCountStatus(String countId, CountStatus status, {String? voidReason}) async {
    final c = _counts.firstWhere((c) => c.id == countId);
    if (status == CountStatus.approved && _isStaff) throw Exception('message: 員工不能核准盤點,');
    _replace(c, status);
  }

  void _replace(StockCount c, CountStatus s) {
    final i = _counts.indexOf(c);
    _counts[i] = StockCount(id: c.id, bizDate: c.bizDate, countedBy: c.countedBy, status: s, note: c.note,
        lineCount: _lines[c.id]?.length ?? 0);
  }

  // ---------------- 訂位（示範） ----------------
  final Map<String, List<Reservation>> _demoRes = {}; // 依店家分開
  final Map<String, Map<String, dynamic>> _demoResSettings = {};
  @override
  Future<ReservationSettings?> reservationSettings(String storeId) async => ReservationSettings.fromRow({
        'store_id': storeId, 'slug': 'demo', 'enabled': true, 'display_name': '示範店', 'first_slot': '19:00',
        'last_slot': '23:00', 'slot_minutes': 30, 'max_guests_per_slot': 20, 'max_party': 6, 'days_ahead': 7,
        'same_day_cutoff': '17:00',
        ...?_demoResSettings[storeId],
      });
  @override
  Future<void> saveReservationSettings(String storeId, Map<String, dynamic> values) async {
    _demoResSettings.putIfAbsent(storeId, () => {}).addAll(values);
  }
  @override
  Future<List<Reservation>> reservations(String storeId, DateTime from, DateTime to) async =>
      (_demoRes[storeId] ?? []).where((r) => !r.date.isBefore(from) && !r.date.isAfter(to)).toList();
  @override
  Future<void> addReservation(String storeId,
      {required DateTime date, required String time, required int party, required String name, required String phone, String? email, String? note}) async {
    final list = _demoRes.putIfAbsent(storeId, () => []);
    list.add(Reservation(
        id: '$storeId-${list.length}', date: date, time: time, party: party, name: name, phone: phone, email: email, note: note,
        status: 'confirmed', source: 'app', createdAt: DateTime.now()));
  }
  final _demoSpecial = <String, Map<String, ReservationSpecialDay>>{};
  final _demoGuests = <String, Map<String, GuestProfile>>{};
  @override
  Future<List<ReservationSpecialDay>> specialDays(String storeId, DateTime from, DateTime to) async =>
      (_demoSpecial[storeId]?.values ?? const <ReservationSpecialDay>[])
          .where((d) => !d.day.isBefore(from) && !d.day.isAfter(to))
          .toList()
        ..sort((a, b) => a.day.compareTo(b.day));
  @override
  Future<void> saveSpecialDay(String storeId, ReservationSpecialDay d) async =>
      (_demoSpecial[storeId] ??= {})[d.day.toIso8601String().substring(0, 10)] = d;
  @override
  Future<void> deleteSpecialDay(String storeId, DateTime day) async =>
      _demoSpecial[storeId]?.remove(day.toIso8601String().substring(0, 10));
  @override
  Future<Map<String, GuestStats>> guestStats(String storeId, Set<String> phoneDigits) async {
    final all = _demoRes[storeId] ?? const <Reservation>[];
    final out = <String, GuestStats>{};
    for (final p in phoneDigits) {
      final prof = _demoGuests[storeId]?[p];
      final reset = prof?.noshowResetAt;
      final resetDay = reset == null ? null : DateTime(reset.year, reset.month, reset.day);
      out[p] = GuestStats(
        all.where((r) => phoneDigitsOf(r.phone) == p && r.status == 'arrived').length,
        all.where((r) => phoneDigitsOf(r.phone) == p && r.status == 'no_show' && (resetDay == null || r.date.isAfter(resetDay))).length,
        prof,
      );
    }
    return out;
  }
  @override
  Future<void> saveGuestProfile(String storeId, GuestProfile g, {bool resetNoshow = false}) async {
    final m = _demoGuests[storeId] ??= {};
    // 和正式資料庫一樣：解除時記下現在時間，之後只算那天以後的未到；沒解除就保留原本的解除時間（Codex 審查）
    m[g.phoneDigits] = GuestProfile(
      phoneDigits: g.phoneDigits,
      tags: g.tags,
      note: g.note,
      noshowResetAt: resetNoshow ? DateTime.now() : m[g.phoneDigits]?.noshowResetAt,
    );
  }

  @override
  Future<void> decidePartyRequest(String id, bool approve, int expectedParty) async {
    for (final list in _demoRes.values) {
      final i = list.indexWhere((r) => r.id == id);
      if (i < 0) continue;
      final r = list[i];
      list[i] = Reservation(
          id: r.id, date: r.date, time: r.time, party: approve ? (r.requestedParty ?? r.party) : r.party, name: r.name,
          phone: r.phone, email: r.email, note: r.note, status: r.status, source: r.source, createdAt: r.createdAt,
          requestedParty: r.requestedParty, partyRequestStatus: approve ? 'approved' : 'rejected');
      return;
    }
  }

  @override
  Future<void> updateReservation(String id, Map<String, dynamic> values) async {
    for (final list in _demoRes.values) {
      final i = list.indexWhere((r) => r.id == id);
      if (i < 0) continue;
      final r = list[i];
      list[i] = Reservation(
          id: r.id, date: r.date, time: r.time, party: r.party, name: r.name, phone: r.phone, email: r.email,
          note: values.containsKey('note') ? values['note'] as String? : r.note,
          status: values['status'] as String? ?? r.status, source: r.source, createdAt: r.createdAt,
          requestedParty: r.requestedParty, partyRequestStatus: r.partyRequestStatus);
      return;
    }
  }
}
