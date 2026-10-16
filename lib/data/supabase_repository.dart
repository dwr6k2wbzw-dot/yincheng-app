import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide toDouble;

import '../config.dart';
import 'models.dart';
import 'row_cache.dart';
import 'repository.dart';

/// 透過 Supabase（PostgREST）讀寫。所有權限由資料庫的 RLS 與觸發器把關，App 端不做權限判斷以外的假設。
class SupabaseRepository implements Repository {
  SupabaseClient get _db => Supabase.instance.client;
  static final _day = DateFormat('yyyy-MM-dd');

  // ---------------- 帳號 ----------------
  @override
  Stream<bool> get signedInChanges => _db.auth.onAuthStateChange.map((e) => e.session != null);
  @override
  bool get isSignedIn => _db.auth.currentSession != null;
  @override
  String? get currentUserId => _db.auth.currentUser?.id;
  @override
  String? get currentUserEmail => _db.auth.currentUser?.email;
  @override
  Future<void> signIn(String email, String password) =>
      _db.auth.signInWithPassword(email: email.trim(), password: password);
  @override
  Future<void> signOut() async {
    await RowCache.clear(); // 登出就清掉手機裡存的上次資料
    await _db.auth.signOut();
  }

  // ---------------- 上次讀到的資料（打開先顯示，老闆 2026-10-16） ----------------
  String _ck(String what, List<Object?> args) => '${currentUserId ?? '-'}|$what|${args.join('|')}';
  T _remember<T>(String key, dynamic raw, T Function(dynamic) parse) {
    RowCache.put(key, raw);
    return parse(raw);
  }

  T? _peek<T>(String key, T Function(dynamic) parse) {
    final raw = RowCache.get(key);
    if (raw == null) return null;
    try {
      return parse(raw);
    } catch (_) {
      return null; // 舊格式讀不懂就當沒有
    }
  }

  static List<Map<String, dynamic>> _rows(dynamic raw) =>
      [for (final r in raw as List) Map<String, dynamic>.from(r as Map)];
  static Map<String, dynamic>? _row(dynamic raw) => raw == null ? null : Map<String, dynamic>.from(raw as Map);

  static List<Membership> _parseMemberships(dynamic raw) {
    final list = _rows(raw).map(Membership.fromRow).toList();
    list.sort((a, b) => a.storeName.compareTo(b.storeName));
    return list;
  }

  static FixedCosts _parseFixed(dynamic raw) {
    final rows = _rows(raw);
    double? pick(String c) {
      final r = rows.where((x) => x['category'] == c).toList();
      return r.isEmpty ? null : toDouble(r.first['amount']);
    }

    return FixedCosts(rent: pick('rent'), payroll: pick('payroll'));
  }

  String _mk(DateTime month) => _day.format(DateTime(month.year, month.month, 1));

  @override
  List<Membership>? peekMemberships() => _peek(_ck('members', []), _parseMemberships);
  @override
  MonthlySummary? peekMonthlySummary(String storeId, DateTime month) => _peek(_ck('summary', [storeId, _mk(month)]),
      (raw) => summaryFromRows(_row((raw as List)[0]), _row(raw[1]), month));
  @override
  List<DailyRevenue>? peekDailyRevenueBetween(String storeId, DateTime from, DateTime to) =>
      _peek(_ck('daily', [storeId, _day.format(from), _day.format(to)]), (raw) => _rows(raw).map(dailyFromRow).toList());
  @override
  FixedCosts? peekFixedCosts(String storeId, DateTime month) => _peek(_ck('fixed', [storeId, _mk(month)]), _parseFixed);
  @override
  List<ExpenseItem>? peekExpenseItems(String storeId, DateTime month) =>
      _peek(_ck('items', [storeId, _mk(month)]), (raw) => _rows(raw).map(ExpenseItem.fromRow).toList());
  @override
  List<RecurringExpenseItem>? peekRecurringExpenseItems(String storeId) =>
      _peek(_ck('recurring', [storeId]), (raw) => _rows(raw).map(RecurringExpenseItem.fromRow).toList());
  @override
  double? peekCardFeeRate(String storeId) =>
      _peek(_ck('cardfee', [storeId]), (raw) => raw is Map && raw['v'] == null ? 0.02 : toDouble((raw as Map)['v']));
  @override
  (double?,)? peekPettyCashBalance(String storeId) =>
      _peek(_ck('petty', [storeId]), (raw) => ((raw as Map)['v'] == null ? null : toDouble(raw['v']),));
  @override
  Future<bool> signUp(String email, String password) async {
    // 確認信的連結回到目前這個網址（GitHub Pages）
    final back = '${Uri.base.origin}${Uri.base.path}';
    final r = await _db.auth.signUp(email: email.trim(), password: password, emailRedirectTo: back);
    return r.session != null;
  }

