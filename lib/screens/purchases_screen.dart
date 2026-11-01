import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/purchase_items_math.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../services/slip_scan.dart';
import '../widgets/common.dart';
import '../widgets/photo_thumb.dart';
import 'purchase_items_editor.dart';
import 'vendor_contacts_screen.dart';

/// 進貨管理：本月進貨分成「月結廠商」與「零用金支出」兩大類，
/// 點大類展開各進貨類別的小計，點類別看該類別依廠商分組的明細（老闆／店長可在明細核銷）
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late Future<(List<Purchase>, Map<String, String>, DateTime?)> _future;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final _open = <String>{}; // 已展開的大類
  bool _started = false;
  /// 今天的營業日（早上 6 點前算前一天）；用來標出「當日新增」（老闆 2026-10-12）
  DateTime? _today;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  /// 進貨以 Dropbox 日報表為準的店：只能看，不能新增或核銷（核銷也以 Excel 的「核銷」欄為準）
  bool get _synced => AppConfig.excelSyncedStores.contains(widget.membership.storeName);

  /// 顯示時合併的類別（0047）：例 咖啡吧-餐食、布布拉麵-餐食 → 餐食；只影響進貨頁分組，不改資料
  Map<String, String> _displayAs = {};

  Future<(List<Purchase>, Map<String, String>, DateTime?)> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final r = await Future.wait([repo.monthPurchases(id, _month), repo.costCategories()]);
    try {
      _today = await repo.businessDate(id);
    } catch (_) {
      _today = null; // 取不到就不顯示當日新增，不影響列表
    }
    final cats = {for (final c in r[1] as List<CostCategory>) c.code: c.name};
    _displayAs = {
      for (final c in r[1] as List<CostCategory>)
        if (c.displayAs != null) c.code: c.displayAs!
    };
    DateTime? last;
    if (_synced && widget.membership.canSeeRevenue) last = await repo.lastExcelSync(id);
    return (r[0] as List<Purchase>, cats, last);
  }

  void _reload() => setState(() => _future = _load());

  void _shiftMonth(int d) {
    _month = DateTime(_month.year, _month.month + d);
    _reload();
  }

  Future<void> _openCategory(String title, List<Purchase> items, Map<String, String> cats,
      {bool Function(Purchase)? reloadFilter}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CategoryPurchasesScreen(
          title: title,
          month: _month,
          items: items,
          categoryNames: cats,
          today: _today,
          canReconcile: widget.membership.isManager && !_synced,
          membership: widget.membership,
          // 月結廠商的類別：先顯示廠商區塊（老闆 2026-10-29），點區塊才看每筆
          vendorBlocks: reloadFilter != null,
          reloadFilter: reloadFilter,
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
                onPressed: () async {
                  final saved = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => PurchaseFormScreen(membership: widget.membership)),
                  );
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.add),
                label: const Text('新增進貨'),
              ),
        body: FutureBuilder<(List<Purchase>, Map<String, String>, DateTime?)>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (all, cats, last) = snap.data!;
            // 已被 Excel 同一筆取代、或日報表已涵蓋（以日報表為準）的 App 暫記不計入
            final list = all.where((p) => p.counted).toList();
            final replaced = all.where((p) => p.superseded).length;
            final covered = all.where((p) => !p.superseded && p.excelCovered).toList();
            final vendor = list.where((p) => p.paidBy != 'petty_cash').toList();
            final petty = list.where((p) => p.paidBy == 'petty_cash').toList();
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                Row(children: [
                  IconButton(tooltip: '上個月', onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Text(DateFormat('yyyy 年 M 月', 'zh_TW').format(_month),
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: AppType.title)),
                  ),
                  IconButton(tooltip: '下個月', onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
                ]),
                // 廠商資料（0076，老闆 2026-10-29）：只有老闆、店長看得到
                if (widget.membership.isManager)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => VendorContactsScreen(membership: widget.membership)),
                      ),
                      icon: const Icon(Icons.contacts_outlined, size: 18),
                      label: const Text('廠商資料'),
                    ),
                  ),
                const SizedBox(height: 4),
                if (_synced) ...[
                  // 進貨以日報表為準（老闆 2026-10-13 晚上，0049）；說明收成一行＋ⓘ（老闆 2026-10-29）
                  InfoLine(
                    text: '每小時從日報表帶入・最後 ${last == null ? '尚無紀錄' : DateFormat('M/d HH:mm').format(last)}',
                    detail: '來自日報表的進貨不能在 App 修改。按「新增進貨」手動輸入的會先計入；'
                        '之後日報表有同一筆，就改以日報表為準、不重複計算。自己新增的可以點進去修改或刪除。',
                  ),
                  const SizedBox(height: 4),
                ],
                _group('vendor', '月結廠商', '月結付款', Icons.storefront_outlined, vendor, cats),
                const SizedBox(height: 12),
                _group('petty', '零用金支出', '零用金付款', Icons.payments_outlined, petty, cats),
                const SizedBox(height: 12),
                Text('本月進貨合計 ${ntd(list.fold<double>(0, (t, p) => t + p.amount))}，共 ${list.length} 筆',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                if (_synced && (replaced > 0 || covered.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (replaced > 0) '$replaced 筆 App 進貨已由日報表取代',
                        if (covered.isNotEmpty) '${covered.length} 筆 10/12 以前的 App 進貨以日報表為準、不計入（點下方查看）',
                      ].join('；'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.warn, fontSize: AppType.small),
                    ),
                  ),
                if (covered.isNotEmpty)
                  Center(
                    child: TextButton(
                      onPressed: () => _openCategory('以日報表為準（不計入）的暫記', covered, cats),
                      child: const Text('查看以日報表為準的暫記'),
                    ),
                  ),
              ]),
            );
          },
        ),
      );

  /// 這些進貨裡，進貨日期是今天（營業日）的合計
  double _todayAmount(List<Purchase> items) =>
      _today == null ? 0 : items.where((p) => isSameDay(p.purchaseDate, _today!)).fold(0.0, (t, p) => t + p.amount);

  /// 一個大類：標題列（總金額）＋展開後各進貨類別小計
  Widget _group(String key, String title, String sub, IconData icon, List<Purchase> items, Map<String, String> cats) {
    final total = items.fold<double>(0, (t, p) => t + p.amount);
    final byCat = <String, List<Purchase>>{};
    for (final p in items) {
      byCat.putIfAbsent(_displayAs[p.categoryCode] ?? p.categoryCode, () => []).add(p);
    }
    // 依類別在設定中的順序排列
    final order = cats.keys.toList();
    final codes = byCat.keys.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a), ib = order.indexOf(b);
        return (ia < 0 ? 999 : ia).compareTo(ib < 0 ? 999 : ib);
      });
    final open = _open.contains(key);
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => setState(() => open ? _open.remove(key) : _open.add(key)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$sub・${items.length} 筆', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                ]),
              ),
              Text(ntd(total), style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: AppColors.muted),
            ]),
          ),
        ),
        if (open) ...[
          const Divider(height: 1),
          if (codes.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('本月沒有資料', style: TextStyle(color: AppColors.muted)),
            ),
          for (final c in codes)
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              title: Text(cats[c] ?? c),
              subtitle: Text('${byCat[c]!.length} 筆', style: const TextStyle(fontSize: AppType.small)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                // 當日新增金額（例：10/12 新增 $886）
                if (_todayAmount(byCat[c]!) != 0) ...[
                  Text('${DateFormat('M/d').format(_today!)} 新增${ntd(_todayAmount(byCat[c]!))}',
                      style: TextStyle(color: AppColors.warn, fontSize: AppType.small, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                ],
                Text(ntd(byCat[c]!.fold<double>(0, (t, p) => t + p.amount)),
                    style: const TextStyle(fontSize: AppType.body, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, color: AppColors.muted),
              ]),
              onTap: () => _openCategory('$title・${cats[c] ?? c}', byCat[c]!, cats,
                  reloadFilter: key == 'vendor'
                      ? (p) => p.counted && p.paidBy != 'petty_cash' && (_displayAs[p.categoryCode] ?? p.categoryCode) == c
                      : null),
            ),
          const SizedBox(height: 4),
        ],
      ]),
    );
  }
}

