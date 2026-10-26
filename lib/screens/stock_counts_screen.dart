import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 盤點（老闆 2026-10-16 重新設計）：
/// - 目的：只看庫存、低於安全量就提醒（不算成本）
/// - 品項由老闆／店長／正職在 App 新增（名稱、類別、單位、安全量）
/// - 酒類開過的：整瓶＋剩幾成（0.1 為單位）
/// - 誰盤都直接算數：盤完直接更新庫存，不用核准
const stockCategories = ['酒水', '餐食', '雜項'];

String fmtQty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

int _catOrder(String c) {
  final i = stockCategories.indexOf(c);
  return i < 0 ? stockCategories.length : i;
}

List<Product> _sorted(List<Product> list) => [...list]
  ..sort((a, b) {
    final c = _catOrder(a.category).compareTo(_catOrder(b.category));
    return c != 0 ? c : a.name.compareTo(b.name);
  });

bool _isLow(Product p, StockLevel? s) => p.parLevel != null && s != null && s.qty < p.parLevel!;

class StockCountsScreen extends StatefulWidget {
  const StockCountsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<StockCountsScreen> createState() => _StockCountsScreenState();
}

class _StockCountsScreenState extends State<StockCountsScreen> {
  late Future<(List<Product>, Map<String, StockLevel>)> _future;
  bool _started = false;
  String _cat = '全部';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  Future<(List<Product>, Map<String, StockLevel>)> _load() async {
    final repo = AppScope.of(context).repo;
    final r = await Future.wait<dynamic>(
        [repo.products(widget.membership.storeId), repo.latestStock(widget.membership.storeId)]);
    return (_sorted(r[0] as List<Product>), r[1] as Map<String, StockLevel>);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _open(Widget screen) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(List<Product>, Map<String, StockLevel>)>(
        future: _future,
        builder: (context, snap) {
          final data = snap.data;
          return Scaffold(
            floatingActionButton: data == null || data.$1.isEmpty
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => _open(StockCountScreen(membership: widget.membership, products: data.$1, last: data.$2)),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('開始盤點'),
                  ),
            body: snap.hasError
                ? ErrorView(message: friendlyError(snap.error!), onRetry: _reload)
                : data == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(onRefresh: () async => _reload(), child: _body(data.$1, data.$2)),
          );
        },
      );

  Widget _body(List<Product> products, Map<String, StockLevel> last) {
    // 品項管理：老闆、店長、正職（0051，老闆 2026-10-16）＋兼職（0067，老闆 2026-10-26）
    final isMgr = widget.membership.isManager || widget.membership.role == Role.staff || widget.membership.isPartTime;
    final low = products.where((p) => _isLow(p, last[p.id])).toList();
    final cats = ['全部', ...stockCategories, ...{for (final p in products) p.category}.where((c) => !stockCategories.contains(c))];
    final shown = products.where((p) => _cat == '全部' || p.category == _cat).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
      Row(children: [
        Expanded(child: Text('庫存', style: TextStyle(fontSize: 12, color: AppColors.muted, letterSpacing: 2))),
        if (isMgr)
          TextButton.icon(
            onPressed: () => _open(ProductsScreen(membership: widget.membership)),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('品項管理'),
          ),
        TextButton.icon(
          onPressed: () => _open(StockHistoryScreen(membership: widget.membership)),
          icon: const Icon(Icons.history, size: 18),
          label: const Text('盤點紀錄'),
        ),
      ]),
      if (products.isEmpty)
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('還沒有盤點品項', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
                isMgr
                    ? '先到「品項管理」新增要盤點的東西（名稱、類別、單位、安全量），就可以開始盤點。'
                    : '請老闆、店長、正職或兼職先到「品項管理」新增要盤點的品項。',
                style: TextStyle(color: AppColors.muted, height: 1.5)),
          ]),
        )
      else ...[
        // 缺貨提醒
        if (low.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bad.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.bad.withValues(alpha: 0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.bad, size: 20),
                const SizedBox(width: 8),
                Text('缺貨提醒・${low.length} 項', style: TextStyle(color: AppColors.bad, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              for (final p in low)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text(p.name)),
                    Text('剩 ${fmtQty(last[p.id]!.qty)} ${p.unit}',
                        style: TextStyle(color: AppColors.bad, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                    Text('（安全量 ${fmtQty(p.parLevel!)}）', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        for (final p in shown) ...[_stockRow(p, last[p.id]), const SizedBox(height: 8)],
      ],
    ]);
  }

  Widget _stockRow(Product p, StockLevel? s) {
    final low = _isLow(p, s);
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              '${p.category}・${s == null ? '還沒盤過' : '${DateFormat('M/d').format(s.date)} 盤'}'
              '${p.parLevel == null ? '' : '・安全量 ${fmtQty(p.parLevel!)}'}',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ]),
        ),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: s == null ? '—' : fmtQty(s.qty),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: low ? AppColors.bad : null, fontFeatures: tabular)),
          TextSpan(text: ' ${p.unit}', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ])),
      ]),
    );
  }
}