  // ---------------- 成員管理 ----------------
  @override
  Future<int> claimInvite(String code) async =>
      (await _db.rpc('claim_invite', params: {'p_code': code}) as num).toInt();
  @override
  Future<String> createInvite(List<String> storeIds, Role role, String name) async =>
      await _db.rpc('create_invite', params: {'p_stores': storeIds, 'p_role': role.name, 'p_name': name}) as String;
  @override
  Future<List<MemberInfo>> storeMembers(String storeId) async {
    final rows = await _db.rpc('store_member_list', params: {'p_store': storeId}) as List;
    return rows.map((r) => MemberInfo.fromRow(r as Map<String, dynamic>)).toList();
  }
  @override
  Future<List<MemberInvite>> openInvites(String storeId) async {
    final rows = await _db
        .from('member_invites')
        .select('id, display_name, role, created_at, expires_at')
        .eq('store_id', storeId)
        .isFilter('claimed_at', null)
        .isFilter('revoked_at', null)
        .order('created_at', ascending: false);
    return rows.map(MemberInvite.fromRow).toList();
  }
  @override
  Future<void> revokeInvite(String inviteId) => _db.rpc('revoke_invite', params: {'p_id': inviteId});
  @override
  Future<void> updateMember(String storeId, String userId, {Role? role, bool? active}) async {
    final rows = await _db
        .from('store_members')
        .update({if (role != null) 'role': role.name, if (active != null) 'active': active})
        .eq('store_id', storeId)
        .eq('user_id', userId)
        .select('user_id');
    if (rows.isEmpty) throw Exception('message: 沒有權限修改這位成員,');
  }

  // ---------------- 店家 ----------------
  @override
  Future<List<Membership>> myMemberships() async {
    final rows = await _db
        .from('store_members')
        .select('store_id, role, display_name, stores(name)')
        .eq('user_id', currentUserId!)
        .eq('active', true);
    return _remember(_ck('members', []), rows, _parseMemberships);
  }

  // ---------------- 營運總覽 ----------------
  @override
  Future<MonthlySummary> monthlySummary(String storeId, DateTime month) async {
    final m = _day.format(DateTime(month.year, month.month, 1));
    // 營收與成本同時查（原本一個等一個，載入變慢）
    final r = await Future.wait([
      _db.from('v_monthly_revenue').select().eq('store_id', storeId).eq('period_month', m).maybeSingle(),
      _db.from('v_monthly_cost').select().eq('store_id', storeId).eq('period_month', m).maybeSingle(),
    ]);
    return _remember(_ck('summary', [storeId, _mk(month)]), [r[0], r[1]],
        (raw) => summaryFromRows(_row((raw as List)[0]), _row(raw[1]), month));
  }

  @override
  Future<List<DailyRevenue>> recentDailyRevenue(String storeId, int days) async {
    final from = _day.format(DateTime.now().subtract(Duration(days: days)));
    final rows = await _db
        .from('daily_revenue')
        .select('biz_date, revenue, guests')
        .eq('store_id', storeId)
        .eq('kind', 'daily')
        .gte('biz_date', from)
        .order('biz_date');
    return rows.map(dailyFromRow).toList();
  }

  @override
  Future<List<DailyRevenue>> dailyRevenueBetween(String storeId, DateTime from, DateTime to) async {
    final rows = await _db
        .from('daily_revenue')
        .select('biz_date, revenue, guests')
        .eq('store_id', storeId)
        .eq('kind', 'daily')
        .gte('biz_date', _day.format(from))
        .lte('biz_date', _day.format(to))
        .order('biz_date');
    return _remember(_ck('daily', [storeId, _day.format(from), _day.format(to)]), rows,
        (raw) => _rows(raw).map(dailyFromRow).toList());
  }

  @override
  Future<List<Issue>> consistencyIssues(String storeId) async {
    final rows = await _db.rpc('consistency_report', params: {'p_store': storeId}) as List;
    return rows
        .map((r) => Issue(r['check_name'] as String, r['severity'] as String, r['detail'] as String? ?? ''))
        .toList();
  }

  @override
  Future<double?> pettyCashBalance(String storeId) async {
    final r = await _db
        .from('v_petty_cash_monthly')
        .select('closing_balance')
        .eq('store_id', storeId)
        .order('period_month', ascending: false)
        .limit(1)
        .maybeSingle();
    final v = r == null ? null : toDouble(r['closing_balance']);
    RowCache.put(_ck('petty', [storeId]), {'v': v});
    return v;
  }

  // ---------------- 每日營收 ----------------
  static const _revCols = 'id, biz_date, cash, credit_card, amex, deposit, guests, '
      'drinks_revenue, food_revenue, project_amount, coffee_revenue, ramen_revenue, note, source';

  @override
  Future<List<RevenueEntry>> revenueEntries(String storeId, {int limit = 60}) async {
    final rows = await _db
        .from('daily_revenue')
        .select(_revCols)
        .eq('store_id', storeId)
        .eq('kind', 'daily')
        .order('biz_date', ascending: false)
        .limit(limit);
    return rows.map(RevenueEntry.fromRow).toList();
  }

  @override
  Future<RevenueEntry?> revenueEntryFor(String storeId, DateTime bizDate) async {
    final r = await _db
        .from('daily_revenue')
        .select(_revCols)
        .eq('store_id', storeId)
        .eq('kind', 'daily')
        .eq('biz_date', _day.format(bizDate))
        .maybeSingle();
    return r == null ? null : RevenueEntry.fromRow(r);
  }