/// 某大類中某進貨類別的明細：依廠商分組，每組顯示小計；老闆／店長可核銷
class _CategoryPurchasesScreen extends StatefulWidget {
  const _CategoryPurchasesScreen({
    required this.title,
    required this.month,
    required this.items,
    required this.categoryNames,
    required this.canReconcile,
    required this.membership,
    this.today,
    this.vendorBlocks = false,
    this.reloadFilter,
  });
  final Membership membership;
  /// 先顯示廠商區塊（一行兩格：廠商名稱＋總金額），點區塊才看那家的每一筆（月結廠商用，老闆 2026-10-29）
  final bool vendorBlocks;
  /// 從廠商明細回來時重新讀這個月的進貨，用這個條件挑出這個類別的（核銷、刪除後金額才會對）
  final bool Function(Purchase)? reloadFilter;
  final DateTime? today; // 今天的營業日：當日新增的品項用橘色
  final String title;
  final DateTime month;
  final List<Purchase> items;
  final Map<String, String> categoryNames;
  final bool canReconcile;
  @override
  State<_CategoryPurchasesScreen> createState() => _CategoryPurchasesScreenState();
}

class _CategoryPurchasesScreenState extends State<_CategoryPurchasesScreen> {
  late List<Purchase> _items = List.of(widget.items);

