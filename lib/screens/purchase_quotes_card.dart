// 進貨報價（老闆 2026-11-13：原本的「本月進貨總表」改成這個）
// 每個品項最近一次的進貨單價，分酒類、餐食、雜項。資料來自拍照讀到的進貨品項（自動帶進來的只有酒類、餐食）；
// 老闆、店長可以點一項修改品名／單位／單價、搬到別的類別，或把它從報價表拿掉（0105）；
// 也可以手動新增品項（0107，老闆 2026-11-13 18:31）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/purchase_items_math.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PurchaseQuotesCard extends StatefulWidget {
  const PurchaseQuotesCard({super.key, required this.membership});
  final Membership membership;
  @override
  State<PurchaseQuotesCard> createState() => PurchaseQuotesCardState();
}

class PurchaseQuotesCardState extends State<PurchaseQuotesCard> {
  static const _fold = 12; // 超過就先收起來
  Future<List<ItemQuote>>? _future;
  String _group = 'drink';
  String _q = '';
  final _search = TextEditingController();
  bool _all = false;
  bool _showHidden = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<ItemQuote>> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final r = await Future.wait<dynamic>([
      repo.purchaseQuoteLines(id),
      repo.purchaseQuoteEdits(id),
      repo.costCategories()
    ]);
    return buildQuotes(r[0] as List<QuoteLine>, r[1] as List<QuoteEdit>,
        quoteGroupOf(r[2] as List<CostCategory>));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 進貨頁下拉重新整理、新增進貨後呼叫
  void reload() => setState(() => _future = _load());

  bool get _canEdit => widget.membership.isManager;