  @override
  Future<void> saveRevenueEntry(String storeId, RevenueEntry e) async {
    if (e.id == null) {
      // 新增：updated_by／updated_at 由資料庫填入；同一天只能有一筆（資料庫唯一索引擋重複）
      await _db.from('daily_revenue').insert({
        'store_id': storeId,
        'biz_date': _day.format(e.bizDate),
        'kind': 'daily',
        ...e.toValues(),
      });
    } else {
      final rows = await _db.from('daily_revenue').update(e.toValues()).eq('id', e.id!).select('id');
      if (rows.isEmpty) throw Exception('message: 沒有權限修改這天的營收（可能已月結鎖帳）,');
    }
  }

  @override
  Future<DateTime?> lastExcelSync(String storeId) async {
    final r = await _db
        .from('import_batches')
        .select('imported_at')
        .eq('store_id', storeId)
        .order('imported_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return r == null ? null : DateTime.tryParse(r['imported_at'] as String)?.toLocal();
  }

  // ---------------- 租金／人事成本 ----------------
  @override
  Future<FixedCosts> fixedCosts(String storeId, DateTime month) async {
    final rows = await _db
        .from('expenses')
        .select('category, amount')
        .eq('store_id', storeId)
        .eq('period_month', _day.format(DateTime(month.year, month.month, 1)))
        .inFilter('category', ['rent', 'payroll']);
    return _remember(_ck('fixed', [storeId, _mk(month)]), rows, _parseFixed);
  }

  @override
  Future<void> saveFixedCost(String storeId, DateTime month, String category, double amount) async {
    final m = _day.format(DateTime(month.year, month.month, 1));
    final existing = await _db
        .from('expenses')
        .select('id')
        .eq('store_id', storeId)
        .eq('period_month', m)
        .eq('category', category)
        .maybeSingle();
    if (existing == null) {
      await _db.from('expenses').insert({'store_id': storeId, 'period_month': m, 'category': category, 'amount': amount});
    } else {
      final rows = await _db.from('expenses').update({'amount': amount}).eq('id', existing['id']).select('id');
      if (rows.isEmpty) throw Exception('message: 沒有權限修改（可能已月結鎖帳）,');
    }
  }
  @override
  Future<List<ExpenseItem>> expenseItems(String storeId, DateTime month) async {
    final rows = await _db
        .from('expense_items')
        .select('id, name, category, amount')
        .eq('store_id', storeId)
        .eq('period_month', _day.format(DateTime(month.year, month.month, 1)))
        .order('created_at');
    return _remember(_ck('items', [storeId, _mk(month)]), rows, (raw) => _rows(raw).map(ExpenseItem.fromRow).toList());
  }

  @override
  Future<void> saveExpenseItem(String storeId, DateTime month, ExpenseItem item, {bool isNew = false}) async {
    final row = {'name': item.name.trim(), 'category': item.category, 'amount': item.amount};
    if (isNew) {
      await _db.from('expense_items').insert({
        ...row,
        'store_id': storeId,
        'period_month': _day.format(DateTime(month.year, month.month, 1)),
      });
    } else {
      final r = await _db.from('expense_items').update(row).eq('id', item.id).select('id');
      if (r.isEmpty) throw Exception('message: 沒有權限修改（只有老闆可以）,');
    }
  }

  @override
  Future<void> deleteExpenseItem(String itemId) async {
    final r = await _db.from('expense_items').delete().eq('id', itemId).select('id');
    if (r.isEmpty) throw Exception('message: 沒有權限刪除（只有老闆可以）,');
  }

  // ---------------- 0039 刷卡手續費率 ----------------
  @override
  Future<double> cardFeeRate(String storeId) async {
    final r = await _db.from('store_settings').select('card_fee_rate').eq('store_id', storeId).maybeSingle();
    final rate = r == null ? 0.02 : toDouble(r['card_fee_rate']);
    RowCache.put(_ck('cardfee', [storeId]), {'v': rate});
    return rate;
  }

  @override
  Future<void> saveCardFeeRate(String storeId, double rate) async {
    await _db.from('store_settings').upsert({'store_id': storeId, 'card_fee_rate': rate}, onConflict: 'store_id');
  }

  // ---------------- 0039 每月固定支出 ----------------
  @override
  Future<List<RecurringExpenseItem>> recurringExpenseItems(String storeId) async {
    final rows = await _db
        .from('recurring_expense_items')
        .select('id, name, category, amount')
        .eq('store_id', storeId)
        .eq('active', true)
        .order('created_at');
    return _remember(_ck('recurring', [storeId]), rows, (raw) => _rows(raw).map(RecurringExpenseItem.fromRow).toList());
  }

  @override
  Future<void> saveRecurringExpenseItem(String storeId, RecurringExpenseItem item, {bool isNew = false}) async {
    final row = {'name': item.name.trim(), 'category': item.category, 'amount': item.amount};
    if (isNew) {
      await _db.from('recurring_expense_items').insert({...row, 'store_id': storeId});
    } else {
      final r = await _db.from('recurring_expense_items').update(row).eq('id', item.id).select('id');
      if (r.isEmpty) throw Exception('message: 沒有權限修改（只有老闆可以）,');
    }
  }

  @override
  Future<void> deleteRecurringExpenseItem(String itemId) async {
    final r = await _db.from('recurring_expense_items').delete().eq('id', itemId).select('id');
    if (r.isEmpty) throw Exception('message: 沒有權限刪除（只有老闆可以）,');
  }


  // ---------------- 進貨 ----------------
  @override
  Future<DateTime> businessDate(String storeId) async {
    final r = await _db.rpc('business_date', params: {'p_store': storeId});
    return toDate(r) ?? DateTime.now();
  }

  @override
  Future<List<CostCategory>> costCategories() async {
    final rows =
        await _db.from('cost_categories').select('code, name, store_name, cost_group, in_misc_rate, selectable, display_as').order('sort_order');
    final list = rows
        .map((r) => CostCategory.full(r['code'] as String, r['name'] as String, r['store_name'] as String?,
            costGroup: r['cost_group'] as String? ?? 'other', inMiscRate: r['in_misc_rate'] as bool? ?? false,
            selectable: r['selectable'] as bool? ?? true, displayAs: r['display_as'] as String?))
        .toList();
    // 老闆指定的順序優先（List.sort 不穩定，所以用原本位置當第二排序）
    final pos = {for (final (i, c) in list.indexed) c.code: i};
    int rank(CostCategory c) {
      final i = AppConfig.categoryOrder.indexOf(c.code);
      return i < 0 ? 1000 + pos[c.code]! : i;
    }
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  // ---------------- 班表 ----------------
  @override
  Future<ShiftMonth> shiftMonth(String storeId, DateTime month) async {
    final from = DateTime(month.year, month.month, 1);
    final to = DateTime(month.year, month.month + 1, 1);
    final m = _day.format(from);
    final r = await Future.wait([
      _db.from('shift_people').select().eq('store_id', storeId).order('sort_order').order('name'),
      _db
          .from('shift_entries')
          .select('person_id, work_date, mark')
          .eq('store_id', storeId)
          .gte('work_date', m)
          .lt('work_date', _day.format(to))
          .limit(5000),
      _db.from('shift_day_notes').select('note_date, note').eq('store_id', storeId).gte('note_date', m).lt('note_date', _day.format(to)),
      _db.from('shift_month_stats').select('person_id, should_off, prev_unused_special, comp_unused, special_total').eq('store_id', storeId).eq('period_month', m),
      _db.from('shift_month_files').select('photo_path').eq('store_id', storeId).eq('period_month', m),
    ]);
    final people = (r[0] as List).map((x) => ShiftPerson.fromRow(x as Map<String, dynamic>)).toList();
    final marks = <String, Map<int, String>>{};
    for (final e in r[1] as List) {
      final d = DateTime.parse(e['work_date'] as String).day;
      marks.putIfAbsent(e['person_id'] as String, () => {})[d] = e['mark'] as String;
    }
    final notes = {for (final n in r[2] as List) DateTime.parse(n['note_date'] as String).day: n['note'] as String};
    double? n(dynamic v) => v == null ? null : toDouble(v);
    final stats = {
      for (final s in r[3] as List)
        s['person_id'] as String: ShiftStats(
          shouldOff: n(s['should_off']),
          prevUnused: n(s['prev_unused_special']),
          compUnused: n(s['comp_unused']),
          specialTotal: n(s['special_total']),
        )
    };
    final files = r[4] as List;
    return ShiftMonth(from, people, marks, notes, stats, files.isEmpty ? null : files.first['photo_path'] as String);
  }

  @override
  Future<void> setShift(String storeId, String personId, DateTime date, String? mark) async {
    if (mark == null) {
      await _db.from('shift_entries').delete().eq('person_id', personId).eq('work_date', _day.format(date));
    } else {
      await _db.from('shift_entries').upsert(
          {'store_id': storeId, 'person_id': personId, 'work_date': _day.format(date), 'mark': mark},
          onConflict: 'person_id,work_date');
    }
  }

  @override
  Future<void> setShiftNote(String storeId, DateTime date, String? note) async {
    if (note == null || note.trim().isEmpty) {
      await _db.from('shift_day_notes').delete().eq('store_id', storeId).eq('note_date', _day.format(date));
    } else {
      await _db.from('shift_day_notes').upsert(
          {'store_id': storeId, 'note_date': _day.format(date), 'note': note.trim()},
          onConflict: 'store_id,note_date');
    }
  }

  @override
  Future<void> saveShiftPerson(String storeId, ShiftPerson p, {bool isNew = false}) async {
    final v = {
      'name': p.name.trim(),
      'kind': p.kind,
      'sort_order': p.sortOrder,
      'hire_date': p.hireDate == null ? null : _day.format(p.hireDate!),
      'active': p.active,
      'role_code': (p.roleCode?.trim().isEmpty ?? true) ? null : p.roleCode!.trim(),
    };
    if (isNew) {
      await _db.from('shift_people').insert({...v, 'store_id': storeId});
    } else {
      final rows = await _db.from('shift_people').update(v).eq('id', p.id).select('id');
      if (rows.isEmpty) throw Exception('message: 沒有權限修改班表人員,');
    }
  }

  @override
  Future<void> saveShiftStats(String storeId, String personId, DateTime month, ShiftStats s) =>
      _db.from('shift_month_stats').upsert({
        'store_id': storeId,
        'person_id': personId,
        'period_month': _day.format(DateTime(month.year, month.month, 1)),
        'should_off': s.shouldOff,
        'prev_unused_special': s.prevUnused,
        'comp_unused': s.compUnused,
        'special_total': s.specialTotal,
      }, onConflict: 'person_id,period_month');

  @override
  Future<void> uploadShiftPhoto(String storeId, DateTime month, Uint8List jpeg) async {
    final m = DateFormat('yyyy-MM').format(month);
    final path = '$storeId/schedules/$m-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage.from('receipts').uploadBinary(path, jpeg,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
    await _db.from('shift_month_files').upsert({
      'store_id': storeId,
      'period_month': _day.format(DateTime(month.year, month.month, 1)),
      'photo_path': path,
    }, onConflict: 'store_id,period_month');
  }

  // ---------------- 交接事項與工作提醒 ----------------
  @override
  Future<HandoverBoard> handoverBoard(String storeId, {bool withSchedule = false}) async {
    final today = bizToday();
    final since = _day.format(today.subtract(const Duration(days: 62)));
    final r = await Future.wait(<Future<dynamic>>[
      _db
          .from('handover_notes')
          .select('id, body, photo_path, author_id, author_name, created_at, resolved_at, resolved_name, edited_at, edited_name, handover_reads(user_id, user_name)')
          .eq('store_id', storeId)
          .order('created_at', ascending: false)
          .limit(80),
      _db.from('work_reminders').select().eq('store_id', storeId).order('created_at'),
      _db.from('reminder_done').select().eq('store_id', storeId).gte('occurrence', since),
      if (withSchedule) shiftMonth(storeId, today),
    ]);
    final notes = (r[0] as List).map((x) => HandoverNote.fromRow(x as Map<String, dynamic>)).toList();
    final rem = (r[1] as List).map((x) => WorkReminder.fromRow(x as Map<String, dynamic>)).toList();
    final done = {
      for (final x in (r[2] as List).map((x) => ReminderDone.fromRow(x as Map<String, dynamic>))) x.key: x,
    };
    final sm = withSchedule ? r[3] as ShiftMonth : null;
    return HandoverBoard(notes, rem, done, sm?.people ?? const [],
        {for (final p in sm?.people ?? const <ShiftPerson>[]) p.id: sm!.mark(p.id, today.day)});
  }

  @override
  Future<void> addHandover(String storeId, String body, Uint8List? jpeg) async {
    String? path;
    if (jpeg != null) {
      path = '$storeId/handover/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _db.storage.from('receipts').uploadBinary(path, jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
    }
    await _db.from('handover_notes').insert({'store_id': storeId, 'body': body, 'photo_path': path});
  }

  @override
  Future<void> updateHandover(String noteId, String body) async {
    final rows = await _db.from('handover_notes').update({'body': body.trim()}).eq('id', noteId).select('id');
    if (rows.isEmpty) throw Exception('message: 這則交接已被刪除或沒有權限修改,');
  }

  @override
  Future<void> setHandoverResolved(String noteId, bool resolved) => _db
      .from('handover_notes')
      .update({'resolved_at': resolved ? DateTime.now().toUtc().toIso8601String() : null}).eq('id', noteId);

  @override
  Future<void> markHandoverRead(String storeId, List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    await _db.from('handover_reads').upsert(
      [for (final id in noteIds) {'store_id': storeId, 'note_id': id}],
      onConflict: 'note_id,user_id',
      ignoreDuplicates: true,
    );
  }

  @override
  Future<void> deleteHandover(String noteId) => _db.from('handover_notes').delete().eq('id', noteId);

  @override
  Future<NotificationFeed> notifications(String storeId) async {
    final since = DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String();
    final r = await Future.wait<dynamic>([
      _db
          .from('app_notifications')
          .select()
          .eq('store_id', storeId)
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(50),
      _db.from('notification_reads').select('seen_at').eq('store_id', storeId).maybeSingle(),
    ]);
    final me = currentUserId;
    final items = (r[0] as List)
        .map((x) => AppNotification.fromRow(x as Map<String, dynamic>))
        .where((n) => me == null || n.actorId != me)
        .toList();
    final seen = (r[1] as Map<String, dynamic>?)?['seen_at'] as String?;
    return NotificationFeed(items, seen == null ? null : DateTime.parse(seen).toLocal());
  }

  @override
  Future<void> markNotificationsSeen(String storeId) =>
      _db.rpc('mark_notifications_seen', params: {'p_store': storeId});

  @override
  Future<void> saveReminder(String storeId, WorkReminder r, {bool isNew = false}) async {
    final row = {
      'title': r.title.trim(),
      'detail': (r.detail?.trim().isEmpty ?? true) ? null : r.detail!.trim(),
      'repeat': r.repeat,
      'due_date': r.repeat == 'once' && r.dueDate != null ? _day.format(r.dueDate!) : null,
      'weekday': r.repeat == 'weekly' ? r.weekday : null,
      'month_day': r.repeat == 'monthly' ? r.monthDay : null,
      'assign_person_id': r.assignOnShift ? null : r.assignPersonId,
      'assign_on_shift': r.assignOnShift,
      'active': r.active,
    };
    if (isNew) {
      await _db.from('work_reminders').insert({...row, 'store_id': storeId, 'start_date': _day.format(bizToday())});
    } else {
      await _db.from('work_reminders').update(row).eq('id', r.id);
    }
  }

  @override
  Future<void> deleteReminder(String reminderId) => _db.from('work_reminders').delete().eq('id', reminderId);

  @override
  Future<void> setReminderDone(String storeId, String reminderId, DateTime occurrence, bool done) async {
    if (done) {
      await _db.from('reminder_done').insert({'store_id': storeId, 'reminder_id': reminderId, 'occurrence': _day.format(occurrence)});
    } else {
      await _db.from('reminder_done').delete().eq('reminder_id', reminderId).eq('occurrence', _day.format(occurrence));
    }
  }

  @override
  Future<String> shiftPhotoUrl(String path) => _db.storage.from('receipts').createSignedUrl(path, 3600);

  @override
  Future<List<String>> excelVendorNames(String storeId) async {
    final now = DateTime.now();
    final rows = await _db
        .from('purchases')
        .select('memo')
        .eq('store_id', storeId)
        .eq('source', 'import')
        .eq('paid_by', 'vendor')
        .gte('period_month', _day.format(DateTime(now.year, now.month - 5, 1)))
        .limit(5000);
    return excelVendorNamesFromRows(rows);
  }

  @override
  Future<List<String>> memberNames(String storeId) async {
    final rows = await _db.from('store_members').select('display_name').eq('store_id', storeId).eq('active', true);
    final names = {for (final r in rows) ((r['display_name'] as String?) ?? '').trim()}..remove('');
    return names.toList()..sort();
  }

  @override
  Future<VendorHints> vendorHints(String storeId) async {
    final now = DateTime.now();
    final rows = await _db
        .from('purchases')
        .select('category_code, paid_by, memo, vendor_name, suppliers!purchases_supplier_same_store(name)')
        .eq('store_id', storeId)
        .gte('period_month', _day.format(DateTime(now.year, now.month - 6, 1)))
        .limit(5000);
    return (vendor: vendorHintsFromRows(rows, paidBy: 'vendor'), petty: vendorHintsFromRows(rows, paidBy: 'petty_cash'));
  }

  @override
  Future<List<Supplier>> suppliers(String storeId) async {
    final rows = await _db
        .from('suppliers')
        .select('id, name, default_category')
        .eq('store_id', storeId)
        .eq('active', true)
        .order('name');
    return rows.map((r) => Supplier(r['id'] as String, r['name'] as String, r['default_category'] as String?)).toList();
  }

  @override
  Future<List<Purchase>> recentPurchases(String storeId, {int limit = 30}) async {
    final rows = await _db
        .from('purchases')
        .select('id, purchase_date, category_code, memo, amount, paid_by, reconciled, source, superseded_by, excel_covered_at, created_by, vendor_name, no_receipt, '
            'suppliers!purchases_supplier_same_store(name)')
        .eq('store_id', storeId)
        .order('purchase_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Purchase.fromRow).toList();
  }

  @override
  Future<List<Purchase>> monthPurchases(String storeId, DateTime month) async {
    final rows = await _db
        .from('purchases')
        .select('id, purchase_date, category_code, memo, amount, paid_by, reconciled, source, superseded_by, excel_covered_at, created_by, vendor_name, no_receipt, '
            'suppliers!purchases_supplier_same_store(name)')
        .eq('store_id', storeId)
        .eq('period_month', _day.format(DateTime(month.year, month.month, 1)))
        .order('purchase_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(2000);
    return rows.map(Purchase.fromRow).toList();
  }

  @override
  Future<List<VendorSlip>> vendorSlips(String storeId, DateTime month) async {
    final from = DateTime(month.year, month.month, 1);
    final rows = await _db
        .from('vendor_slips')
        .select('id, vendor, slip_no, slip_date, total, note, status, source, source_file, photo_path, '
            'vendor_slip_lines(line_no, item_code, item_name, qty, unit, unit_price, amount)')
        .eq('store_id', storeId)
        .eq('period_month', _day.format(from)) // 歸屬月份＝Dropbox「M月份」資料夾
        .order('slip_date')
        .order('slip_no')
        .limit(2000);
    final slips = rows.map(VendorSlip.fromRow).toList();
    // 類別、付款方式：照片路徑與當初那筆進貨相同，用它找回（老闆 2026-10-12）
    final paths = slips.map((s) => s.photoPath).whereType<String>().toSet().toList();
    if (paths.isNotEmpty) {
      final cats = <String, String>{}, paid = <String, String>{}, filer = <String, String>{};
      for (var i = 0; i < paths.length; i += 100) {
        final part = paths.sublist(i, i + 100 > paths.length ? paths.length : i + 100);
        final ps = await _db
            .from('purchases')
            .select('photo_path, category_code, paid_by, memo')
            .eq('store_id', storeId)
            .inFilter('photo_path', part);
        for (final p in ps) {
          cats[p['photo_path'] as String] = p['category_code'] as String;
          paid[p['photo_path'] as String] = p['paid_by'] as String;
          final memo = (p['memo'] as String?)?.trim();
          if (memo != null && memo.isNotEmpty) filer[p['photo_path'] as String] = memo;
        }
      }
      for (final s in slips) {
        if (s.photoPath != null) {
          s.categoryCode = cats[s.photoPath];
          s.paidBy = paid[s.photoPath];
          s.filer = filer[s.photoPath];
        }
      }
    }
    return slips;
  }

  @override
  Future<String> saveVendorSlip(String storeId, VendorSlip s) async {
    final id = await _db.rpc('save_vendor_slip', params: {
      'p_id': s.id.isEmpty ? null : s.id,
      'p_store': storeId,
      'p_vendor': s.vendor,
      'p_slip_no': s.slipNo,
      'p_date': _day.format(s.date),
      'p_total': s.total,
      'p_note': s.note ?? '',
      'p_status': s.status,
      if (s.periodMonth != null) 'p_period': _day.format(s.periodMonth!),
      'p_lines': [
        for (final l in s.lines)
          {
            'item_code': l.itemCode ?? '',
            'item_name': l.itemName,
            'qty': l.qty,
            'unit': l.unit ?? '',
            'unit_price': l.unitPrice,
            'amount': l.amount,
          }
      ],
    });
    return id as String;
  }

  @override
  Future<void> deleteVendorSlip(String slipId) async {
    final rows = await _db.from('vendor_slips').delete().eq('id', slipId).select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限刪除這張單據,');
  }

  @override
  Future<List<String>> failedSlipFiles(String storeId) async {
    final rows = await _db
        .from('vendor_slip_files')
        .select('file_name')
        .eq('store_id', storeId)
        .eq('status', 'failed')
        .order('processed_at');
    return rows.map((r) => r['file_name'] as String).toList();
  }

  @override
  Future<void> addPurchase(NewPurchase p) async {
    // created_by、period_month 由資料庫填入；client_request_id 防止重送重複
    String? photoPath;
    if (p.photoJpeg != null) {
      // 路徑規則：receipts/{店家 id}/...（資料庫與 Storage 權限都會檢查）
      photoPath = '${p.storeId}/slips/${p.clientRequestId}.jpg';
      try {
        await _db.storage.from('receipts').uploadBinary(photoPath, p.photoJpeg!,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
      } on StorageException catch (e) {
        // 網路重送：同一張表單的照片已經上傳過
        if (e.statusCode != '409' && !e.message.contains('exists')) rethrow;
      }
    }
    await _db.from('purchases').insert({
      'store_id': p.storeId,
      'purchase_date': _day.format(p.purchaseDate),
      'category_code': p.categoryCode,
      'supplier_id': p.supplierId,
      'vendor_name': (p.vendorName?.trim().isEmpty ?? true) ? null : p.vendorName!.trim(),
      if (photoPath != null) 'photo_path': photoPath,
      'memo': (p.memo?.trim().isEmpty ?? true) ? null : p.memo!.trim(),
      'amount': p.amount,
      'paid_by': p.paidBy,
      'client_request_id': p.clientRequestId,
      if (p.noReceipt && photoPath == null) 'no_receipt': true,
    });
    // 送貨單照片 → 銷貨單草稿。進貨已存好，這步失敗不影響進貨
    if (photoPath != null && p.amount > 0 && p.slipDraft) {
      // 0040：存檔當下就建立草稿（內容由資料庫從這筆進貨讀）
      try {
        await _db.rpc('create_photo_slip_draft', params: {'p_photo_path': photoPath});
        return;
      } catch (_) {
        // 失敗（例如網路斷了）才放進佇列，由每小時的同步補做（0034）
      }
      try {
        final hex = StringBuffer(r'\x');
        for (final b in p.photoJpeg!) {
          hex.write(b.toRadixString(16).padLeft(2, '0'));
        }
        await _db.from('slip_photo_queue').insert({
          'store_id': p.storeId,
          'photo_path': photoPath,
          'image': hex.toString(),
          'vendor_name': (p.slipVendor?.trim().isEmpty ?? true) ? null : p.slipVendor!.trim(),
          'amount': p.amount,
          'purchase_date': _day.format(p.purchaseDate),
        });
      } catch (_) {}
    }
  }

  @override
  Future<void> updatePurchase(String purchaseId, NewPurchase p) async {
    final rows = await _db
        .from('purchases')
        .update({
          'purchase_date': _day.format(p.purchaseDate),
          'period_month': _day.format(DateTime(p.purchaseDate.year, p.purchaseDate.month, 1)),
          'category_code': p.categoryCode,
          'supplier_id': p.supplierId,
          'vendor_name': (p.vendorName?.trim().isEmpty ?? true) ? null : p.vendorName!.trim(),
          'memo': (p.memo?.trim().isEmpty ?? true) ? null : p.memo!.trim(),
          'amount': p.amount,
          'paid_by': p.paidBy,
        })
        .eq('id', purchaseId)
        .select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限修改這筆進貨（只有建立的人或老闆、店長可以改）,');
  }

  @override
  Future<void> deletePurchase(String purchaseId) async {
    final rows = await _db.from('purchases').delete().eq('id', purchaseId).select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限刪除這筆進貨（只有建立的人或老闆、店長可以刪）,');
  }

  @override
  Future<void> setReconciled(String purchaseId, bool reconciled) async {
    final rows = await _db.from('purchases').update({'reconciled': reconciled}).eq('id', purchaseId).select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限修改這筆進貨（可能已核銷或已鎖帳）,');
  }

  // ---------------- 盤點 ----------------
  @override
  Future<List<Product>> products(String storeId) async {
    // 只列出員工有權限的欄位（cost_price 員工不可讀，不能用 select *）
    final rows = await _db
        .from('products')
        .select('id, name, category, unit')
        .eq('store_id', storeId)
        .eq('active', true)
        .order('category')
        .order('name');
    return rows
        .map((r) => Product(r['id'] as String, r['name'] as String, r['category'] as String, r['unit'] as String))
        .toList();
  }

  @override
  Future<List<StockCount>> stockCounts(String storeId) async {
    final rows = await _db
        .from('stock_counts')
        .select('id, biz_date, counted_by, status, note, stock_count_lines(count)')
        .eq('store_id', storeId)
        .order('counted_at', ascending: false)
        .limit(30);
    return rows.map(StockCount.fromRow).toList();
  }

  @override
  Future<String> createStockCount(String storeId, String? note) async {
    final r = await _db.from('stock_counts').insert({'store_id': storeId, 'note': note}).select('id').single();
    return r['id'] as String;
  }

  @override
  Future<List<CountLine>> countLines(String countId) async {
    final rows = await _db
        .from('stock_count_lines')
        .select('product_id, qty, products!stock_count_lines_product_same_store(name, unit)')
        .eq('count_id', countId);
    return rows.map((r) {
      final p = r['products'] as Map? ?? {};
      return CountLine(r['product_id'] as String, p['name'] as String? ?? '', p['unit'] as String? ?? '', toDouble(r['qty']));
    }).toList()
      ..sort((a, b) => a.productName.compareTo(b.productName));
  }

  @override
  Future<void> upsertCountLine(String countId, String productId, double qty) async {
    await _db
        .from('stock_count_lines')
        .upsert({'count_id': countId, 'product_id': productId, 'qty': qty}, onConflict: 'count_id,product_id');
  }

  @override
  Future<void> setCountStatus(String countId, CountStatus status, {String? voidReason}) async {
    final rows = await _db
        .from('stock_counts')
        .update({'status': status.name, if (voidReason != null) 'void_reason': voidReason})
        .eq('id', countId)
        .select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限變更這份盤點,');
  }

  // ---------------- 訂位（0050） ----------------
  @override
  Future<ReservationSettings?> reservationSettings(String storeId) async {
    final r = await _db.from('reservation_settings').select().eq('store_id', storeId).maybeSingle();
    return r == null ? null : ReservationSettings.fromRow(r);
  }

  @override
  Future<void> saveReservationSettings(String storeId, Map<String, dynamic> values) async {
    final rows = await _db.from('reservation_settings').update(values).eq('store_id', storeId).select('store_id');
    if (rows.isEmpty) throw Exception('message: 只有老闆可以修改訂位設定,');
  }

  @override
  Future<List<Reservation>> reservations(String storeId, DateTime from, DateTime to) async {
    final rows = await _db
        .from('reservations')
        .select('id, slot_date, slot_time, party_size, guest_name, phone, email, note, status, source, email_error, created_at')
        .eq('store_id', storeId)
        .gte('slot_date', _day.format(from))
        .lte('slot_date', _day.format(to))
        .order('slot_date')
        .order('slot_time')
        .order('created_at');
    return rows.map(Reservation.fromRow).toList();
  }

  @override
  Future<void> addReservation(String storeId,
      {required DateTime date, required String time, required int party, required String name, required String phone, String? email, String? note}) async {
    await _db.from('reservations').insert({
      'store_id': storeId,
      'slot_date': _day.format(date),
      'slot_time': time,
      'party_size': party,
      'guest_name': name,
      'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (note != null && note.isNotEmpty) 'note': note,
      'source': 'app',
    });
  }

  @override
  Future<void> updateReservation(String id, Map<String, dynamic> values) async {
    final rows = await _db.from('reservations').update(values).eq('id', id).select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限修改這筆訂位,');
  }
}