  Future<void> _openVendor(String vendor) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CategoryPurchasesScreen(
          title: '${widget.title}・$vendor',
          month: widget.month,
          items: _items.where((p) => vendorGroupName(p) == vendor).toList(),
          categoryNames: widget.categoryNames,
          canReconcile: widget.canReconcile,
          membership: widget.membership,
          today: widget.today,
        ),
      ),
    );
    // 回來時重讀：在明細裡核銷、刪除、修改過，區塊的金額才會對
    final f = widget.reloadFilter;
    if (f == null || !mounted) return;
    try {
      final all = await AppScope.of(context).repo.monthPurchases(widget.membership.storeId, widget.month);
      if (mounted) setState(() => _items = all.where(f).toList());
    } catch (_) {}
  }

  /// 廠商區塊：一行兩格，金額大的在前面
  Widget _blocks(double total) {
    final groups = <String, List<Purchase>>{};
    for (final p in _items) {
      groups.putIfAbsent(vendorGroupName(p), () => []).add(p);
    }
    double sum(List<Purchase> l) => l.fold<double>(0, (t, p) => t + p.amount);
    final names = groups.keys.toList()..sort((a, b) => sum(groups[b]!).compareTo(sum(groups[a]!)));
    final today = widget.today;
    Widget block(String n) {
      final l = groups[n]!;
      final todayAmt = today == null ? 0.0 : l.where((p) => isSameDay(p.purchaseDate, today)).fold(0.0, (t, p) => t + p.amount);
      final open = l.where((p) => !p.reconciled).length;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => _openVendor(n),
          child: SectionCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppType.body, fontWeight: AppFont.heading, height: 1.3)),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(ntd(sum(l)),
                    style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.figure, fontFeatures: tabular)),
              ),
              const SizedBox(height: 4),
              Text(
                '${l.length} 筆${open > 0 ? '・未核銷 $open' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.muted, fontSize: AppType.caption),
              ),
              if (todayAmt != 0)
                Text('${DateFormat('M/d').format(today!)} 新增${ntd(todayAmt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.warn, fontSize: AppType.caption, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < names.length; i += 2) ...[
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: block(names[i])),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < names.length ? block(names[i + 1]) : const SizedBox()),
          ]),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Future<void> _toggle(Purchase p) async {
    try {
      await AppScope.of(context).repo.setReconciled(p.id, !p.reconciled);
      setState(() {
        final i = _items.indexWhere((x) => x.id == p.id);
        _items[i] = Purchase(
          id: p.id, purchaseDate: p.purchaseDate, categoryCode: p.categoryCode, supplierName: p.supplierName,
          memo: p.memo, amount: p.amount, paidBy: p.paidBy, reconciled: !p.reconciled, source: p.source,
          supersededBy: p.supersededBy, excelCovered: p.excelCovered, createdBy: p.createdBy,
          noReceipt: p.noReceipt, photoPath: p.photoPath, // 核銷後照片縮圖要留著（Codex 審查）
        );
      });
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  /// 點一筆：日報表的 → 說明要改日報表；App 暫記 → 修改／刪除
  Future<void> _actions(Purchase p) async {
    final repo = AppScope.of(context).repo;
    final mine = p.createdBy != null && p.createdBy == repo.currentUserId;
    if (p.fromExcel) {
      showMessage(context, '這筆是 10/12 以前從日報表匯入的進貨，不能在 App 修改或刪除');
      return;
    }
    if (!widget.membership.isManager && !mine) {
      showMessage(context, '只有建立這筆的人或老闆、店長可以修改、刪除');
      return;
    }
    if (p.reconciled) {
      showMessage(context, '已核銷的進貨不能修改或刪除，請先由老闆或店長取消核銷');
      return;
    }
    final locked = !p.counted; // 已被取代或以日報表為準：只能刪
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('${p.supplierName ?? p.memo ?? '進貨'}・${ntd(p.amount)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(locked ? '這筆已以日報表為準（不計入），只能刪除' : 'App 新增的進貨：可以修改或刪除'),
          ),
          if (!locked)
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('修改'), onTap: () => Navigator.pop(c, 'edit')),
          ListTile(
            leading: Icon(Icons.delete_outline, color: AppColors.bad),
            title: Text('刪除', style: TextStyle(color: AppColors.bad)),
            onTap: () => Navigator.pop(c, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || act == null) return;
    if (act == 'edit') {
      final saved = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => PurchaseFormScreen(membership: widget.membership, editing: p)));
      if (saved == true && mounted) Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('刪除這筆進貨？'),
        content: Text('${DateFormat('M/d').format(p.purchaseDate)}　${p.supplierName ?? p.memo ?? ''}　${ntd(p.amount)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.bad),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await repo.deletePurchase(p.id);
      if (!mounted) return;
      showMessage(context, '已刪除');
      setState(() => _items.removeWhere((x) => x.id == p.id));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 有廠商用廠商名稱分組；沒有廠商的（零用金常見）用摘要分組
    final groups = <String, List<Purchase>>{};
    for (final p in _items) {
      groups.putIfAbsent(p.supplierName ?? p.memo ?? '（無摘要）', () => []).add(p);
    }
    // 最新的在最上面（老闆 2026-10-14）：每組內依日期新→舊；組與組之間依該組最新一筆的日期排
    for (final g in groups.values) {
      g.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    }
    final names = groups.keys.toList()
      ..sort((a, b) => groups[b]!.first.purchaseDate.compareTo(groups[a]!.first.purchaseDate));
    final total = _items.fold<double>(0, (t, p) => t + p.amount);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: AppType.title))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        SectionCard(
          child: Row(children: [
            Text(DateFormat('M 月合計', 'zh_TW').format(widget.month), style: TextStyle(color: AppColors.muted)),
            const Spacer(),
            Text(ntd(total), style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w800)),
          ]),
        ),
        if (widget.vendorBlocks) ...[
          const SizedBox(height: 16),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text('本月沒有資料', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            )
          else
            _blocks(total),
        ] else
        for (final n in names) ...[
          const SizedBox(height: 16),
          if (names.length > 1) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              Expanded(child: Text(n, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${groups[n]!.length} 筆・${ntd(groups[n]!.fold<double>(0, (t, p) => t + p.amount))}',
                  style: TextStyle(color: AppColors.muted)),
            ]),
          ),
          const SizedBox(height: 8),
          for (final p in groups[n]!) ...[
            _PurchaseTile(
              p: p,
              isToday: widget.today != null && isSameDay(p.purchaseDate, widget.today!),
              categoryName: widget.categoryNames[p.categoryCode] ?? p.categoryCode,
              canReconcile: widget.canReconcile,
              onToggle: () => _toggle(p),
              onTap: () => _actions(p),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ]),
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile(
      {required this.p,
      required this.categoryName,
      required this.canReconcile,
      required this.onToggle,
      required this.onTap,
      this.isToday = false});
  final Purchase p;
  final bool isToday; // 當日新增：廠商／品項與金額用橘色
  final String categoryName;
  final bool canReconcile;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          // 送貨單／發票照片（老闆 2026-10-16：銷貨單照片併到進貨），點了看大圖
          if (p.photoPath != null) ...[
            PhotoThumb(key: ValueKey(p.photoPath), path: p.photoPath!, size: 44),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.supplierName ?? p.memo ?? categoryName,
                  style: TextStyle(fontWeight: FontWeight.w600, color: isToday ? AppColors.warn : null)),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('M/d').format(p.purchaseDate)}・$categoryName'
                '${p.paidBy == 'petty_cash' ? '・零用金' : ''}${p.noReceipt ? '・缺憑' : ''}${p.source == 'import' ? '・日報表' : (p.counted ? '・App（點一下可改）' : '・以日報表為準，不計入')}',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
              ),
            ]),
          ),
          Text(ntd(p.amount),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isToday ? AppColors.warn : (p.amount < 0 ? AppColors.good : null))),
          const SizedBox(width: 4),
          IconButton(
            tooltip: p.reconciled ? '已核銷' : (canReconcile ? '核銷' : '未核銷'),
            onPressed: canReconcile ? onToggle : null,
            icon: Icon(p.reconciled ? Icons.verified : Icons.radio_button_unchecked,
                color: p.reconciled ? AppColors.good : AppColors.muted),
          ),
        ]),
      ),
      );
}

/// 新增進貨（PRD 畫面 04）
final _vendorParen = RegExp(r'\s*[(（][^()（）]*[)）]\s*$');

/// 廠商的統一名稱（區塊分組、新增進貨的廠商清單共用）：去掉名稱最後的括號說明（大倉捷(退酒) → 大倉捷），
/// 再照 AppConfig.vendorGroupAlias 合併別名（德哥 → 阿德水果）。只影響畫面，資料不改。
String vendorGroupName(Purchase p) => normalizeVendorName((p.supplierName ?? '').trim().isNotEmpty ? p.supplierName! : (p.memo ?? '')) ?? '未填廠商';

String? normalizeVendorName(String raw) {
  var n = raw.trim();
  if (n.isEmpty) return null;
  final base = n.replaceFirst(_vendorParen, '').trim();
  if (base.isNotEmpty) n = base;
  return AppConfig.vendorGroupAlias[n] ?? n;
}

