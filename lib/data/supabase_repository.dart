import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide toDouble;

import '../config.dart';
import 'models.dart';
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
  Future<void> signOut() => _db.auth.signOut();
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
    final list = rows.map(Membership.fromRow).toList();
    list.sort((a, b) => a.storeName.compareTo(b.storeName));
    return list;
  }

  // ---------------- 營運總覽 ----------------
  @override
  Future<MonthlySummary> monthlySummary(String storeId, DateTime month) async {
    final m = _day.format(DateTime(month.year, month.month, 1));
    final rev = await _db.from('v_monthly_revenue').select().eq('store_id', storeId).eq('period_month', m).maybeSingle();
    final cost = await _db.from('v_monthly_cost').select().eq('store_id', storeId).eq('period_month', m).maybeSingle();
    return summaryFromRows(rev, cost, month);
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
    return r == null ? null : toDouble(r['closing_balance']);
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
    double? pick(String c) {
      final r = rows.where((x) => x['category'] == c).toList();
      return r.isEmpty ? null : toDouble(r.first['amount']);
    }

    return FixedCosts(rent: pick('rent'), payroll: pick('payroll'));
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

  // ---------------- 進貨 ----------------
  @override
  Future<DateTime> businessDate(String storeId) async {
    final r = await _db.rpc('business_date', params: {'p_store': storeId});
    return toDate(r) ?? DateTime.now();
  }

  @override
  Future<List<CostCategory>> costCategories() async {
    final rows = await _db.from('cost_categories').select('code, name, store_name').order('sort_order');
    final list = rows.map((r) => CostCategory(r['code'] as String, r['name'] as String, r['store_name'] as String?)).toList();
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
          .select('id, body, photo_path, author_id, author_name, created_at, resolved_at, resolved_name, handover_reads(user_id, user_name)')
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
  Future<Map<String, List<String>>> vendorHints(String storeId) async {
    final now = DateTime.now();
    final rows = await _db
        .from('purchases')
        .select('category_code, memo, vendor_name, suppliers!purchases_supplier_same_store(name)')
        .eq('store_id', storeId)
        .gte('period_month', _day.format(DateTime(now.year, now.month - 6, 1)))
        .limit(5000);
    return vendorHintsFromRows(rows);
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
        .select('id, purchase_date, category_code, memo, amount, paid_by, reconciled, source, superseded_by, excel_covered_at, created_by, vendor_name, '
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
        .select('id, purchase_date, category_code, memo, amount, paid_by, reconciled, source, superseded_by, excel_covered_at, created_by, vendor_name, '
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
    return rows.map(VendorSlip.fromRow).toList();
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
    });
    // 送貨單照片 → 每小時的同步辨識成銷貨單草稿（0034）。進貨已存好，這步失敗不影響進貨
    if (photoPath != null && p.amount > 0 && p.slipDraft) {
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
}