/// 開始盤點：每個品項填「整數＋剩幾成」，點過或按「同上次」才算有盤；只更新有盤的品項
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key, required this.membership, required this.products, required this.last});
  final Membership membership;
  final List<Product> products;
  final Map<String, StockLevel> last;
  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  final _whole = <String, int>{};
  final _tenth = <String, int>{};
  final _done = <String>{};
  String _q = '';
  String _cat = '全部'; // 盤點時只看某一類（老闆 2026-10-27）
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final p in widget.products) {
      // 先四捨五入到 0.1 再拆整數與幾成（0.96 → 1.0，不會變成 0.9；Codex 審查）
      final tenths = ((widget.last[p.id]?.qty ?? 0) * 10).round();
      _whole[p.id] = tenths ~/ 10;
      _tenth[p.id] = tenths % 10;
    }
  }

  double _qty(String id) => _whole[id]! + _tenth[id]! / 10;

  void _set(String id, {int? whole, int? tenth}) => setState(() {
        if (whole != null) _whole[id] = whole.clamp(0, 9999);
        if (tenth != null) _tenth[id] = tenth;
        _done.add(id);
      });

  Future<void> _save() async {
    if (_done.isEmpty) {
      showMessage(context, '還沒有盤任何品項', error: true);
      return;
    }
    final left = widget.products.length - _done.length;
    if (left > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('完成盤點？'),
          content: Text('已盤 ${_done.length} 項，還有 $left 項沒盤。\n只會更新已盤的品項，沒盤的維持上次的數量。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('繼續盤')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('完成')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final lines = {for (final id in _done) id: _qty(id)};
    setState(() => _saving = true);
    final repo = AppScope.of(context).repo;
    try {
      final id = await repo.createStockCount(widget.membership.storeId, null);
      for (final e in lines.entries) {
        await repo.upsertCountLine(id, e.key, e.value);
      }
      // 誰盤都直接算數（老闆 2026-10-16）：送出就是最新庫存
      await repo.setCountStatus(id, CountStatus.submitted);
      if (!mounted) return;
      showMessage(context, '已完成盤點（${lines.length} 項）');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showMessage(context, friendlyError(e), error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.products
        .where((p) => _q.isEmpty || p.name.toLowerCase().contains(_q.toLowerCase()))
        .where((p) => _cat == '全部' || p.category == _cat)
        .toList();
    // 類別：照品項管理的順序，再接店裡自己加的類別
    final present = {for (final p in widget.products) p.category};
    final cats = ['全部', ...stockCategories.where(present.contains), ...present.where((c) => !stockCategories.contains(c))];
    String chipLabel(String c) {
      final items = c == '全部' ? widget.products : widget.products.where((p) => p.category == c);
      final done = items.where((p) => _done.contains(p.id)).length;
      return '$c $done/${items.length}';
    }
    final groups = <String, List<Product>>{};
    for (final p in list) {
      groups.putIfAbsent(p.category, () => []).add(p);
    }
    return PopScope(
      // 儲存中不能離開（Codex 審查：避免伺服器已存但畫面沒更新、重複盤點）
      canPop: _done.isEmpty && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('離開盤點？'),
            content: const Text('已填的數量不會儲存。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('繼續盤')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('離開')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop(false);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('盤點・${DateFormat('M/d').format(bizToday())}')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 110), children: [
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜尋品項'),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: 10),
          // 類別：點一下只看那一類，數字是「已盤／總數」
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(chipLabel(c)), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
                ),
            ]),
          ),
          for (final cat in groups.keys) ...[
            const SizedBox(height: 14),
            Text(cat, style: TextStyle(color: AppColors.primary, fontSize: 13, letterSpacing: 2)),
            const SizedBox(height: 6),
            for (final p in groups[cat]!) ...[_countRow(p), const SizedBox(height: 8)],
          ],
          const SizedBox(height: 10),
          Text('數量＝整數＋剩幾成（例如 3 瓶又剩 4 成＝3.4）。沒變的按「同上次」。',
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('完成盤點（已盤 ${_done.length} / ${widget.products.length}）'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _countRow(Product p) {
    final done = _done.contains(p.id);
    final last = widget.last[p.id];
    final w = _whole[p.id]!, t = _tenth[p.id]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: done ? AppColors.primary.withValues(alpha: 0.6) : AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (done) ...[Icon(Icons.check_circle, size: 16, color: AppColors.primary), const SizedBox(width: 6)],
          Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(last == null ? '上次：沒盤過' : '上次 ${fmtQty(last.qty)}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(
            tooltip: '減 1',
            onPressed: w > 0 ? () => _set(p.id, whole: w - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 44,
            child: Text('$w', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, fontFeatures: tabular)),
          ),
          IconButton(tooltip: '加 1', onPressed: () => _set(p.id, whole: w + 1), icon: const Icon(Icons.add_circle_outline)),
          const SizedBox(width: 4),
          // 剩幾成
          DropdownButton<int>(
            value: t,
            underline: const SizedBox.shrink(),
            items: [
              for (var i = 0; i <= 9; i++) DropdownMenuItem(value: i, child: Text(i == 0 ? '＋0' : '＋$i 成')),
            ],
            onChanged: (v) {
              if (v != null) _set(p.id, tenth: v);
            },
          ),
          Text(' ${p.unit}', style: TextStyle(color: AppColors.muted)),
          const Spacer(),
          if (!done)
            TextButton(onPressed: () => _set(p.id), child: Text(last == null ? '確認' : '同上次'))
          else
            Text(fmtQty(_qty(p.id)), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontFeatures: tabular)),
          const SizedBox(width: 6),
        ]),
      ]),
    );
  }
}

