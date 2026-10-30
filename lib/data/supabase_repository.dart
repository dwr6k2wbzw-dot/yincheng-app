import 'dart:convert';
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
        .select('id, display_name, role, created_at, expires_at, invited_by')
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

  // ---------------- 0076 廠商資料 ----------------
  @override
  Future<List<VendorContact>> vendorContacts(String storeId) async {
    final rows = await _db
        .from('vendor_contacts')
        .select('id, kind, name, items, contact, bank, account, note, billing_day')
        .eq('store_id', storeId)
        .order('kind')
        .order('sort_order')
        .order('name');
    return rows.map(VendorContact.fromRow).toList();
  }

  @override
  Future<void> saveVendorContact(String storeId, VendorContact v) async {
    if (v.id == null) {
      await _db.from('vendor_contacts').insert({...v.toRow(), 'store_id': storeId});
    } else {
      final r = await _db.from('vendor_contacts').update(v.toRow()).eq('id', v.id!).select('id');
      if (r.isEmpty) throw Exception('message: 沒有權限修改（只有老闆、店長可以）,');
    }
  }

  @override
  Future<void> deleteVendorContact(String id) async {
    final r = await _db.from('vendor_contacts').delete().eq('id', id).select('id');
    if (r.isEmpty) throw Exception('message: 沒有權限刪除（只有老闆、店長可以）,');
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
    final r = await Future.wait<dynamic>([
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
      _db.from('shift_month_files').select('id, photo_path, uploaded_at').eq('store_id', storeId).eq('period_month', m).order('uploaded_at'),
      // 照片辨識草稿（0070）：員工、兼職讀不到（RLS），會是空的
      _db
          .from('shift_photo_drafts')
          .select('id, status, created_at, processed_at, message, photo_count, draft')
          .eq('store_id', storeId)
          .eq('period_month', m)
          .inFilter('status', ['pending', 'ready', 'failed'])
          .order('created_at', ascending: false)
          .limit(1)
          .then((v) => v, onError: (_) => <Map<String, dynamic>>[]),
      // 班別／時段清單（0075）：讀不到就用 App 內建設定
      _db
          .from('shift_mark_options')
          .select('id, kind, mark, time_range, sort_order')
          .eq('store_id', storeId)
          .order('sort_order')
          .order('mark')
          .then<Object?>((v) => v, onError: (_) => null),
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
    final photos = [
      for (final f in r[4] as List)
        ShiftPhoto(f['id'] as String, f['photo_path'] as String,
            f['uploaded_at'] == null ? null : DateTime.parse(f['uploaded_at'] as String).toLocal())
    ];
    final drafts = r[5] as List;
    final opts = r[6] as List?;
    return ShiftMonth(
        from,
        people,
        marks,
        notes,
        stats,
        photos,
        drafts.isEmpty ? null : ShiftDraft.fromRow(drafts.first as Map<String, dynamic>),
        opts == null
            ? const ShiftOptions([], loaded: false)
            : ShiftOptions([for (final x in opts) ShiftMarkOption.fromRow(x as Map<String, dynamic>)]));
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
    // 0070：每張照片一列（不再蓋掉同月的舊照片）；另附影像給每小時同步的 Claude 辨識成班表草稿
    final hex = StringBuffer(r'\x');
    for (final b in jpeg) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    await _db.from('shift_month_files').insert({
      'store_id': storeId,
      'period_month': _day.format(DateTime(month.year, month.month, 1)),
      'photo_path': path,
      'image': hex.toString(),
    });
  }

  @override
  Future<void> deleteShiftPhoto(String photoId) async {
    final rows = await _db.from('shift_month_files').delete().eq('id', photoId).select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限刪除這張照片（只有老闆、店長可以刪）,');
  }

  @override
  Future<int> applyShiftDraft(ShiftDraft d) async {
    final n = await _db.rpc('apply_shift_draft', params: {'p_id': d.id, 'p_expected': d.processedAtRaw});
    return (n as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> dismissShiftDraft(String draftId) async {
    await _db.from('shift_photo_drafts').update({'status': 'dismissed'}).eq('id', draftId);
  }

  // ---------------- 交接事項與工作提醒 ----------------
  @override
  Future<HandoverBoard> handoverBoard(String storeId, {bool withSchedule = false}) async {
    final today = bizToday();
    final since = _day.format(today.subtract(const Duration(days: 62)));
    final r = await Future.wait(<Future<dynamic>>[
      _db
          .from('handover_notes')
          .select('id, body, photo_path, author_id, author_name, created_at, resolved_at, resolved_name, edited_at, edited_name, important, handover_reads(user_id, user_name), handover_items(id, position, body, done_at, done_name)')
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
  Future<void> addHandover(String storeId, String body, List<String> items, Uint8List? jpeg, {bool important = false}) async {
    String? path;
    if (jpeg != null) {
      path = '$storeId/handover/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _db.storage.from('receipts').uploadBinary(path, jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
    }
    // 0060：交接與清單一次寫入
    await _db.rpc('create_handover',
        params: {'p_store': storeId, 'p_body': body, 'p_photo_path': path, 'p_items': items, 'p_important': important});
  }

  @override
  Future<void> updateHandover(String noteId, String body, List<String> items, {bool? important}) =>
      _db.rpc('update_handover', params: {
        'p_note': noteId,
        'p_body': body.trim(),
        'p_items': items,
        if (important != null) 'p_important': important,
      });

  // 0079：每家店的 LINE 通知開關（store_settings 只有老闆讀寫得到；讀不到就當作開著）
  @override
  Future<bool> lineNotifyEnabled(String storeId) async {
    final r = await _db.from('store_settings').select('line_notify_enabled').eq('store_id', storeId).maybeSingle();
    return r == null ? true : (r['line_notify_enabled'] as bool? ?? true);
  }

  @override
  Future<void> saveLineNotifyEnabled(String storeId, bool on) async {
    await _db.from('store_settings').upsert({'store_id': storeId, 'line_notify_enabled': on}, onConflict: 'store_id');
  }

  // 0081：老闆 LINE 私訊綁定（只看得到自己的）
  @override
  Future<int> lineOwnerLinks() async => (await _db.from('line_owner_links').select('line_user_id')).length;

  @override
  Future<void> linkLineOwner(String code) => _db.rpc('line_owner_link', params: {'p_code': code.trim()});

  @override
  Future<void> unlinkLineOwner() async {
    final me = currentUserId;
    if (me == null) return;
    await _db.from('line_owner_links').delete().eq('user_id', me);
  }

  @override
  Future<void> setHandoverItemDone(String itemId, bool done) async {
    final rows = await _db
        .from('handover_items')
        .update({'done_at': done ? DateTime.now().toUtc().toIso8601String() : null})
        .eq('id', itemId)
        .select('id');
    if (rows.isEmpty) throw Exception('message: 這一項已被刪除或沒有權限,');
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
  Future<List<AppNotification>> reservationEvents(String storeId) async {
    final since = DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String();
    final rows = await _db
        .from('app_notifications')
        .select()
        .eq('store_id', storeId)
        .eq('kind', 'reservation')
        .gte('created_at', since)
        .order('created_at', ascending: false)
        .limit(30);
    final me = currentUserId;
    return rows.map(AppNotification.fromRow).where((n) => me == null || n.actorId != me).toList();
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
  Future<ShiftPlanSetup> shiftPlanSetup(String storeId, DateTime month) async {
    final from = DateTime(month.year, month.month, 1);
    final to = DateTime(month.year, month.month + 1, 1);
    final r = await Future.wait<dynamic>([
      _db.from('shift_staffing').select('weekday, need, min_full').eq('store_id', storeId),
      _db.from('shift_staffing_days').select('day, need').eq('store_id', storeId).gte('day', _day.format(from)).lt('day', _day.format(to)),
      _db.from('shift_settings').select('request_deadline').eq('store_id', storeId).maybeSingle(),
      _db.from('shift_rules').select().eq('store_id', storeId),
      _db.from('shift_pair_rules').select('id, person_a, person_b, kind').eq('store_id', storeId).order('created_at'),
      _db
          .from('shift_requests')
          .select('person_id, req_date, kind')
          .eq('store_id', storeId)
          .gte('req_date', _day.format(from))
          .lt('req_date', _day.format(to))
          .limit(5000),
    ]);
    final requests = <String, Map<int, String>>{};
    for (final e in r[5] as List) {
      requests.putIfAbsent(e['person_id'] as String, () => {})[DateTime.parse(e['req_date'] as String).day] = e['kind'] as String;
    }
    return ShiftPlanSetup(
      staffing: {
        for (final x in r[0] as List)
          (x['weekday'] as num).toInt(): StaffingNeed((x['need'] as num).toInt(), (x['min_full'] as num?)?.toInt() ?? 0)
      },
      specialDays: {for (final x in r[1] as List) DateTime.parse(x['day'] as String).day: (x['need'] as num).toInt()},
      deadline: ((r[2] as Map?)?['request_deadline'] as num?)?.toInt() ?? 20,
      rules: {for (final x in r[3] as List) x['person_id'] as String: ShiftRule.fromRow(x as Map<String, dynamic>)},
      requests: requests,
      pairRules: [for (final x in r[4] as List) PairRule.fromRow(x as Map<String, dynamic>)],
    );
  }

  @override
  Future<void> addShiftPairRule(String storeId, String a, String b, String kind) =>
      _db.from('shift_pair_rules').insert({'store_id': storeId, 'person_a': a, 'person_b': b, 'kind': kind});

  @override
  Future<void> deleteShiftPairRule(String id) => _db.from('shift_pair_rules').delete().eq('id', id);

  @override
  Future<void> claimShiftPerson(String personId) => _db.rpc('shift_claim_person', params: {'p_person': personId});

  @override
  Future<void> clearShiftPersonUser(String personId) async {
    final rows = await _db.from('shift_people').update({'user_id': null}).eq('id', personId).select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限修改班表人員,');
  }

  @override
  Future<void> setShiftRequest(String storeId, String personId, DateTime date, String? kind) async {
    if (kind == null) {
      final rows = await _db.from('shift_requests').delete().eq('person_id', personId).eq('req_date', _day.format(date)).select('person_id');
      if (rows.isEmpty) throw Exception('message: 已經過了填寫截止日，請找老闆或店長改,');
    } else {
      await _db.from('shift_requests').upsert(
          {'store_id': storeId, 'person_id': personId, 'req_date': _day.format(date), 'kind': kind},
          onConflict: 'person_id,req_date');
    }
  }

  @override
  Future<void> saveShiftRule(String storeId, ShiftRule r) async {
    if (r.isEmpty) {
      await _db.from('shift_rules').delete().eq('person_id', r.personId);
    } else {
      await _db.from('shift_rules').upsert(r.toRow(storeId), onConflict: 'person_id');
    }
  }

  @override
  Future<void> saveShiftStaffing(String storeId, Map<int, StaffingNeed> staffing) => _db.from('shift_staffing').upsert([
        for (final e in staffing.entries) {'store_id': storeId, 'weekday': e.key, 'need': e.value.need, 'min_full': e.value.minFull}
      ], onConflict: 'store_id,weekday');

  @override
  Future<void> setShiftStaffingDay(String storeId, DateTime day, int? need) async {
    if (need == null) {
      await _db.from('shift_staffing_days').delete().eq('store_id', storeId).eq('day', _day.format(day));
    } else {
      await _db.from('shift_staffing_days').upsert({'store_id': storeId, 'day': _day.format(day), 'need': need}, onConflict: 'store_id,day');
    }
  }

  @override
  Future<void> saveShiftDeadline(String storeId, int day) =>
      _db.from('shift_settings').upsert({'store_id': storeId, 'request_deadline': day}, onConflict: 'store_id');

  @override
  Future<int> applyShiftPlan(String storeId, DateTime month, Map<String, Map<int, String>> plan) async {
    final n = await _db.rpc('apply_shift_plan', params: {
      'p_store': storeId,
      'p_month': _day.format(DateTime(month.year, month.month, 1)),
      'p_plan': {
        for (final e in plan.entries) e.key: {for (final d in e.value.entries) '${d.key}': d.value}
      },
    });
    return (n as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> saveShiftMarkOption(String storeId, ShiftMarkOption o) async {
    final v = {'kind': o.kind, 'mark': o.mark, 'time_range': o.timeRange, 'sort_order': o.sortOrder};
    if (o.id.isEmpty) {
      await _db.from('shift_mark_options').insert({...v, 'store_id': storeId});
    } else {
      final rows = await _db.from('shift_mark_options').update(v).eq('id', o.id).select('id');
      if (rows.isEmpty) throw Exception('message: 沒有權限修改班別／時段,');
    }
  }

  @override
  Future<void> deleteShiftMarkOption(String id) async {
    final rows = await _db.from('shift_mark_options').delete().eq('id', id).select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限刪除班別／時段,');
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
        .select('id, purchase_date, category_code, memo, amount, paid_by, reconciled, source, superseded_by, excel_covered_at, created_by, vendor_name, no_receipt, photo_path, '
            'suppliers!purchases_supplier_same_store(name)')
        .eq('store_id', storeId)
        .order('purchase_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return _withPhotos(rows.map(Purchase.fromRow).toList());
  }

  @override
  Future<List<Purchase>> monthPurchases(String storeId, DateTime month) async {
    final rows = await _db
        .from('purchases')
        .select('id, purchase_date, category_code, memo, amount, paid_by, reconciled, source, superseded_by, excel_covered_at, created_by, vendor_name, no_receipt, photo_path, '
            'suppliers!purchases_supplier_same_store(name)')
        .eq('store_id', storeId)
        .eq('period_month', _day.format(DateTime(month.year, month.month, 1)))
        .order('purchase_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(2000);
    return _withPhotos(rows.map(Purchase.fromRow).toList());
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

  /// 日報表匯入的那筆沒有照片時，帶上被它取代的 App 暫記的照片（同一筆進貨）
  static List<Purchase> _withPhotos(List<Purchase> list) {
    final byImport = <String, String>{};
    for (final p in list) {
      if (p.supersededBy != null && p.photoPath != null) byImport.putIfAbsent(p.supersededBy!, () => p.photoPath!);
    }
    for (final p in list) {
      if (p.photoPath == null && byImport.containsKey(p.id)) p.photoPath = byImport[p.id];
    }
    return list;
  }

  // ---------------- 盤點 ----------------
  @override
  Future<List<Product>> products(String storeId) async {
    // 只列出員工有權限的欄位（cost_price 員工不可讀，不能用 select *）
    final rows = await _db
        .from('products')
        .select('id, name, category, unit, par_level')
        .eq('store_id', storeId)
        .eq('active', true)
        .order('category')
        .order('name');
    return rows
        .map((r) => Product(r['id'] as String, r['name'] as String, r['category'] as String, r['unit'] as String,
            parLevel: r['par_level'] == null ? null : toDouble(r['par_level'])))
        .toList();
  }

  @override
  Future<Map<String, StockLevel>> latestStock(String storeId) async {
    // 可以只盤一部分，所以要一路往前找，直到每個使用中的品項都找到最近一次（Codex 審查）
    final active = (await _db.from('products').select('id').eq('store_id', storeId).eq('active', true))
        .map((r) => r['id'] as String)
        .toSet();
    final out = <String, StockLevel>{};
    const page = 60;
    for (var from = 0; from < page * 50; from += page) {
      final rows = await _db
          .from('stock_counts')
          .select('biz_date, counted_at, status, stock_count_lines(product_id, qty)')
          .eq('store_id', storeId)
          .inFilter('status', ['submitted', 'approved'])
          .order('counted_at', ascending: false)
          .order('id')
          .range(from, from + page - 1);
      for (final c in rows) {
        final d = DateTime.parse(c['biz_date'] as String);
        for (final l in (c['stock_count_lines'] as List? ?? const [])) {
          out.putIfAbsent(l['product_id'] as String, () => StockLevel(toDouble(l['qty']), d));
        }
      }
      if (rows.length < page || active.every(out.containsKey)) break;
    }
    return out;
  }

  @override
  Future<void> saveProduct(String storeId, Product p) async {
    final row = {'name': p.name.trim(), 'category': p.category, 'unit': p.unit.trim(), 'par_level': p.parLevel};
    if (p.id.isEmpty) {
      // 同名的品項以前停用過（清單上看不到）：直接恢復那一個，不另外新增（老闆 2026-10-25：新增時一直說已有相同名稱）
      final old = await _db
          .from('products')
          .select('id')
          .eq('store_id', storeId)
          .eq('name', row['name'] as String)
          .eq('active', false)
          .maybeSingle();
      if (old != null) {
        final r = await _db.from('products').update({...row, 'active': true}).eq('id', old['id'] as String).select('id');
        if (r.isEmpty) throw Exception('message: 只有老闆、店長、正職或兼職可以修改品項,');
        return;
      }
      await _db.from('products').insert({...row, 'store_id': storeId});
    } else {
      final r = await _db.from('products').update(row).eq('id', p.id).select('id');
      if (r.isEmpty) throw Exception('message: 只有老闆、店長、正職或兼職可以修改品項,');
    }
  }

  @override
  Future<void> deactivateProduct(String productId) async {
    final r = await _db.from('products').update({'active': false}).eq('id', productId).select('id');
    if (r.isEmpty) throw Exception('message: 只有老闆、店長、正職或兼職可以停用品項,');
  }

  @override
  Future<List<StockCount>> stockCounts(String storeId) async {
    final rows = await _db
        .from('stock_counts')
        .select('id, biz_date, counted_by, status, note, stock_count_lines(count)')
        .eq('store_id', storeId)
        // 盤點紀錄只列算數的（草稿、退回、作廢不佔 30 筆的名額；Codex 審查）
        .inFilter('status', ['submitted', 'approved'])
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
        .select('id, slot_date, slot_time, party_size, guest_name, phone, email, note, status, source, email_error, created_at, '
            'requested_party, party_request_status, lang, table_ids, seated_at, cleared_at, walk_in, hidden_at')
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
      {required DateTime date, required String time, required int party, required String name, required String phone, String? email, String? note, List<String> tableIds = const []}) async {
    await _db.from('reservations').insert({
      'store_id': storeId,
      'slot_date': _day.format(date),
      'slot_time': time,
      'party_size': party,
      'guest_name': name,
      'phone': phone.isEmpty ? null : phone, // 0057 可以不留電話
      if (email != null && email.isNotEmpty) 'email': email,
      if (note != null && note.isNotEmpty) 'note': note,
      if (tableIds.isNotEmpty) 'table_ids': tableIds, // 電話訂位選位置（老闆 2026-10-22）
      'source': 'app',
    });
  }

  @override
  Future<void> updateReservation(String id, Map<String, dynamic> values) async {
    final rows = await _db.from('reservations').update(values).eq('id', id).select('id');
    if (rows.isEmpty) throw Exception('message: 沒有權限修改這筆訂位,');
  }

  // ---------------- 0061 時間軸：桌位、現場客 ----------------
  @override
  Future<List<ReservationTable>> reservationTables(String storeId) async {
    final rows = await _db.from('reservation_tables').select().eq('store_id', storeId)
        // supabase 的 order() 預設由大到小，要明確指定由小到大（A1 在最上面）
        .order('sort', ascending: true).order('name', ascending: true);
    return rows.map(ReservationTable.fromRow).toList();
  }

  @override
  Future<void> saveReservationTable(String storeId, ReservationTable t) async {
    final v = {'name': t.name.trim(), 'seats': t.seats, 'combinable': t.combinable, 'sort': t.sort, 'active': t.active};
    if (t.id.isEmpty) {
      await _db.from('reservation_tables').insert({'store_id': storeId, ...v});
    } else {
      final rows = await _db.from('reservation_tables').update(v).eq('id', t.id).select('id');
      if (rows.isEmpty) throw Exception('message: 沒有權限修改桌位,');
    }
  }

  @override
  Future<void> addWalkIn(String storeId,
      {required DateTime date, required String time, required int party, required String name, required List<String> tableIds}) async {
    await _db.from('reservations').insert({
      'store_id': storeId,
      'slot_date': _day.format(date),
      'slot_time': time,
      'party_size': party,
      'guest_name': name,
      'phone': null,
      'source': 'app',
      'status': 'arrived',
      'walk_in': true,
      'table_ids': tableIds,
    });
  }

  // ---------------- 0052 特殊日期、熟客 ----------------
  @override
  Future<List<ReservationSpecialDay>> specialDays(String storeId, DateTime from, DateTime to) async {
    final rows = await _db
        .from('reservation_special_days')
        .select()
        .eq('store_id', storeId)
        .gte('day', _day.format(from))
        .lte('day', _day.format(to))
        .order('day');
    return rows.map(ReservationSpecialDay.fromRow).toList();
  }

  @override
  Future<void> saveSpecialDay(String storeId, ReservationSpecialDay d) async {
    await _db.from('reservation_special_days').upsert({
      'store_id': storeId,
      'day': _day.format(d.day),
      'closed': d.closed,
      'max_groups': d.maxGroups,
      'max_guests': d.maxGuests,
      'max_large': d.maxLarge,
      'note': d.note,
    }, onConflict: 'store_id,day');
  }

  @override
  Future<void> deleteSpecialDay(String storeId, DateTime day) async {
    final r = await _db.from('reservation_special_days').delete().eq('store_id', storeId).eq('day', _day.format(day)).select('day');
    if (r.isEmpty) throw Exception('message: 只有老闆可以刪除特殊日期,');
  }

  @override
  Future<Map<String, GuestStats>> guestStats(String storeId, Set<String> phoneDigits) async {
    final list = phoneDigits.where((p) => p.length >= 8).toList();
    if (list.isEmpty) return {};
    final r = await Future.wait<dynamic>([
      _db.from('reservations').select('phone_digits, status, slot_date').eq('store_id', storeId).inFilter('phone_digits', list),
      _db.from('reservation_guests').select().eq('store_id', storeId).inFilter('phone_digits', list),
    ]);
    final profiles = {for (final g in (r[1] as List)) (g['phone_digits'] as String): GuestProfile.fromRow(g as Map<String, dynamic>)};
    final out = <String, GuestStats>{};
    for (final p in list) {
      final reset = profiles[p]?.noshowResetAt;
      final resetDay = reset == null ? null : DateTime(reset.year, reset.month, reset.day);
      var visits = 0, noShows = 0;
      for (final x in (r[0] as List).where((x) => x['phone_digits'] == p)) {
        if (x['status'] == 'arrived') visits++;
        if (x['status'] == 'no_show') {
          final d = DateTime.parse(x['slot_date'] as String);
          if (resetDay == null || d.isAfter(resetDay)) noShows++;
        }
      }
      out[p] = GuestStats(visits, noShows, profiles[p]);
    }
    return out;
  }

  @override
  Future<void> decidePartyRequest(String id, bool approve, int expectedParty) async {
    await _db.rpc('decide_party_request', params: {'p_id': id, 'p_approve': approve, 'p_expected': expectedParty});
  }

  @override
  Future<void> saveGuestProfile(String storeId, GuestProfile g, {bool resetNoshow = false}) async {
    await _db.from('reservation_guests').upsert({
      'store_id': storeId,
      'phone_digits': g.phoneDigits,
      'tags': g.tags,
      'note': (g.note ?? '').trim().isEmpty ? null : g.note!.trim(),
      if (resetNoshow) 'noshow_reset_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'store_id,phone_digits');
  }

  // ---------------- 功能許願（0069） ----------------
  @override
  Future<List<ChangeRequest>> changeRequests(String storeId) async {
    final rows = await _db
        .from('change_requests')
        .select('id, store_id, title, requested_by, requester_name, status, preview_url, pr_number, last_error, run_count, '
            'created_at, updated_at, run_started_at')
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .limit(50);
    return _rows(rows).map(ChangeRequest.fromRow).toList();
  }

  @override
  Future<List<ChangeMessage>> changeMessages(String requestId) async {
    final rows = await _db
        .from('change_request_messages')
        .select('id, kind, author_name, body, created_at')
        .eq('request_id', requestId)
        .order('id');
    // 附的照片（0071）；資料庫還沒更新時就當沒有照片
    final photos = <int, List<String>>{};
    try {
      final ps = await _db
          .from('change_request_photos')
          .select('id, message_id')
          .eq('request_id', requestId)
          .order('created_at');
      for (final p in _rows(ps)) {
        (photos[(p['message_id'] as num).toInt()] ??= []).add(p['id'] as String);
      }
    } catch (_) {}
    return _rows(rows)
        .map((r) => ChangeMessage.fromRow(r, photoIds: photos[(r['id'] as num).toInt()] ?? const []))
        .toList();
  }

  @override
  Future<Uint8List> changePhoto(String photoId) async {
    final b64 = await _db.rpc('cr_photo', params: {'p_photo': photoId}) as String;
    return base64Decode(b64);
  }

  @override
  Future<ChangeQuota> changeQuota(String storeId) async {
    final r = await _db.rpc('cr_quota', params: {'p_store': storeId});
    final m = _row(r is List ? (r.isEmpty ? null : r.first) : r) ?? const {};
    return ChangeQuota((m['used'] as num?)?.toInt() ?? 0, (m['monthly_limit'] as num?)?.toInt());
  }

  @override
  Future<String> createChangeRequest(String storeId, String body, {List<String> photos = const []}) async =>
      await _db.rpc('cr_create', params: {
        'p_store': storeId,
        'p_body': body,
        if (photos.isNotEmpty) 'p_photos': [for (final p in photos) _b64(p)],
      }) as String;

  /// data URL → 純 base64
  static String _b64(String dataUrl) => dataUrl.contains(',') ? dataUrl.substring(dataUrl.indexOf(',') + 1) : dataUrl;

  @override
  Future<void> followupChangeRequest(String requestId, String body, {List<String> photos = const []}) =>
      _db.rpc('cr_followup', params: {
        'p_id': requestId,
        'p_body': body,
        if (photos.isNotEmpty) 'p_photos': [for (final p in photos) _b64(p)],
      });

  @override
  Future<void> submitChangeRequest(String requestId) => _db.rpc('cr_submit', params: {'p_id': requestId});

  @override
  Future<void> approveChangeRequest(String requestId) => _db.rpc('cr_approve', params: {'p_id': requestId});

  @override
  Future<void> returnChangeRequest(String requestId, String reason) =>
      _db.rpc('cr_return', params: {'p_id': requestId, 'p_reason': reason});

  @override
  Future<void> cancelChangeRequest(String requestId) => _db.rpc('cr_cancel', params: {'p_id': requestId});

  @override
  Future<void> kickChangeRequests() async {
    try {
      await _db.functions.invoke('change-request', body: {'op': 'kick'});
    } catch (_) {
      // 派工失敗不影響畫面；下次打開許願頁會再試
    }
  }
}
