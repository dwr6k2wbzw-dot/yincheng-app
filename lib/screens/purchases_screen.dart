import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 進貨管理（PRD 畫面 03／04）：最近進貨列表＋新增進貨；老闆／店長可核銷
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late Future<(List<Purchase>, Map<String, String>)> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  Future<(List<Purchase>, Map<String, String>)> _load() async {
    final repo = AppScope.of(context).repo;
    final r = await Future.wait([repo.recentPurchases(widget.membership.storeId), repo.costCategories()]);
    final cats = {for (final c in r[1] as List<CostCategory>) c.code: c.name};
    return (r[0] as List<Purchase>, cats);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _toggleReconcile(Purchase p) async {
    try {
      await AppScope.of(context).repo.setReconciled(p.id, !p.reconciled);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
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
        body: FutureBuilder<(List<Purchase>, Map<String, String>)>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (list, cats) = snap.data!;
            if (list.isEmpty) return const Center(child: Text('還沒有進貨紀錄', style: TextStyle(color: AppColors.muted)));
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _PurchaseTile(
                  p: list[i],
                  categoryName: cats[list[i].categoryCode] ?? list[i].categoryCode,
                  canReconcile: widget.membership.isManager,
                  onToggle: () => _toggleReconcile(list[i]),
                ),
              ),
            );
          },
        ),
      );
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.p, required this.categoryName, required this.canReconcile, required this.onToggle});
  final Purchase p;
  final String categoryName;
  final bool canReconcile;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.supplierName ?? p.memo ?? categoryName, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('M/d').format(p.purchaseDate)}・$categoryName'
                '${p.paidBy == 'petty_cash' ? '・零用金' : ''}${p.source == 'import' ? '・Excel' : ''}',
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
      );
}

/// 新增進貨（PRD 畫面 04）
class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key, required this.membership});
  final Membership membership;
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
  String? _supplierId;
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
    _date ??= r[2] as DateTime;
    return (r[0] as List<CostCategory>, r[1] as List<Supplier>);
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
    setState(() => _saving = true);
    try {
      await AppScope.of(context).repo.addPurchase(NewPurchase(
            storeId: widget.membership.storeId,
            purchaseDate: _date!,
            categoryCode: _category!,
            supplierId: _supplierId,
            memo: _memo.text,
            amount: _isReturn ? -raw : raw,
            paidBy: _paidBy,
            clientRequestId: _requestId,
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
        appBar: AppBar(title: const Text('新增進貨')),
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
                decoration: const InputDecoration(labelText: '進貨類別'),
                items: [for (final c in cats) DropdownMenuItem(value: c.code, child: Text(c.name))],
                onChanged: (v) => setState(() {
                  _category = v;
                  // 只有一家預設廠商時自動帶入（例：水果＝德哥）
                  final match = sups.where((s) => s.defaultCategory == v).toList();
                  if (_supplierId == null && match.length == 1) _supplierId = match.first.id;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: _supplierId,
                decoration: const InputDecoration(labelText: '廠商（選填）'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('（不指定）')),
                  for (final s in sups) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _supplierId = v),
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
                onSelectionChanged: (v) => setState(() => _paidBy = v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memo,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '摘要／備註（選填）'),
              ),
              const SizedBox(height: 12),
              const SectionCard(
                child: Row(children: [
                  Icon(Icons.photo_camera_outlined, color: AppColors.muted),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('拍照辨識送貨單：下一版加入（收據儲存空間與權限已在資料庫完成）',
                        style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ),
                ]),
              ),
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
