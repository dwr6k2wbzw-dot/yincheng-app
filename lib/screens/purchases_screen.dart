import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../services/slip_scan.dart';
import '../widgets/common.dart';

/// 進貨管理：本月進貨分成「月結廠商」（廠商請款）與「零用金支出」兩大類，
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  /// 進貨以 Dropbox 日報表為準的店：只能看，不能新增或核銷（核銷也以 Excel 的「核銷」欄為準）
  bool get _synced => AppConfig.excelSyncedStores.contains(widget.membership.storeName);

  Future<(List<Purchase>, Map<String, String>, DateTime?)> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final r = await Future.wait([repo.monthPurchases(id, _month), repo.costCategories()]);
    final cats = {for (final c in r[1] as List<CostCategory>) c.code: c.name};
    DateTime? last;
    if (_synced && widget.membership.canSeeRevenue) last = await repo.lastExcelSync(id);
    return (r[0] as List<Purchase>, cats, last);
  }

  void _reload() => setState(() => _future = _load());

  void _shiftMonth(int d) {
    _month = DateTime(_month.year, _month.month + d);
    _reload();
  }

  Future<void> _openCategory(String title, List<Purchase> items, Map<String, String> cats) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CategoryPurchasesScreen(
          title: title,
          month: _month,
          items: items,
          categoryNames: cats,
          canReconcile: widget.membership.isManager && !_synced,
          membership: widget.membership,
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
            final pending = list.where((p) => p.source == 'app').toList();
            final vendor = list.where((p) => p.paidBy != 'petty_cash').toList();
            final petty = list.where((p) => p.paidBy == 'petty_cash').toList();
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                Row(children: [
                  IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Text(DateFormat('yyyy 年 M 月', 'zh_TW').format(_month),
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  ),
                  IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
                ]),
                const SizedBox(height: 4),
                if (_synced) ...[
                  SectionCard(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.sync, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '進貨由 Dropbox 日報表每小時自動同步，內容和金額一律以日報表為準（日報表的進貨在 App 不能改、不能刪）。'
                          '也可以按右下角在 App 先記一筆（暫記），暫記可以點進去修改或刪除；'
                          '日報表打進同一筆、或日報表已經記到更晚的日期，暫記就不再計入，不會重複算。'
                          '${last == null ? '' : '\n最後一次寫入：${DateFormat('M/d HH:mm').format(last)}'}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],
                _group('vendor', '月結廠商', '廠商請款', Icons.storefront_outlined, vendor, cats),
                const SizedBox(height: 12),
                _group('petty', '零用金支出', '零用金付款', Icons.payments_outlined, petty, cats),
                const SizedBox(height: 12),
                Text('本月進貨合計 ${ntd(list.fold<double>(0, (t, p) => t + p.amount))}，共 ${list.length} 筆',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                if (_synced && (pending.isNotEmpty || replaced > 0 || covered.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (pending.isNotEmpty)
                          '含 App 暫記 ${pending.length} 筆 ${ntd(pending.fold<double>(0, (t, p) => t + p.amount))}（Excel 還沒出現）',
                        if (replaced > 0) '$replaced 筆暫記已由 Excel 取代',
                        if (covered.isNotEmpty) '${covered.length} 筆暫記以日報表為準、不計入（點下方查看）',
                      ].join('；'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.warn, fontSize: 12),
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

  /// 一個大類：標題列（總金額）＋展開後各進貨類別小計
  Widget _group(String key, String title, String sub, IconData icon, List<Purchase> items, Map<String, String> cats) {
    final total = items.fold<double>(0, (t, p) => t + p.amount);
    final byCat = <String, List<Purchase>>{};
    for (final p in items) {
      byCat.putIfAbsent(p.categoryCode, () => []).add(p);
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
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => open ? _open.remove(key) : _open.add(key)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            child: Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$sub・${items.length} 筆', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
              Text(ntd(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: AppColors.muted),
            ]),
          ),
        ),
        if (open) ...[
          const Divider(height: 1),
          if (codes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('本月沒有資料', style: TextStyle(color: AppColors.muted)),
            ),
          for (final c in codes)
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              title: Text(cats[c] ?? c),
              subtitle: Text('${byCat[c]!.length} 筆', style: const TextStyle(fontSize: 12)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(ntd(byCat[c]!.fold<double>(0, (t, p) => t + p.amount)),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ]),
              onTap: () => _openCategory('$title・${cats[c] ?? c}', byCat[c]!, cats),
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
  });
  final Membership membership;
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

  Future<void> _toggle(Purchase p) async {
    try {
      await AppScope.of(context).repo.setReconciled(p.id, !p.reconciled);
      setState(() {
        final i = _items.indexWhere((x) => x.id == p.id);
        _items[i] = Purchase(
          id: p.id, purchaseDate: p.purchaseDate, categoryCode: p.categoryCode, supplierName: p.supplierName,
          memo: p.memo, amount: p.amount, paidBy: p.paidBy, reconciled: !p.reconciled, source: p.source,
          supersededBy: p.supersededBy, excelCovered: p.excelCovered, createdBy: p.createdBy,
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
      showMessage(context, '這筆來自 Dropbox 日報表，以日報表為準；要改請改日報表，下一次同步（每小時）就會更新');
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
            subtitle: Text(locked ? '這筆已以日報表為準（不計入），只能刪除' : 'App 暫記：可以修改或刪除'),
          ),
          if (!locked)
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('修改'), onTap: () => Navigator.pop(c, 'edit')),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.bad),
            title: const Text('刪除', style: TextStyle(color: AppColors.bad)),
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
    final names = groups.keys.toList()
      ..sort((a, b) => groups[b]!.fold<double>(0, (t, p) => t + p.amount)
          .compareTo(groups[a]!.fold<double>(0, (t, p) => t + p.amount)));
    final total = _items.fold<double>(0, (t, p) => t + p.amount);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 16))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        SectionCard(
          child: Row(children: [
            Text(DateFormat('M 月合計', 'zh_TW').format(widget.month), style: const TextStyle(color: AppColors.muted)),
            const Spacer(),
            Text(ntd(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
        ),
        for (final n in names) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              Expanded(child: Text(n, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${groups[n]!.length} 筆・${ntd(groups[n]!.fold<double>(0, (t, p) => t + p.amount))}',
                  style: const TextStyle(color: AppColors.muted)),
            ]),
          ),
          const SizedBox(height: 8),
          for (final p in groups[n]!) ...[
            _PurchaseTile(
              p: p,
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
      {required this.p, required this.categoryName, required this.canReconcile, required this.onToggle, required this.onTap});
  final Purchase p;
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
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.supplierName ?? p.memo ?? categoryName, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('M/d').format(p.purchaseDate)}・$categoryName'
                '${p.paidBy == 'petty_cash' ? '・零用金' : ''}${p.source == 'import' ? '・日報表' : (p.counted ? '・App 暫記（點一下可改）' : '・以日報表為準，不計入')}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ]),
          ),
          Text(ntd(p.amount),
              style: TextStyle(fontWeight: FontWeight.w700, color: p.amount < 0 ? AppColors.good : null)),
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
class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key, required this.membership, this.editing});
  final Membership membership;
  /// 修改既有的 App 暫記（null＝新增）
  final Purchase? editing;
  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _amount = TextEditingController();
  final _memo = TextEditingController();
  // 同一張表單只產生一次：網路重送時資料庫會以這個 id 擋下重複
  final _requestId = const Uuid().v4();
  DateTime? _date;
  String? _category;
  final _vendor = TextEditingController(); // 廠商名稱：自行輸入（和既有廠商同名就自動對應）
  String? _photo; // 送貨單照片（JPEG data URL）
  bool _scanning = false;
  String? _scanNote;
  List<Supplier> _sups = [];
  Map<String, List<String>> _hints = {}; // 類別 → 常用廠商（日報表統計）
  String _paidBy = 'vendor';
  bool _isReturn = false;
  bool _saving = false;
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
    try {
      _hints = adjustVendorHints(await repo.vendorHints(id));
    } catch (_) {} // 提示讀不到不影響新增
    _sups = r[1] as List<Supplier>;
    // 填表人預設帶入自己的名字（可以改成請款人）
    if (_memo.text.isEmpty && e == null) _memo.text = widget.membership.displayName;
    return (r[0] as List<CostCategory>, r[1] as List<Supplier>);
  }

  final _vendorFocus = FocusNode();

  /// 拍照辨識送貨單：讀出廠商、日期、合計填進表單（使用者核對後再儲存）
  Future<void> _scan(List<Supplier> sups) async {
    String? photo;
    try {
      photo = await pickSlipImage();
    } catch (e) {
      if (mounted) showMessage(context, '照片讀取失敗：$e', error: true);
      return;
    }
    if (photo == null || !mounted) return;
    setState(() {
      _photo = photo;
      _scanning = true;
      _scanNote = null;
    });
    try {
      final text = await ocrSlip(photo);
      final g = guessSlip(text, sups.map((s) => s.name).toList());
      if (!mounted) return;
      final got = <String>[];
      setState(() {
        if (g.vendor != null) {
          _vendor.text = g.vendor!;
          got.add('廠商');
        }
        if (g.date != null) {
          _date = g.date;
          got.add('日期');
        }
        if (g.total != null) {
          _amount.text = g.total! == g.total!.roundToDouble() ? g.total!.toInt().toString() : g.total!.toString();
          got.add('金額');
        }
        _scanNote = got.isEmpty
            ? '沒有讀到可用的資料，請自己填寫（照片會一起存）'
            : '已帶入${got.join('、')}，文字辨識可能讀錯，請對照照片核對';
      });
    } catch (e) {
      if (mounted) setState(() => _scanNote = '辨識失敗（${e.toString().replaceAll('Error: ', '')}），請自己填寫；照片仍會一起存');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Widget _scanCard(List<Supplier> sups) => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('拍照辨識送貨單', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (_scanning)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton(
                onPressed: _saving ? null : () => _scan(sups),
                child: Text(_photo == null ? '拍照／選照片' : '重拍'),
              ),
          ]),
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('辨識中…第一次使用要下載辨識資料，可能需要 20～60 秒',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
          if (_scanNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_scanNote!, style: const TextStyle(color: AppColors.warn, fontSize: 12)),
            ),
          if (_photo != null && AppConfig.vendorSlipStores.contains(widget.membership.storeName) && !_isReturn)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('儲存後，這張送貨單會在一小時內自動變成「銷貨單」分頁的草稿，再由老闆或店長核對品項。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
            ),
          if (_photo != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(dataUrlBytes(_photo!), height: 220, fit: BoxFit.contain),
            ),
            TextButton(
              onPressed: _scanning ? null : () => setState(() {
                _photo = null;
                _scanNote = null;
              }),
              child: const Text('不附照片'),
            ),
          ],
        ]),
      );

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
        if (mounted) {
          showMessage(context, '已修改');
          Navigator.pop(context, true);
        }
        return;
      }
      await AppScope.of(context).repo.addPurchase(NewPurchase(
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
          ));
      if (mounted) {
        showMessage(context, '已新增');
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
        appBar: AppBar(title: Text(widget.editing == null ? '新增進貨' : '修改進貨（App 暫記）')),
        body: FutureBuilder<(List<CostCategory>, List<Supplier>)>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (cats, sups) = snap.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('進貨日期'),
                subtitle: const Text('凌晨 6 點前算前一個營業日', style: TextStyle(fontSize: 12)),
                trailing: Text(DateFormat('yyyy/M/d').format(_date!), style: const TextStyle(fontSize: 16)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date!,
                    firstDate: DateTime(2025),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
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
                  for (final c in cats.where((c) => c.storeName == null || c.storeName == widget.membership.storeName))
                    DropdownMenuItem(
                      value: c.code,
                      child: Text(
                        _hints[c.code] == null ? c.name : '${c.name}（${_hints[c.code]!.join('、')}）',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _category = v;
                  // 只有一家預設廠商、而且還沒填廠商時自動帶入（例：水果＝德哥）
                  final match = sups.where((s) => s.defaultCategory == v).toList();
                  if (_vendor.text.trim().isEmpty && match.length == 1) _vendor.text = match.first.name;
                }),
              ),
              const SizedBox(height: 12),
              RawAutocomplete<String>(
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
                  decoration: const InputDecoration(labelText: '廠商名稱／品項（選填，自行輸入）', counterText: ''),
                ),
                optionsViewBuilder: (context, onSelected, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: AppColors.cardHigh,
                    borderRadius: BorderRadius.circular(12),
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
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('這是退貨／退單'),
                subtitle: const Text('會以負數記錄，沖減當月成本', style: TextStyle(fontSize: 12)),
                value: _isReturn,
                onChanged: (v) => setState(() => _isReturn = v),
              ),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'vendor', label: Text('廠商請款'), icon: Icon(Icons.storefront)),
                  ButtonSegment(value: 'petty_cash', label: Text('零用金'), icon: Icon(Icons.payments_outlined)),
                ],
                selected: {_paidBy},
                onSelectionChanged: widget.editing != null && !widget.membership.isManager
                    ? null // 付款方式建立後只有老闆、店長能改（資料庫也會擋）
                    : (v) => setState(() => _paidBy = v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memo,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '填表人／請款人（選填）'),
              ),
              const SizedBox(height: 12),
              if (widget.editing == null) _scanCard(sups),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('儲存', style: TextStyle(fontSize: 16)),
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
      final name = AppConfig.vendorHintRename[n] ?? n;
      if (!list.contains(name)) list.add(name);
    }
    if (list.isNotEmpty) out[c] = list;
  }
  return out;
}
