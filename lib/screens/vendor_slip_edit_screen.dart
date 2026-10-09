import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 新增／修改一張銷貨單（老闆、店長）。文字辨識的草稿在這裡核對後按「確認無誤」。
class VendorSlipEditScreen extends StatefulWidget {
  const VendorSlipEditScreen({super.key, required this.membership, this.slip, this.month});
  final Membership membership;
  final VendorSlip? slip; // null：新增
  final DateTime? month;
  @override
  State<VendorSlipEditScreen> createState() => _VendorSlipEditScreenState();
}

class _LineCtrl {
  final code = TextEditingController();
  final name = TextEditingController();
  final qty = TextEditingController();
  final unit = TextEditingController();
  final price = TextEditingController();
  final amount = TextEditingController();
  _LineCtrl([VendorSlipLine? l]) {
    if (l != null) {
      code.text = l.itemCode ?? '';
      name.text = l.itemName;
      qty.text = _num(l.qty);
      unit.text = l.unit ?? '';
      price.text = l.unitPrice == null ? '' : _num(l.unitPrice!);
      amount.text = _num(l.amount);
    } else {
      qty.text = '1';
    }
  }
  void dispose() {
    for (final c in [code, name, qty, unit, price, amount]) {
      c.dispose();
    }
  }
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
double? _parse(String s) => double.tryParse(s.replaceAll(',', '').trim());

class _VendorSlipEditScreenState extends State<VendorSlipEditScreen> {
  final _vendor = TextEditingController();
  final _slipNo = TextEditingController();
  final _total = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;
  final _lines = <_LineCtrl>[];
  bool _busy = false;

  bool get _isNew => widget.slip == null;

  @override
  void initState() {
    super.initState();
    final s = widget.slip;
    final m = widget.month ?? DateTime.now();
    _date = s?.date ?? (DateTime.now().month == m.month ? DateTime.now() : DateTime(m.year, m.month, 1));
    if (s != null) {
      _vendor.text = s.vendor;
      _slipNo.text = s.slipNo;
      _total.text = _num(s.total);
      _note.text = s.note ?? '';
      _lines.addAll(s.lines.map(_LineCtrl.new));
    }
    if (_lines.isEmpty) _lines.add(_LineCtrl());
  }