  Future<void> _run(Future<void> Function() act, String done) async {
    try {
      await act();
      if (!mounted) return;
      showMessage(context, done);
      reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _edit(ItemQuote q) async {
    final r = await showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (_) => _QuoteEditSheet(quote: q),
    );
    if (r == null || !mounted) return;
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    switch (r.action) {
      case _Act.hide:
        await _run(() => repo.savePurchaseQuoteEdit(id, r.edit!), '已從報價表拿掉「${q.name}」');
      case _Act.delete:
        await _run(() => repo.deletePurchaseQuoteEdit(id, q.key), '已刪除「${q.name}」');
      case _Act.restore:
        await _run(() => repo.deletePurchaseQuoteEdit(id, q.key), '已還原成進貨資料');
      case _Act.move:
        await _run(() => repo.savePurchaseQuoteEdit(id, r.edit!), '已把「${q.name}」搬到${quoteGroupLabel(r.edit!.group!)}');
      case _Act.save:
        final e = r.edit!;
        // 進貨算出來的品項：什麼都沒改（也沒搬類別）就等於還原
        if (!e.manual && e.name == null && e.unit == null && e.unitPrice == null && e.group == null) {
          await _run(() => repo.deletePurchaseQuoteEdit(id, q.key), '已還原成進貨資料');
        } else {
          await _run(() => repo.savePurchaseQuoteEdit(id, e), '已修改');
        }
    }
  }

  /// 手動新增品項（0107）：預設放在目前看的這一類
  Future<void> _add() async {
    final r = await showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (_) => _QuoteEditSheet(group: _group),
    );
    if (r == null || r.edit == null || !mounted) return;
    final repo = AppScope.of(context).repo;
    await _run(() => repo.savePurchaseQuoteEdit(widget.membership.storeId, r.edit!), '已新增「${r.edit!.name}」');
    if (mounted && r.edit!.group != null && r.edit!.group != _group) {
      // 換到新增的那一類：搜尋字一起清掉（跟點類別一樣，Codex 審查）
      setState(() {
        _group = r.edit!.group!;
        _q = '';
        _search.clear();
        _all = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ItemQuote>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 80,
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          return _card(snap.data ?? const [], snap.hasError);
        },
      );

  Widget _card(List<ItemQuote> all, bool error) {
    final live = all.where((r) => !r.hidden).toList();
    final hidden = all.where((r) => r.hidden).toList();
    int count(String g) => live.where((r) => r.group == g).length;
    final rows = live.where((r) => r.group == _group).toList();
    final q = _q.toLowerCase();
    final hit = q.isEmpty
        ? rows
        : rows
            .where((r) =>
                r.name.toLowerCase().contains(q) ||
                (r.vendor ?? '').toLowerCase().contains(q))
            .toList();
    final shown = _all || q.isNotEmpty ? hit : hit.take(_fold).toList();
    final muted = TextStyle(color: AppColors.muted, fontSize: AppType.caption);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.sell_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          const Expanded(
              child: Text('進貨報價',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: AppType.title))),
          if (live.isNotEmpty)
            Text('${live.length} 項',
                style:
                    TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        ]),
        const SizedBox(height: 4),
        Text(
          error
              ? '進貨報價暫時讀不到，下拉可以重新整理'
              : live.isEmpty && hidden.isEmpty
                  ? '還沒有資料。新增進貨時拍送貨單，讀到的品項和單價會自動列在這裡${_canEdit ? '；也可以自己新增' : ''}。'
                  : '每個品項最近一次的進貨單價，來自拍照讀到的送貨單${_canEdit ? '；點一項可以修改、搬到別的類別或拿掉' : ''}',
          style: TextStyle(
              color: AppColors.muted, fontSize: AppType.small, height: 1.45),
        ),
        if (live.isNotEmpty || hidden.isNotEmpty || _canEdit) ...[
          const SizedBox(height: 12),
          Wrap(runSpacing: 8, children: [
            for (final g in quoteGroups)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SelectChip(
                  label: Text('${g.$2} ${count(g.$1)}'),
                  selected: _group == g.$1,
                  onSelected: (_) => setState(() {
                    _group = g.$1;
                    // 換分區時清掉搜尋字：另一區品項少的時候搜尋欄不會出現，留著會把東西藏起來清不掉（Codex 審查）
                    _q = '';
                    _search.clear();
                    _all = false;
                  }),
                ),
              ),
          ]),
          // 有搜尋字時搜尋欄一定留著：搬走、刪掉、拿掉之後品項變少，也還能清掉搜尋字（Codex 審查）
          if (rows.length > _fold || _q.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: '搜尋品項或廠商',
                  isDense: true),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 7, child: Text('品項', style: muted)),
            Expanded(
                flex: 2,
                child: Text('單位', style: muted, textAlign: TextAlign.center)),
            Expanded(
                flex: 4,
                child: Text('進貨單價', style: muted, textAlign: TextAlign.right)),
          ]),
          const SizedBox(height: 6),
          Divider(height: 1, color: AppColors.line),
          for (final r in shown) _row(r),
          if (hit.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(rows.isEmpty ? '這一類還沒有資料' : '沒有符合的品項',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted)),
            ),
          if (q.isEmpty && rows.length > _fold)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? '收起' : '看全部 ${rows.length} 項'),
              ),
            ),
          if (_canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: Text('新增${quoteGroupLabel(_group)}品項'),
              ),
            ),
          if (_canEdit && hidden.isNotEmpty) ...[
            Divider(height: 1, color: AppColors.line),
            InkWell(
              onTap: () => setState(() => _showHidden = !_showHidden),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Text('已拿掉 ${hidden.length} 項',
                        style: TextStyle(
                            color: AppColors.muted, fontSize: AppType.small)),
                  ),
                  Icon(_showHidden ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.muted, size: 20),
                ]),
              ),
            ),
            if (_showHidden)
              for (final r in hidden)
                Row(children: [
                  Expanded(
                    child: Text(
                        '${r.name}${r.unit == null ? '' : '／${r.unit}'}・${ntd(r.rawPrice)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.muted, fontSize: AppType.small)),
                  ),
                  TextButton(
                    onPressed: () {
                      final repo = AppScope.of(context).repo;
                      final id = widget.membership.storeId;
                      // 拿掉之前改過的品名、類別這些，放回去時照樣留著
                      _run(
                          () => r.edit != null && r.edit!.hasChanges
                              ? repo.savePurchaseQuoteEdit(id, r.edit!.copyWithHidden(false))
                              : repo.deletePurchaseQuoteEdit(id, r.key),
                          '已放回報價表');
                    },
                    child: const Text('放回去'),
                  ),
                ]),
          ],
        ],
      ]),
    );
  }

  Widget _row(ItemQuote r) {
    final up = r.previous != null && r.price > r.previous!;
    final sub = [
      DateFormat('M/d').format(r.date),
      if ((r.vendor ?? '').trim().isNotEmpty) r.vendor!.trim(),
      if (r.custom) '手動新增' else if (r.manual) '手動改價' else if (r.edited) '已修改',
    ].join('・');
    return InkWell(
      onTap: _canEdit ? () => _edit(r) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(
              flex: 7,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: AppType.small,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: r.manual || r.custom
                                ? AppColors.primary
                                : AppColors.muted,
                            fontSize: AppType.caption)),
                  ]),
            ),
            Expanded(
              flex: 2,
              child: Text(r.unit ?? '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.muted, fontSize: AppType.small)),
            ),
            Expanded(
              flex: 4,
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(ntd(r.price),
                    style: const TextStyle(
                        fontSize: AppType.body,
                        fontWeight: AppFont.label,
                        fontFeatures: tabular)),
                if (r.previous != null)
                  Text('${up ? '▲' : '▼'} 原 ${ntd(r.previous!)}',
                      style: TextStyle(
                          color: up ? AppColors.warn : AppColors.good,
                          fontSize: AppType.caption,
                          fontFeatures: tabular)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

enum _Act { save, move, hide, restore, delete }

class _SheetResult {
  const _SheetResult(this.action, [this.edit]);
  final _Act action;
  final QuoteEdit? edit;
}

/// 修改一項報價（品名、單位、單價、搬到別的類別；拿掉或還原），或手動新增一項（quote＝null）
class _QuoteEditSheet extends StatefulWidget {
  const _QuoteEditSheet({this.quote, this.group = 'drink'});
  final ItemQuote? quote;
  final String group; // 新增時預設的類別
  @override
  State<_QuoteEditSheet> createState() => _QuoteEditSheetState();
}

class _QuoteEditSheetState extends State<_QuoteEditSheet> {
  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  late final _name = TextEditingController(text: widget.quote?.name ?? '');
  late final _unit = TextEditingController(text: widget.quote?.unit ?? '');
  late final _price = TextEditingController(text: widget.quote == null ? '' : _num(widget.quote!.price));
  late String _newGroup = widget.group; // 只有新增時用
  String? _error;

  bool get _isNew => widget.quote == null;
  bool get _custom => _isNew || widget.quote!.custom;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final unit = _unit.text.trim();
    final price = double.tryParse(_price.text.trim());
    if (name.isEmpty) return setState(() => _error = '請填品名');
    if (price == null || price < 0) return setState(() => _error = '單價請填數字');
    final q = widget.quote;
    if (_custom) {
      // 手動新增的：每個欄位都照填的存
      final today = bizToday();
      Navigator.pop(
        context,
        _SheetResult(
          _Act.save,
          QuoteEdit(
            key: q?.key ?? 'manual:${const Uuid().v4()}',
            name: name,
            unit: unit.isEmpty ? null : unit,
            unitPrice: round2(price),
            asOf: q?.date ?? today,
            group: q?.group ?? _newGroup,
            manual: true,
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _SheetResult(
        _Act.save,
        QuoteEdit(
          key: q!.key,
          // 跟進貨資料一樣的欄位不存（之後進貨資料變了會跟著變）
          name: name == q.rawName ? null : name,
          unit: unit == (q.rawUnit ?? '') ? null : unit,
          unitPrice: round2(price) == q.rawPrice ? null : round2(price),
          asOf: q.date,
          asOfAt: q.at,
          group: q.edit?.group, // 搬過的類別保留
        ),
      ),
    );
  }

  /// 搬到別的類別：其他修改照舊
  void _move(String g) {
    final q = widget.quote!;
    final base = q.edit ?? QuoteEdit(key: q.key, asOf: q.date, asOfAt: q.at);
    Navigator.pop(context, _SheetResult(_Act.move, base.copyWith(group: g)));
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    final sub = TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.45);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_isNew ? '新增品項' : '修改報價', style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (q != null && !q.custom)
              Text(
                '進貨資料：${q.rawName}${q.rawUnit == null ? '' : '／${q.rawUnit}'}・${ntd(q.rawPrice)}'
                '（${DateFormat('M/d').format(q.date)}${(q.vendor ?? '').isEmpty ? '' : ' ${q.vendor}'}）',
                style: sub,
              )
            else if (q != null)
              Text('手動新增・${DateFormat('M/d').format(q.date)}${(q.edit?.by ?? '').isEmpty ? '' : '・${q.edit!.by}'}', style: sub)
            else
              Text('還沒進過、或送貨單讀不到的品項，可以自己加進報價表。', style: sub),
            const SizedBox(height: 14),
            TextField(
                controller: _name,
                autofocus: _isNew,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '品名', counterText: '')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _unit, maxLength: 20, decoration: const InputDecoration(labelText: '單位', counterText: '')),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: '進貨單價（元）', prefixText: '\$ '),
                ),
              ),
            ]),
            if (_isNew) ...[
              const SizedBox(height: 14),
              Text('類別', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final g in quoteGroups)
                  SelectChip(label: Text(g.$2), selected: _newGroup == g.$1, onSelected: (_) => setState(() => _newGroup = g.$1)),
              ]),
            ],
            const SizedBox(height: 6),
            Text(
                _error ??
                    (_custom ? '手動新增的品項不會被進貨資料蓋掉，要改就點它修改。' : '改過的單價會一直顯示，直到下一次進這個品項（那時改看新的進貨單價）。'),
                style: TextStyle(color: _error == null ? AppColors.muted : AppColors.bad, fontSize: AppType.small, height: 1.45)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(_isNew ? '新增' : '儲存'),
            ),
            if (q != null) ...[
              const SizedBox(height: 18),
              Text('搬到其他類別（現在在${quoteGroupLabel(q.group)}）', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              const SizedBox(height: 8),
              Row(children: [
                for (final g in quoteGroups.where((g) => g.$1 != q.group)) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _move(g.$1),
                      icon: const Icon(Icons.drive_file_move_outline, size: 18),
                      label: Text('搬到${g.$2}'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    ),
                  ),
                  if (g != quoteGroups.where((g) => g.$1 != q.group).last) const SizedBox(width: 10),
                ],
              ]),
              const SizedBox(height: 8),
              Row(children: [
                if (!q.custom && q.edited)
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, const _SheetResult(_Act.restore)),
                      child: const Text('還原成進貨資料'),
                    ),
                  ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(
                        context,
                        q.custom
                            ? const _SheetResult(_Act.delete)
                            : _SheetResult(_Act.hide, (q.edit ?? QuoteEdit(key: q.key)).copyWithHidden())),
                    child: Text(q.custom ? '刪除這一項' : '從報價表拿掉', style: TextStyle(color: AppColors.bad)),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