/// 刪除類別結果：moved＝品項移到 target；deactivated＝品項一起停用
class CategoryDeleteResult {
  const CategoryDeleteResult(this.target, this.ids, {this.complete = true});
  final String? target; // null＝一起停用
  final Set<String> ids; // 已處理的品項
  final bool complete; // false＝中途出錯，類別可能還在
}

/// 刪除類別（老闆 2026-10-16；2026-10-26 品項表單也能刪）：
/// 類別是跟著品項存的，所以刪除＝把裡面的品項移到別的類別，或一起停用。
/// 沒帶 items 就自己去讀這個類別的品項。取消回傳 null。酒水／餐食／雜項不能刪。
Future<CategoryDeleteResult?> deleteStockCategory(
    BuildContext context, Membership membership, String cat, List<String> cats,
    {List<Product>? items}) async {
  if (stockCategories.contains(cat)) return null;
  final repo = AppScope.of(context).repo;
  try {
    items ??= (await repo.products(membership.storeId)).where((p) => p.category == cat).toList();
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
    return null;
  }
  if (!context.mounted) return null;
  final list = items;
  final others = [...{...stockCategories, ...cats}].where((c) => c != cat).toList();
  String target = others.first;
  final action = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: Text('刪除「$cat」類別？'),
        content: list.isEmpty
            ? const Text('這個類別目前沒有品項，可以直接刪除。')
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('這個類別有 ${list.length} 個品項。要把它們移到：'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in others)
                    ChoiceChip(label: Text(o), selected: target == o, onSelected: (_) => setD(() => target = o)),
                ]),
                const SizedBox(height: 12),
                Text('或是把這些品項一起停用（以前的盤點紀錄會保留）。', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
        actions: list.isEmpty
            ? [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(c, 'move'), child: const Text('刪除')),
              ]
            : [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(c, 'deactivate'),
                    child: Text('一起停用', style: TextStyle(color: AppColors.bad))),
                FilledButton(onPressed: () => Navigator.pop(c, 'move'), child: Text('移到「$target」')),
              ],
      ),
    ),
  );
  if (action == null || !context.mounted) return null;
  final done = <String>{};
  try {
    for (final p in list) {
      if (action == 'move') {
        await repo.saveProduct(membership.storeId, Product(p.id, p.name, target, p.unit, parLevel: p.parLevel));
      } else {
        await repo.deactivateProduct(p.id);
      }
      done.add(p.id);
    }
    if (context.mounted) {
      showMessage(
          context,
          list.isEmpty
              ? '「$cat」已刪除'
              : action == 'move'
                  ? '已把 ${list.length} 個品項移到「$target」，「$cat」已刪除'
                  : '已停用 ${list.length} 個品項，「$cat」已刪除');
    }
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
    return CategoryDeleteResult(action == 'move' ? target : null, done, complete: false);
  }
  return CategoryDeleteResult(action == 'move' ? target : null, done);
}