class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key, required this.membership, this.editing});
  final Membership membership;
  /// 修改既有的 App 暫記（null＝新增）
  final Purchase? editing;
  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

/// 隱城新增進貨：各付款方式不提供的進貨類別（老闆 2026-10-11 決定）
const _hiddenCatsByPaidBy = <String, Set<String>>{
  // 月結廠商不出現：零用金-其他雜支、現結酒商
  'vendor': {'petty_misc', 'liquor_cash'},
  // 零用金不出現：月結酒商、酒水副材料-德哥、清運／滅蟲／花藝
  'petty_cash': {'liquor_monthly', 'fruit', 'service'},
};

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _amount = TextEditingController();
  final _memo = TextEditingController();
  // 同一張表單只產生一次：網路重送時資料庫會以這個 id 擋下重複
  final _requestId = const Uuid().v4();
  DateTime? _date;
  String? _category;
  final _vendor = TextEditingController(); // 廠商名稱：自行輸入（和既有廠商同名就自動對應）
  // 月結廠商清單（老闆 2026-10-29：廠商名稱改成從清單選）：本月＋前兩個月出現過的月結廠商，依筆數多到少
  List<String> _monthlyVendors = [];
  List<String> _members = []; // 成員名字（填表人／請款人可從清單選）
  String? _photo; // 送貨單照片（JPEG data URL）
  List<Supplier> _sups = [];
  Map<String, String> _displayAs = {}; // 舊類別 → 合併後的類別（0048）
  String _paidBy = 'vendor';
  // 依付款方式隱藏的類別（只隱城套用）
  /// 某類別在某付款方式下可自動帶入的預設廠商名稱（依合併後類別比對、排除該付款方式不適用的來源類別）
  List<String> _autoSuppliers(List<Supplier> sups, String category, String paidBy) => sups
      .where((s) => (_displayAs[s.defaultCategory] ?? s.defaultCategory) == category)
      .where((s) => !_sourceHidden(s.defaultCategory, paidBy))
      .map((s) => s.name)
      .toList();

  /// 這個來源類別在某付款方式下要不要排除（合併提示、自動帶入廠商用）：
  /// 隱城依付款方式不提供的類別＋零用金不顯示提示的類別（Codex 審查）
  bool _sourceHidden(String? code, String paidBy) =>
      code != null &&
      ((widget.membership.storeName == '隱城' && (_hiddenCatsByPaidBy[paidBy]?.contains(code) ?? false)) ||
          (paidBy == 'petty_cash' && AppConfig.pettyCashHintHidden.contains(code)));

  Set<String> get _hiddenCats => widget.membership.storeName == '隱城'
      ? (_hiddenCatsByPaidBy[_paidBy] ?? const <String>{})
      : const <String>{};
  bool _isReturn = false;
  bool _noReceipt = false; // 沒有照片時一定要勾「缺憑」才能儲存（老闆 2026-10-12）
  bool _saving = false;
  // 品項明細（0087，老闆 2026-11-01：拍照辨識 → 品項 → 庫存）
  List<PurchaseItem> _items = [];
  List<Product> _products = [];
  List<CostCategory> _cats = [];
  bool _itemsLoaded = true; // 修改時：讀得到原本的明細才能改（讀不到就不動明細）
  bool _reading = false; // 正在辨識照片
  int _readSeq = 0; // 換照片時丟掉舊的辨識結果
  String? _readMsg; // 辨識結果說明（帶入了什麼、要注意什麼）
  bool _readFailed = false;
  late Future<(List<CostCategory>, List<Supplier>)> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  Future<(List<CostCategory>, List<Supplier>)> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final r = await Future.wait([repo.costCategories(), repo.suppliers(id), repo.businessDate(id)]);
    final e = widget.editing;
    if (e != null && _category == null) {
      _date = e.purchaseDate;
      _category = e.categoryCode;
      _vendor.text = e.supplierName ?? '';
      _amount.text = e.amount.abs() == e.amount.abs().roundToDouble() ? e.amount.abs().toInt().toString() : e.amount.abs().toString();
      _isReturn = e.amount < 0;
      _paidBy = e.paidBy;
      _memo.text = e.memo ?? '';
    }
    _date ??= r[2] as DateTime;
    // 顯示合併（0047／0048）：舊類別對應到新類別（例：月結酒商、德哥 → 酒水），自動帶入預設廠商用
    _displayAs = {
      for (final c in r[0] as List<CostCategory>)
        if (c.displayAs != null) c.code: c.displayAs!
    };
    // 常用廠商提示已移除（老闆 2026-10-13）；改成月結廠商可從日報表廠商名單選、填表人可從成員名單選
    try {
      _members = await repo.memberNames(id);
    } catch (_) {} // 名單讀不到不影響新增
    try {
      _monthlyVendors = await _recentMonthlyVendors(repo, id, widget.membership.storeName, r[2] as DateTime);
    } catch (_) {} // 讀不到時清單只剩「手動新增廠商」
    _sups = r[1] as List<Supplier>;
    _cats = r[0] as List<CostCategory>;
    try {
      _products = await repo.products(id);
    } catch (_) {} // 讀不到品項：明細照樣可以填，只是不能對應庫存
    if (e != null) {
      try {
        _items = withoutDiffLine(await repo.purchaseItems(e.id));
      } catch (_) {
        _itemsLoaded = false;
      }
    }
    // 填表人預設帶入自己的名字（可以改成請款人）
    if (_memo.text.isEmpty && e == null) _memo.text = widget.membership.displayName;
    return (r[0] as List<CostCategory>, r[1] as List<Supplier>);
  }

  final _vendorFocus = FocusNode();

  /// 本月＋前兩個月的月結廠商（名稱照進貨區塊的合併規則），依出現筆數多到少。
  /// 老闆 2026-10-29：只列月結廠商，零用金的店家不要列入：
  /// - 只算付款方式＝月結廠商的進貨
  /// - 日報表 8 月以前是舊格式（零用金買的東西也記在月結那幾欄，例：上白糖、咖啡豆、花），匯入的舊月份不算
  /// - 同一段時間在零用金出現得比月結多（或一樣多）的名字（例：全聯）也排除；兩邊都有、月結比較多的（例：小郭）保留
  /// - 「廠商資料」裡的月結廠商一律列入（只有老闆、店長讀得到；讀不到就略過）
  static final _newReportFormatFrom = DateTime(2026, 9, 1);
  static Future<List<String>> _recentMonthlyVendors(Repository repo, String storeId, String storeName, DateTime today) async {
    final months = [for (var i = 0; i < 3; i++) DateTime(today.year, today.month - i, 1)];
    final lists = await Future.wait(months.map((m) => repo.monthPurchases(storeId, m)));
    final counts = <String, int>{};
    final petty = <String, int>{};
    for (final p in lists.expand((l) => l)) {
      // 已被日報表取代、不計入的 App 暫記不算（2026-10-29：隱城的小郭食材、薯條、布布拉麵就是這樣混進來的）
      if (!p.counted) continue;
      final n = vendorGroupName(p);
      if (n == '未填廠商') continue;
      if (p.paidBy == 'petty_cash') {
        petty[n] = (petty[n] ?? 0) + 1;
        continue;
      }
      if (p.paidBy != 'vendor') continue;
      if (p.source == 'import' && p.purchaseDate.isBefore(_newReportFormatFrom)) continue;
      final m = AppConfig.vendorListRename[storeName]?[n] ?? n;
      counts[m] = (counts[m] ?? 0) + 1;
    }
    counts.removeWhere((v, c) {
      final inPetty = petty.entries
          .where((x) => x.key == v || x.key.startsWith('$v ') || x.key.startsWith('$v.'))
          .fold<int>(0, (a, x) => a + x.value);
      return inPetty > 0 && inPetty >= c;
    });
    final e = counts.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
    final out = [for (final x in e) x.key];
    try {
      for (final c in await repo.vendorContacts(storeId)) {
        if (c.kind != 'monthly') continue;
        final n = normalizeVendorName(c.name);
        if (n != null && !out.contains(n)) out.add(n);
      }
    } catch (_) {} // 正職、兼職讀不到廠商資料
    // 老闆指定的調整（AppConfig.vendorListRemove／vendorListAdd）
    final remove = AppConfig.vendorListRemove[storeName] ?? const <String>{};
    out.removeWhere(remove.contains);
    for (final n in AppConfig.vendorListAdd[storeName] ?? const <String>[]) {
      if (!out.contains(n)) out.add(n);
    }
    return out;
  }

  /// 月結廠商：從清單選；清單最下面「手動新增廠商」可以自己輸入（老闆 2026-10-29）
  Future<void> _pickMonthlyVendor() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _NamePicker(
        title: '選擇廠商',
        note: '本月與前兩個月的月結廠商（不含零用金店家），常用的在前面',
        names: _monthlyVendors,
        addLabel: '手動新增廠商',
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.startsWith(_NamePicker.addSentinel)) {
      final name = await _askVendorName(picked.substring(_NamePicker.addSentinel.length));
      if (name != null && mounted) setState(() => _vendor.text = name);
      return;
    }
    setState(() => _vendor.text = picked);
  }

  Future<String?> _askVendorName(String initial) async {
    final ctrl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手動新增廠商'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: '廠商名稱'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('確定')),
        ],
      ),
    );
    return (r == null || r.isEmpty) ? null : r;
  }

  Widget _monthlyVendorField() {
    final name = _vendor.text.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: _saving ? null : _pickMonthlyVendor,
      child: InputDecorator(
        isEmpty: name.isEmpty,
        decoration: InputDecoration(
          labelText: '廠商名稱',
          hintText: '點這裡選擇廠商',
          suffixIcon: name.isEmpty
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(
                  tooltip: '清除',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _vendor.clear()),
                ),
        ),
        child: Text(name, style: const TextStyle(fontSize: AppType.body)),
      ),
    );
  }

  /// 從清單選一個名字填進欄位（可搜尋）
  Future<void> _pick(String title, String note, List<String> names, TextEditingController target) async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _NamePicker(title: title, note: note, names: names),
    );
    if (picked != null && mounted) setState(() => target.text = picked);
  }

  /// 拍照／選照片 → 自動辨識送貨單（0087，老闆 2026-11-01 改：推翻 10/14「金額一律手動輸入」）：
  /// 帶入廠商、日期、金額、類別、品項，店員核對後才存。fromLibrary＝true 從手機相簿選（老闆 2026-11-01）
  Future<void> _pickPhoto({bool fromLibrary = false}) async {
    String? photo;
    try {
      photo = await pickSlipImage(fromLibrary: fromLibrary);
    } catch (e) {
      if (mounted) showMessage(context, '照片讀取失敗：$e', error: true);
      return;
    }
    if (photo == null || !mounted) return;
    setState(() => _photo = photo);
    await _readSlip(photo);
  }

  Future<void> _readSlip(String photo) async {
    final seq = ++_readSeq;
    setState(() {
      _reading = true;
      _readMsg = null;
      _readFailed = false;
    });
    try {
      final r = await AppScope.of(context).repo.readSlip(widget.membership.storeId, photo);
      if (!mounted || seq != _readSeq) return;
      await _applyReading(r);
    } catch (e) {
      if (!mounted || seq != _readSeq) return;
      setState(() {
        _readFailed = true;
        _readMsg = friendlyError(e);
      });
    } finally {
      if (mounted && seq == _readSeq) setState(() => _reading = false);
    }
  }

  /// 把辨識結果填進表單：已經填了的欄位不蓋掉（品項例外：先問）
  Future<void> _applyReading(SlipReading r) async {
    if (r.items.isNotEmpty && _items.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('換成這張照片的品項？'),
          content: Text('目前的 ${_items.length} 行品項會換成照片讀到的 ${r.items.length} 行。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('保留目前的')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('換掉')),
          ],
        ),
      );
      if (!mounted) return;
      if (ok == true) _items = [];
    }
    final filled = <String>[];
    setState(() {
      if (r.items.isNotEmpty && _items.isEmpty) {
        _items = r.items;
        filled.add('${r.items.length} 個品項');
      }
      if (r.vendor != null && _vendor.text.trim().isEmpty) {
        _vendor.text = _matchVendor(r.vendor!);
        filled.add('廠商');
      }
      if (r.total != null && r.total! > 0 && _amount.text.trim().isEmpty) {
        _amount.text = r.total! == r.total!.roundToDouble() ? r.total!.toInt().toString() : r.total!.toStringAsFixed(2);
        filled.add('金額');
      }
      final d = r.date;
      if (d != null && _date != null) {
        final today = DateTime.now();
        final ok = !d.isBefore(DateTime(today.year, today.month - 2, 1)) && !d.isAfter(DateTime(today.year, today.month + 2, 0));
        if (ok && !isSameDay(d, _date!)) {
          _date = DateTime(d.year, d.month, d.day);
          filled.add('日期');
        }
      }
      if (r.category != null && _category == null) {
        final c = _categoryFor(r.category!);
        if (c != null) {
          _category = c;
          filled.add('類別');
          final match = _autoSuppliers(_sups, c, _paidBy);
          if (_vendor.text.trim().isEmpty && match.length == 1) _vendor.text = match.first;
        }
      }
      _readFailed = r.items.isEmpty && filled.isEmpty;
      _readMsg = [
        if (filled.isNotEmpty) '已帶入${filled.join('、')}，請對照單據核對。' else if (!_readFailed) '欄位都已經填了，沒有更動。',
        if (r.notes != null && r.notes!.trim().isNotEmpty) r.notes!.trim(),
        if (_readFailed && (r.notes == null || r.notes!.trim().isEmpty)) '這張照片讀不出內容，請手動輸入或重拍。',
      ].join('\n');
    });
  }

  /// 讀到的廠商名稱對回月結廠商清單（例：「大倉捷股份有限公司」→「大倉捷」）
  String _matchVendor(String v) {
    final t = v.trim();
    for (final n in [..._monthlyVendors, ..._sups.map((s) => s.name)]) {
      if (n.isNotEmpty && (t == n || t.contains(n) || (n.length >= 2 && n.contains(t)))) return n;
    }
    return t.length > 60 ? t.substring(0, 60) : t;
  }

  /// 酒水／餐食／雜項 → 這家店、這個付款方式可以選的類別代碼
  String? _categoryFor(String label) {
    final store = widget.membership.storeName;
    final ok = _cats.where((c) =>
        (c.storeName == null || c.storeName == store) && c.selectable && !_hiddenCats.contains(c.code));
    return ok.where((c) => c.name == label).firstOrNull?.code ??
        ok.where((c) => c.name.contains(label)).firstOrNull?.code;
  }

  /// 品項的大類（新增庫存品項用）：照目前選的進貨類別
  String get _productCategory {
    final c = _cats.where((c) => c.code == _category).firstOrNull;
    final name = c == null ? '' : (_cats.where((x) => x.code == (_displayAs[c.code] ?? c.code)).firstOrNull?.name ?? c.name);
    for (final k in const ['酒水', '餐食', '雜項']) {
      if (name.contains(k)) return k;
    }
    return '雜項';
  }

  Future<Product?> _createProduct(String name, String unit) async {
    final repo = AppScope.of(context).repo;
    final existing = _products.where((p) => p.name == name).firstOrNull;
    if (existing != null) return existing;
    try {
      final p = Product('', name, _productCategory, unit);
      final id = await repo.saveProduct(widget.membership.storeId, p);
      final np = Product(id, name, p.category, unit);
      if (mounted) {
        setState(() => _products = [..._products, np]);
        showMessage(context, '已新增庫存品項「$name」（$unit・${p.category}）');
      }
      return np;
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return null;
    }
  }

  Future<void> _editItem(int? index) async {
    final isNew = index == null;
    final r = await editPurchaseItem(
      context,
      item: isNew ? PurchaseItem(name: '', qty: 1, decided: false) : _items[index],
      products: _products,
      isNew: isNew,
      isReturn: _isReturn,
      createProduct: _createProduct,
    );
    if (r == null || !mounted) return;
    setState(() {
      switch (r) {
        case ItemSaved(:final item):
          if (isNew) {
            _items = [..._items, item];
          } else {
            _items = [..._items]..[index] = item;
          }
        case ItemDeleted():
          if (!isNew) _items = [..._items]..removeAt(index);
      }
    });
  }

  Widget _itemsCard() {
    if (!_itemsLoaded) {
      return SectionCard(
        child: Text('品項明細讀取失敗，這次修改不會動到明細。',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      );
    }
    return PurchaseItemsCard(
      items: _items,
      products: _products,
      total: double.tryParse(_amount.text.replaceAll(',', '')),
      isReturn: _isReturn,
      enabled: !_saving && !_reading,
      onTap: (i) => _editItem(i),
      onAdd: () => _editItem(null),
    );
  }

  Widget _scanCard(List<Supplier> sups) => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.photo_camera_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('送貨單／發票照片（必附）', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 10),
          // 拍照／從相簿選（老闆 2026-11-01）
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _pickPhoto(),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(_photo == null ? '拍照' : '重拍'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _pickPhoto(fromLibrary: true),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(_photo == null ? '從相簿選擇' : '改選相簿照片'),
              ),
            ),
          ]),
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('拍好會自動讀出廠商、日期、金額和品項，請對照單據核對後再存。',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          ),
          if (_reading)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('正在讀取送貨單…大約 10～20 秒',
                      style: TextStyle(color: AppColors.primary, fontSize: AppType.small)),
                ),
              ]),
            )
          else if (_readMsg != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (_readFailed ? AppColors.warn : AppColors.good).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_readFailed ? Icons.error_outline : Icons.auto_awesome_outlined,
                    size: 16, color: _readFailed ? AppColors.warn : AppColors.good),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_readMsg!,
                      style: TextStyle(
                          fontSize: AppType.small, height: 1.45, color: _readFailed ? AppColors.warn : AppColors.text)),
                ),
                if (_readFailed && _photo != null)
                  TextButton(onPressed: () => _readSlip(_photo!), child: const Text('再讀一次')),
              ]),
            ),
          if (_photo != null && AppConfig.vendorSlipStores.contains(widget.membership.storeName) && !_isReturn)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('儲存後，照片會顯示在這筆進貨上，點縮圖可以看大圖。',
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.4)),
            ),
          if (_photo != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.memory(dataUrlBytes(_photo!), height: _items.isEmpty ? 220 : 140, fit: BoxFit.contain),
            ),
            TextButton(
              onPressed: () => setState(() {
                _photo = null;
                _readSeq++; // 丟掉還在讀的結果
                _reading = false;
                _readMsg = null;
              }),
              child: const Text('移除照片'),
            ),
          ],
          if (_photo == null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _noReceipt,
              onChanged: (v) => setState(() => _noReceipt = v ?? false),
              title: const Text('缺憑（沒有單據可拍）'),
              subtitle: const Text('沒有照片時一定要勾選才能儲存', style: TextStyle(fontSize: AppType.small)),
            ),
        ]),
      );

  /// 存品項明細；失敗回傳要顯示的訊息（進貨本身已經存好了）
  Future<String?> _saveItems(String purchaseId, List<PurchaseItem> rows) async {
    // 修改時：現在沒有明細、原本也沒有，就不用呼叫（舊進貨、已核銷的不會被擋）
    if (widget.editing != null && rows.isEmpty) {
      try {
        if ((await AppScope.of(context).repo.purchaseItems(purchaseId)).isEmpty) return null;
      } catch (_) {}
    }
    try {
      final app = AppScope.of(context);
      await app.repo.savePurchaseItems(purchaseId, rows, negate: _isReturn);
      app.stockRevision.value++;
      return null;
    } catch (e) {
      return '進貨已存好，但品項明細沒存成功（${friendlyError(e)}）。請到這筆進貨按「修改」再存一次。';
    }
  }

  Future<void> _save() async {
    final raw = double.tryParse(_amount.text.replaceAll(',', ''));
    if (_category == null) {
      showMessage(context, '請選擇進貨類別', error: true);
      return;
    }
    if (raw == null || raw <= 0) {
      showMessage(context, '請輸入大於 0 的金額', error: true);
      return;
    }
    // 新增進貨一定要附照片；沒有照片要勾「缺憑」（老闆 2026-10-12；修改舊資料不檢查）
    if (widget.editing == null && _photo == null && !_noReceipt) {
      showMessage(context, '請拍照或選照片附上單據；沒有單據請勾選「缺憑」', error: true);
      return;
    }
    if (_reading) {
      showMessage(context, '照片還在讀取中，請稍等', error: true);
      return;
    }
    final undecided = _items.where((it) => !it.decided).length;
    if (undecided > 0) {
      showMessage(context, '還有 $undecided 行品項沒決定要不要入庫存（點那一行）', error: true);
      return;
    }
    final unsure = _items.where((it) => !it.sure).length;
    if (unsure > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('已經對照單據核對了嗎？'),
          content: Text('有 $unsure 行品項的字看不清楚（標黃色的），建議點開對照單據再確認。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('回去核對')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('已核對，儲存')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final rows = itemsForSave(_items, raw);
    final name = _vendor.text.trim();
    final known = _sups.where((s) => s.name == name).firstOrNull;
    setState(() => _saving = true);
    try {
      if (widget.editing != null) {
        await AppScope.of(context).repo.updatePurchase(
            widget.editing!.id,
            NewPurchase(
              storeId: widget.membership.storeId,
              purchaseDate: _date!,
              categoryCode: _category!,
              supplierId: known?.id,
              vendorName: known == null && name.isNotEmpty ? name : null,
              memo: _memo.text,
              amount: _isReturn ? -raw : raw,
              paidBy: _paidBy,
              clientRequestId: _requestId,
            ));
        if (_itemsLoaded && mounted) {
          final err = await _saveItems(widget.editing!.id, rows);
          if (err != null && mounted) showMessage(context, err, error: true);
        }
        if (mounted) {
          showMessage(context, '已修改');
          Navigator.pop(context, true);
        }
        return;
      }
      final repo = AppScope.of(context).repo;
      final id = await repo.addPurchase(NewPurchase(
            storeId: widget.membership.storeId,
            purchaseDate: _date!,
            categoryCode: _category!,
            supplierId: known?.id,
            vendorName: known == null && name.isNotEmpty ? name : null,
            photoJpeg: _photo == null ? null : dataUrlBytes(_photo!),
            memo: _memo.text,
            amount: _isReturn ? -raw : raw,
            paidBy: _paidBy,
            clientRequestId: _requestId,
            slipDraft: AppConfig.vendorSlipStores.contains(widget.membership.storeName),
            slipVendor: name.isEmpty ? null : name,
            noReceipt: _photo == null && _noReceipt,
          ));
      if (rows.isNotEmpty && mounted) {
        final err = await _saveItems(id, rows);
        if (err != null) {
          if (mounted) {
            showMessage(context, err, error: true);
            Navigator.pop(context, true);
          }
          return;
        }
      }
      if (mounted) {
        final stocked = rows.where((it) => it.toStock).length;
        showMessage(context, stocked == 0 ? '已新增' : '已新增，$stocked 個品項${_isReturn ? '已從庫存扣掉' : '已加進庫存'}');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.editing == null ? '新增進貨' : '修改進貨')),
        body: FutureBuilder<(List<CostCategory>, List<Supplier>)>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (cats, sups) = snap.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              // 付款方式放第一排（老闆 2026-10-12）：先選月結廠商／零用金，下面的類別選項才會對
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'vendor', label: Text('月結廠商'), icon: Icon(Icons.storefront)),
                  ButtonSegment(value: 'petty_cash', label: Text('零用金'), icon: Icon(Icons.payments_outlined)),
                ],
                selected: {_paidBy},
                onSelectionChanged: widget.editing != null && !widget.membership.isManager
                    ? null // 付款方式建立後只有老闆、店長能改（資料庫也會擋）
                    : (v) => setState(() {
                          final old = _category;
                          final oldPaid = _paidBy;
                          _paidBy = v.first;
                          // 切換付款方式後，若原本選的類別在新付款方式下不提供，就清掉；
                          // 廠商若是依原類別自動帶入的（例：德哥），一併清掉，不留沒有類別的廠商
                          if (_hiddenCats.contains(old)) {
                            _category = null;
                            final auto = sups.where((s) => s.defaultCategory == old).map((s) => s.name).toList();
                            if (auto.length == 1 && _vendor.text.trim() == auto.first) _vendor.clear();
                          } else if (old != null) {
                            // 類別保留時，重新比對自動帶入的廠商：原付款方式自動帶入、新付款方式不適用的就清掉，
                            // 再依新付款方式補帶（Codex 審查）
                            final before = _autoSuppliers(sups, old, oldPaid);
                            final after = _autoSuppliers(sups, old, _paidBy);
                            final cur = _vendor.text.trim();
                            if (before.length == 1 && cur == before.first && !after.contains(cur)) _vendor.clear();
                            if (_vendor.text.trim().isEmpty && after.length == 1) _vendor.text = after.first;
                          }
                        }),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('進貨日期'),
                subtitle: const Text('凌晨 6 點前算前一個營業日', style: TextStyle(fontSize: AppType.small)),
                trailing: Text(DateFormat('yyyy/M/d').format(_date!), style: const TextStyle(fontSize: AppType.title)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date!,
                    firstDate: DateTime(2025),
                    // 老闆 2026-10-29：可以登記到下個月底（先記下個月的進貨）
                    lastDate: DateTime(DateTime.now().year, DateTime.now().month + 2, 0),
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '進貨類別'),
                items: [
                  for (final c in cats.where((c) =>
                      (c.storeName == null || c.storeName == widget.membership.storeName) &&
                      // 依付款方式隱藏、停用的類別（0046）不出現；但正在編輯的那筆既有類別仍保留，避免下拉值不在清單內
                      ((!_hiddenCats.contains(c.code) && c.selectable) || c.code == _category)))
                    DropdownMenuItem(
                      value: c.code,
                      child: Text(
                        () {
                          // 零用金付款時：部分類別改顯示名稱、不顯示廠商提示（月結廠商維持原樣）
                          final petty = _paidBy == 'petty_cash';
                          final label = (petty ? AppConfig.pettyCashCategoryLabel[c.code] : null) ?? c.name;
                          // 老闆 2026-10-13：不再顯示常用廠商提示，只有雜項顯示說明
                          final note = AppConfig.categoryNote[c.code];
                          return note == null ? label : '$label（$note）';
                        }(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _category = v;
                  // 只有一家預設廠商、而且還沒填廠商時自動帶入（例：水果＝德哥）
                  // 依合併後類別比對；零用金時排除 pettyCashHintHidden 來源類別的廠商（與提示一致）
                  final match = v == null ? const <String>[] : _autoSuppliers(sups, v, _paidBy);
                  if (_vendor.text.trim().isEmpty && match.length == 1) _vendor.text = match.first;
                }),
              ),
              const SizedBox(height: 12),
              if (_paidBy == 'vendor') _monthlyVendorField() else RawAutocomplete<String>(
                textEditingController: _vendor,
                focusNode: _vendorFocus,
                optionsBuilder: (v) {
                  final q = v.text.trim();
                  if (q.isEmpty) return const Iterable<String>.empty();
                  return sups.map((s) => s.name).where((n) => n.contains(q) && n != q).take(6);
                },
                fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
                  controller: ctrl,
                  focusNode: focus,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: '廠商名稱／品項（選填，自行輸入）',
                    counterText: '',
                  ),
                ),
                optionsViewBuilder: (context, onSelected, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: AppColors.cardHigh,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
                      child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: [
                        for (final o in options) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: '金額（元）', prefixText: '\$ '),
                onChanged: (_) => setState(() {}), // 品項明細的差額跟著變
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('這是退貨／退單'),
                subtitle: const Text('會以負數記錄，沖減當月成本', style: TextStyle(fontSize: AppType.small)),
                value: _isReturn,
                onChanged: (v) => setState(() => _isReturn = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memo,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: '填表人／請款人（選填）',
                  suffixIcon: _members.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '選擇成員',
                          icon: const Icon(Icons.person_search_outlined),
                          onPressed: () => _pick('選擇填表人／請款人', '名單來自 App 成員', _members, _memo),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.editing == null) ...[_scanCard(sups), const SizedBox(height: 12)],
              _itemsCard(),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('儲存', style: TextStyle(fontSize: AppType.title)),
              ),
            ]);
          },
        ),
      );
}