  @override
  void dispose() {
    for (final c in [_vendor, _slipNo, _total, _note]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _linesTotal => _lines.fold(0.0, (a, l) => a + (_parse(l.amount.text) ?? 0));

  Future<void> _save({required bool confirm}) async {
    final total = _parse(_total.text);
    if (_vendor.text.trim().isEmpty || _slipNo.text.trim().isEmpty) {
      showMessage(context, '請填廠商和單號', error: true);
      return;
    }
    if (total == null || total < 0) {
      showMessage(context, '合計要填數字', error: true);
      return;
    }
    final lines = <VendorSlipLine>[];
    for (final (i, l) in _lines.indexed) {
      if (l.name.text.trim().isEmpty && l.amount.text.trim().isEmpty) continue; // 空白行略過
      final qty = _parse(l.qty.text);
      final amount = _parse(l.amount.text);
      final price = l.price.text.trim().isEmpty ? null : _parse(l.price.text);
      if (l.name.text.trim().isEmpty || qty == null || amount == null || (l.price.text.trim().isNotEmpty && price == null)) {
        showMessage(context, '第 ${i + 1} 項：品名、數量、金額要填，數字要正確', error: true);
        return;
      }
      lines.add(VendorSlipLine(i + 1, l.code.text.trim(), l.name.text.trim(), qty, l.unit.text.trim(), price, amount));
    }
    final diff = (lines.fold(0.0, (a, l) => a + l.amount) - total).abs();
    if (confirm && diff > 0.001) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('合計對不上'),
          content: Text('品項金額加起來是 ${ntd(_linesTotal)}，單據合計是 ${ntd(total)}。\n還是要確認嗎？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('回去修改')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('仍然確認')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final status = confirm ? 'confirmed' : (widget.slip?.status ?? 'confirmed');
    final slip = VendorSlip(widget.slip?.id ?? '', _vendor.text.trim(), _slipNo.text.trim(), _date, total,
        _note.text.trim(), lines,
        status: status,
        // 新增：算在目前畫面的月份；修改：維持原本月份
        periodMonth: _isNew ? DateTime((widget.month ?? _date).year, (widget.month ?? _date).month, 1) : null);
    final repo = AppScope.of(context).repo;
    setState(() => _busy = true);
    try {
      await repo.saveVendorSlip(widget.membership.storeId, slip);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('刪除這張單據'),
        content: Text('刪除 ${widget.slip!.vendor} 單號 ${widget.slip!.slipNo}（含所有品項）？\n刪除後不會再被自動匯入回來。'),
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
    final repo = AppScope.of(context).repo;
    try {
      await repo.deleteVendorSlip(widget.slip!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  void _autoAmount(_LineCtrl l) {
    final q = _parse(l.qty.text);
    final p = _parse(l.price.text);
    if (q != null && p != null) l.amount.text = _num(q * p);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slip;
    final total = _parse(_total.text);
    final mismatch = total != null && (_linesTotal - total).abs() > 0.001;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新增銷貨單' : (s!.isDraft ? '核對草稿' : '修改銷貨單')),
        actions: [
          if (!_isNew) IconButton(tooltip: '刪除', icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : _delete),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
        if (s != null && s.isDraft)
          SectionCard(
            child: Text(
              '這張是文字辨識產生的草稿，字和數字可能讀錯。請對照紙本或 Dropbox 裡的掃描檔'
              '${s.sourceFile == null ? '' : '（${s.sourceFile}）'}修改，確認後按「確認無誤」。',
              style: const TextStyle(color: AppColors.warn, fontSize: 13, height: 1.5),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _vendor, decoration: const InputDecoration(labelText: '廠商'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _slipNo, decoration: const InputDecoration(labelText: '單號'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _date, firstDate: DateTime(2025), lastDate: DateTime(2030));
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: '單據日期'),
                child: Text(DateFormat('yyyy/M/d（E）', 'zh_TW').format(_date)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: '單據合計'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLines: null, decoration: const InputDecoration(labelText: '備註')),
        const SizedBox(height: 16),
        Row(children: [
          const Text('品項', style: TextStyle(color: AppColors.muted)),
          const Spacer(),
          Text('品項合計 ${ntd(_linesTotal)}',
              style: TextStyle(color: mismatch ? AppColors.bad : AppColors.muted, fontWeight: FontWeight.w600)),
        ]),
        if (mismatch)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('品項金額加起來和單據合計不一樣', style: TextStyle(color: AppColors.bad, fontSize: 12)),
          ),
        const SizedBox(height: 8),
        for (final (i, l) in _lines.indexed) _lineCard(i, l),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => setState(() => _lines.add(_LineCtrl())),
          icon: const Icon(Icons.add),
          label: const Text('加一個品項'),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            if (s == null || !s.isDraft)
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _save(confirm: true),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('儲存'),
                ),
              )
            else ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _save(confirm: false),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('先存草稿'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _save(confirm: true),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('確認無誤'),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _lineCard(int i, _LineCtrl l) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SectionCard(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
          child: Column(children: [
            Row(children: [
              Text('#${i + 1}', style: const TextStyle(color: AppColors.muted)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: l.name,
                  decoration: const InputDecoration(labelText: '品名', isDense: true),
                ),
              ),
              IconButton(
                tooltip: '刪除這個品項',
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() {
                  _lines.removeAt(i).dispose();
                  if (_lines.isEmpty) _lines.add(_LineCtrl());
                }),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(controller: l.code, decoration: const InputDecoration(labelText: '編號', isDense: true)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: l.qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _autoAmount(l),
                    decoration: const InputDecoration(labelText: '數量', isDense: true),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: TextField(controller: l.unit, decoration: const InputDecoration(labelText: '單位', isDense: true)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: l.price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _autoAmount(l),
                    decoration: const InputDecoration(labelText: '單價', isDense: true),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: l.amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: '金額', isDense: true),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );
}