/// 品項管理（老闆／店長／正職，0051）：新增、修改、停用
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late Future<List<Product>> _future;
  bool _started = false;
  bool _changed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  Future<List<Product>> _load() async => _sorted(await AppScope.of(context).repo.products(widget.membership.storeId));

  List<String> _cats = stockCategories;

  Future<void> _deleteCategory(String cat, List<Product> items) async {
    final r = await deleteStockCategory(context, widget.membership, cat, _cats, items: items);
    if (r == null || !mounted) return;
    _changed = true;
    setState(() => _future = _load());
  }

  Future<void> _edit(Product? p, {String? category}) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => ProductFormScreen(membership: widget.membership, product: p, category: category, categories: _cats)));
    if (saved == true && mounted) {
      _changed = true;
      setState(() => _future = _load());
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).pop(_changed);
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('品項管理')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('新增品項'),
          ),
          body: FutureBuilder<List<Product>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) return ErrorView(message: friendlyError(snap.error!));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!;
              // 依類別分組（老闆 2026-10-16）：酒水、餐食、雜項一定出現，加上店裡已有的其他類別（例如副材料、水果）
              final groups = <String, List<Product>>{for (final c in stockCategories) c: []};
              for (final p in list) {
                groups.putIfAbsent(p.category, () => []).add(p);
              }
              _cats = groups.keys.toList();
              return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                for (final cat in groups.keys) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: Text('$cat・${groups[cat]!.length} 項',
                          style: TextStyle(color: AppColors.primary, fontSize: 13, letterSpacing: 2)),
                    ),
                    TextButton.icon(
                      onPressed: () => _edit(null, category: cat),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('新增$cat'),
                    ),
                    // 刪除類別（老闆 2026-10-16）：酒水／餐食／雜項是固定的，其他可以刪
                    if (!stockCategories.contains(cat))
                      IconButton(
                        tooltip: '刪除類別',
                        onPressed: () => _deleteCategory(cat, groups[cat]!),
                        icon: Icon(Icons.delete_outline, size: 20, color: AppColors.muted),
                      ),
                  ]),
                  if (groups[cat]!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('還沒有品項', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ),
                  for (final p in groups[cat]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        title: Text(p.name),
                        subtitle: Text('${p.category}・${p.unit}${p.parLevel == null ? '' : '・安全量 ${fmtQty(p.parLevel!)}'}',
                            style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _edit(p),
                      ),
                    ),
                  ),
                ],
              ]);
            },
          ),
        ),
      );
}

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen(
      {super.key, required this.membership, this.product, this.category, this.categories = stockCategories});
  final Membership membership;
  final Product? product;
  final String? category; // 從某個類別按「新增」：預先選好
  final List<String> categories; // 店裡現有的類別
  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _unit = TextEditingController(text: widget.product?.unit ?? '瓶');
  late final _par = TextEditingController(text: widget.product?.parLevel == null ? '' : fmtQty(widget.product!.parLevel!));
  // 舊類別（例如「水果」）保留原本的，除非使用者自己改（Codex 審查）
  late String _cat = widget.product?.category ?? widget.category ?? '酒水';
  late final List<String> _cats = [
    ...{...widget.categories, ...stockCategories, _cat}
  ];

  // 新增類別（老闆 2026-10-16）：輸入名稱，存了這個品項後就會出現在清單裡
  Future<void> _newCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('新增類別'),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 12, decoration: const InputDecoration(hintText: '例如：副材料')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('確定')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      if (!_cats.contains(name)) _cats.add(name);
      _cat = name;
    });
  }
  bool _saving = false;
  bool _catChanged = false; // 這頁刪過類別：離開時要讓品項管理重新讀取

  /// 按類別的 ×：剛新增、還沒存過的直接拿掉；店裡已有的類別要處理裡面的品項（移走或停用）
  Future<void> _removeCategory(String c) async {
    final saved = widget.categories.contains(c) || c == widget.product?.category;
    if (!saved) {
      setState(() {
        _cats.remove(c);
        if (_cat == c) _cat = widget.category != c && widget.category != null ? widget.category! : '酒水';
      });
      return;
    }
    setState(() => _saving = true);
    final r = await deleteStockCategory(context, widget.membership, c, _cats);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r == null) return;
    _catChanged = true;
    final mine = widget.product != null && r.ids.contains(widget.product!.id);
    // 正在修改的這個品項跟著類別一起停用了：直接回清單
    if (mine && r.target == null) {
      Navigator.pop(context, true);
      return;
    }
    if (!r.complete) return;
    setState(() {
      _cats.remove(c);
      if (_cat == c) _cat = r.target ?? '酒水';
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final unit = _unit.text.trim();
    final parText = _par.text.trim();
    final par = parText.isEmpty ? null : double.tryParse(parText);
    if (name.isEmpty) return showMessage(context, '請填品項名稱', error: true);
    if (unit.isEmpty) return showMessage(context, '請填單位', error: true);
    if (parText.isNotEmpty && (par == null || par < 0)) return showMessage(context, '安全量請填數字', error: true);
    setState(() => _saving = true);
    try {
      await AppScope.of(context)
          .repo
          .saveProduct(widget.membership.storeId, Product(widget.product?.id ?? '', name, _cat, unit, parLevel: par));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        final msg = friendlyError(e);
        showMessage(context, msg.contains('duplicate') || msg.contains('unique') ? '已經有同名的品項' : msg, error: true);
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('停用這個品項？'),
        content: Text('「${widget.product!.name}」之後不會出現在盤點清單，以前的盤點紀錄照常保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('停用')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).repo.deactivateProduct(widget.product!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showMessage(context, friendlyError(e), error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  // 儲存／停用進行中不能離開（Codex 審查：避免清單沒更新、重複新增）
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving && !_catChanged,
      onPopInvokedWithResult: (didPop, _) {
        // 刪過類別：回上一頁時帶 true，品項管理才會重新讀取
        if (!didPop && !_saving && _catChanged) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.product == null ? '新增品項' : '修改品項')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: '品項名稱', counterText: '')),
          const SizedBox(height: 14),
          Text('類別', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _cats)
              // 酒水／餐食／雜項固定；其他類別都可以按 × 刪除（老闆 2026-10-26）
              if (!stockCategories.contains(c))
                InputChip(
                  label: Text(c),
                  selected: _cat == c,
                  onSelected: (_) => setState(() => _cat = c),
                  deleteButtonTooltipMessage: '刪除類別',
                  onDeleted: _saving ? null : () => _removeCategory(c),
                )
              else
                ChoiceChip(label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
            ActionChip(avatar: Icon(Icons.add, size: 18, color: AppColors.primary), label: const Text('新增類別'), onPressed: _newCategory),
          ]),
          const SizedBox(height: 14),
          TextField(controller: _unit, maxLength: 10, decoration: const InputDecoration(labelText: '單位', counterText: '')),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final u in const ['瓶', '罐', '包', '盒', '顆', '公斤', '箱'])
              ActionChip(label: Text(u), onPressed: () => setState(() => _unit.text = u)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _par,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: '安全量（選填，低於這個數量就提醒）'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('儲存'),
          ),
          if (widget.product != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : _deactivate,
              child: Text('停用這個品項', style: TextStyle(color: AppColors.bad)),
            ),
          ],
        ]),
      ));
}

