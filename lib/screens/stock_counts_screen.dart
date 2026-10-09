import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

Color _statusColor(CountStatus s) => switch (s) {
      CountStatus.draft => AppColors.muted,
      CountStatus.submitted => AppColors.warn,
      CountStatus.approved => AppColors.good,
      CountStatus.rejected => AppColors.bad,
      CountStatus.voided => AppColors.muted,
    };

/// 盤點（PRD 畫面 05）：草稿 → 送出 → 店長核准／退回；核准後鎖定（由資料庫保證）
class StockCountsScreen extends StatefulWidget {
  const StockCountsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<StockCountsScreen> createState() => _StockCountsScreenState();
}

class _StockCountsScreenState extends State<StockCountsScreen> {
  late Future<List<StockCount>> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = AppScope.of(context).repo.stockCounts(widget.membership.storeId);
  }

  void _reload() => setState(() => _future = AppScope.of(context).repo.stockCounts(widget.membership.storeId));

  Future<void> _open(String countId) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => StockCountDetailScreen(membership: widget.membership, countId: countId)));
    _reload();
  }

  Future<void> _create() async {
    try {
      final id = await AppScope.of(context).repo.createStockCount(widget.membership.storeId, null);
      if (mounted) await _open(id);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.playlist_add_check),
          label: const Text('開始盤點'),
        ),
        body: FutureBuilder<List<StockCount>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            if (list.isEmpty) return const Center(child: Text('還沒有盤點紀錄', style: TextStyle(color: AppColors.muted)));
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = list[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _open(c.id),
                    child: SectionCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${DateFormat('yyyy/M/d').format(c.bizDate)} 盤點',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('${c.lineCount} 項${c.note == null ? '' : '・${c.note}'}',
                                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          ]),
                        ),
                        Text(countStatusLabel(c.status), style: TextStyle(color: _statusColor(c.status))),
                        const Icon(Icons.chevron_right, color: AppColors.muted),
                      ]),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
}

class StockCountDetailScreen extends StatefulWidget {
  const StockCountDetailScreen({super.key, required this.membership, required this.countId});
  final Membership membership;
  final String countId;
  @override
  State<StockCountDetailScreen> createState() => _StockCountDetailScreenState();
}

class _StockCountDetailScreenState extends State<StockCountDetailScreen> {
  StockCount? _count;
  List<Product> _products = [];
  Map<String, double> _qty = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).repo;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final counts = await repo.stockCounts(widget.membership.storeId);
      final products = await repo.products(widget.membership.storeId);
      final lines = await repo.countLines(widget.countId);
      setState(() {
        _count = counts.firstWhere((c) => c.id == widget.countId);
        _products = products;
        _qty = {for (final l in lines) l.productId: l.qty};
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _editable {
    final s = _count?.status;
    final mine = _count?.countedBy == AppScope.of(context).repo.currentUserId;
    if (s == CountStatus.draft || s == CountStatus.rejected) return mine || widget.membership.isManager;
    if (s == CountStatus.submitted) return widget.membership.isManager;
    return false;
  }

  Future<void> _editQty(Product p) async {
    final ctrl = TextEditingController(text: _qty[p.id]?.toString() ?? '');
    final v = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(p.name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(labelText: '實際數量', suffixText: p.unit),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text)), child: const Text('確定')),
        ],
      ),
    );
    if (v == null || !mounted) return;
    try {
      await AppScope.of(context).repo.upsertCountLine(widget.countId, p.id, v);
      setState(() => _qty[p.id] = v);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _setStatus(CountStatus s, {String? reason}) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).repo.setCountStatus(widget.countId, s, voidReason: reason);
      if (mounted) showMessage(context, '已${countStatusLabel(s).replaceAll('已', '')}');
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _void() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('作廢盤點'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '作廢原因（必填）')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('作廢')),
        ],
      ),
    );
    if (reason != null && reason.isNotEmpty) await _setStatus(CountStatus.voided, reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final c = _count;
    final repo = AppScope.of(context).repo;
    final mine = c?.countedBy == repo.currentUserId;
    final isOwner = widget.membership.role == Role.owner;
    return Scaffold(
      appBar: AppBar(title: Text(c == null ? '盤點' : '${DateFormat('M/d').format(c.bizDate)} 盤點')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SectionCard(
                      child: Row(children: [
                        const Text('狀態：', style: TextStyle(color: AppColors.muted)),
                        Text(countStatusLabel(c!.status), style: TextStyle(color: _statusColor(c.status))),
                        const Spacer(),
                        Text('已填 ${_qty.length} / ${_products.length} 項',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: _products.isEmpty
                        ? const Center(child: Text('尚未建立品項，請先由老闆／店長新增品項', style: TextStyle(color: AppColors.muted)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: _products.length,
                            itemBuilder: (_, i) {
                              final p = _products[i];
                              final q = _qty[p.id];
                              return ListTile(
                                title: Text(p.name),
                                subtitle: Text(p.category, style: const TextStyle(fontSize: 12)),
                                trailing: Text(q == null ? '—' : '${NumberFormat('#,##0.##').format(q)} ${p.unit}',
                                    style: TextStyle(fontSize: 16, color: q == null ? AppColors.muted : null)),
                                onTap: _editable ? () => _editQty(p) : null,
                              );
                            },
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
                        if ((c.status == CountStatus.draft || c.status == CountStatus.rejected) && (mine || widget.membership.isManager))
                          FilledButton.icon(
                            onPressed: _busy || _qty.isEmpty ? null : () => _setStatus(CountStatus.submitted),
                            icon: const Icon(Icons.send),
                            label: const Text('送出給店長'),
                          ),
                        if (c.status == CountStatus.submitted && widget.membership.isManager) ...[
                          OutlinedButton(
                            onPressed: _busy ? null : () => _setStatus(CountStatus.rejected),
                            child: const Text('退回'),
                          ),
                          FilledButton.icon(
                            // 店長不能核准自己做的盤點（資料庫也會擋）
                            onPressed: _busy || (mine && !isOwner) ? null : () => _setStatus(CountStatus.approved),
                            icon: const Icon(Icons.verified),
                            label: Text(mine && !isOwner ? '需由他人核准' : '核准'),
                          ),
                        ],
                        if (c.status == CountStatus.approved && isOwner)
                          TextButton(onPressed: _busy ? null : _void, child: const Text('作廢（需填原因）')),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