/// 套用老闆指定的提示調整：隱藏、改名、加入（去除重複）
Map<String, List<String>> adjustVendorHints(Map<String, List<String>> hints) {
  final out = <String, List<String>>{};
  final codes = {...hints.keys, ...AppConfig.vendorHintAdd.keys};
  for (final c in codes) {
    if (AppConfig.vendorHintHidden.contains(c)) continue;
    final list = <String>[];
    for (final n in [...?hints[c], ...?AppConfig.vendorHintAdd[c]]) {
      if (AppConfig.vendorHintRemove[c]?.contains(n) ?? false) continue;
      final name = AppConfig.vendorHintRename[n] ?? n;
      if (!list.contains(name)) list.add(name);
    }
    if (list.isNotEmpty) out[c] = list;
  }
  return out;
}

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;


/// 名字選單（月結廠商、填表人／請款人）：上方搜尋、下方清單
class _NamePicker extends StatefulWidget {
  const _NamePicker({required this.title, required this.note, required this.names, this.addLabel});
  final String title;
  final String note;
  final List<String> names;
  /// 有設定時，清單最下面多一列（例：「手動新增廠商」），點了回傳 addSentinel
  final String? addLabel;
  static const addSentinel = '\u0000add';
  @override
  State<_NamePicker> createState() => _NamePickerState();
}

class _NamePickerState extends State<_NamePicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.names.where((n) => _q.isEmpty || n.contains(_q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(widget.note, style: TextStyle(fontSize: AppType.small, color: AppColors.muted)),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜尋', isDense: true),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ]),
          ),
          Expanded(
            child: list.isEmpty && widget.addLabel == null
                ? Center(child: Text('沒有符合的名字', style: TextStyle(color: AppColors.muted)))
                : ListView.builder(
                    itemCount: list.length + (widget.addLabel == null ? 0 : 1),
                    itemBuilder: (_, i) => i < list.length
                        ? ListTile(title: Text(list[i]), onTap: () => Navigator.of(context).pop(list[i]))
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            if (list.isNotEmpty) const Divider(height: 1),
                            ListTile(
                              leading: Icon(Icons.add, color: AppColors.primary),
                              title: Text(widget.addLabel!, style: TextStyle(color: AppColors.primary)),
                              onTap: () => Navigator.of(context).pop('${_NamePicker.addSentinel}$_q'), // 帶上搜尋字，當作預設名稱
                            ),
                          ]),
                  ),
          ),
        ]),
      ),
    );
  }
}