/// 盤點紀錄：最近 30 次，點進去看那次盤了哪些、各多少
class StockHistoryScreen extends StatefulWidget {
  const StockHistoryScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends State<StockHistoryScreen> {
  Future<List<StockCount>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).repo.stockCounts(widget.membership.storeId).then(
        (l) => l.where((c) => c.status == CountStatus.submitted || c.status == CountStatus.approved).toList());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('盤點紀錄')),
        body: FutureBuilder<List<StockCount>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            if (list.isEmpty) return Center(child: Text('還沒有盤點紀錄', style: TextStyle(color: AppColors.muted)));
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final c in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      title: Text(DateFormat('yyyy/M/d（E）', 'zh_TW').format(c.bizDate)),
                      subtitle: Text('${c.lineCount} 項', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CountDetail(count: c))),
                    ),
                  ),
                ),
            ]);
          },
        ),
      );
}

class _CountDetail extends StatefulWidget {
  const _CountDetail({required this.count});
  final StockCount count;
  @override
  State<_CountDetail> createState() => _CountDetailState();
}

class _CountDetailState extends State<_CountDetail> {
  Future<List<CountLine>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).repo.countLines(widget.count.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${DateFormat('M/d').format(widget.count.bizDate)} 盤點')),
        body: FutureBuilder<List<CountLine>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final l in snap.data!)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(l.productName)),
                    Text('${fmtQty(l.qty)} ${l.unit}', style: const TextStyle(fontFeatures: tabular)),
                  ]),
                ),
            ]);
          },
        ),
      );
}
