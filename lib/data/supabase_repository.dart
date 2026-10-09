import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide toDouble;

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
    final rows = await _db.from('cost_categories').select('code, name').order('sort_order');
    return rows.map((r) => CostCategory(r['code'] as String, r['name'] as String)).toList();
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
        .select('id, purchase_date, category_code, memo, amount, paid_by, reconciled, source, '
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
        .select('id, purchase_date, category_code, memo, amount, paid_by, reconciled, source, '
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
    final to = DateTime(month.year, month.month + 1, 1);
    final rows = await _db
        .from('vendor_slips')
        .select('id, vendor, slip_no, slip_date, total, note, '
            'vendor_slip_lines(line_no, item_code, item_name, qty, unit, unit_price, amount)')
        .eq('store_id', storeId)
        .gte('slip_date', _day.format(from))
        .lt('slip_date', _day.format(to))
        .order('slip_date')
        .order('slip_no')
        .limit(2000);
    return rows.map(VendorSlip.fromRow).toList();
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
    await _db.from('purchases').insert({
      'store_id': p.storeId,
      'purchase_date': _day.format(p.purchaseDate),
      'category_code': p.categoryCode,
      'supplier_id': p.supplierId,
      'memo': (p.memo?.trim().isEmpty ?? true) ? null : p.memo!.trim(),
      'amount': p.amount,
      'paid_by': p.paidBy,
      'client_request_id': p.clientRequestId,
    });
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
