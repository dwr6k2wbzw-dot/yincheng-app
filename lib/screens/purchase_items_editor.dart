// 進貨品項明細（0087，老闆 2026-11-01）
//   拍照辨識送貨單 → 一行一個品項 → 店員核對、改 → 存檔後列進「本月進貨總表」
//   老闆 2026-11-06：移除「加進庫存」的選項（辨識後直接列在總表）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/purchase_items_math.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'stock_counts_screen.dart' show fmtQty;

String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
double? _parse(String s) => double.tryParse(s.replaceAll(',', '').trim());

/// 品項明細卡片（新增／修改進貨表單裡）
class PurchaseItemsCard extends StatelessWidget {
  const PurchaseItemsCard({
    super.key,
    required this.items,
    required this.total,
    required this.isReturn,
    required this.onTap,
    required this.onAdd,
    this.enabled = true,
  });
  final List<PurchaseItem> items;
  final double? total; // 單據金額（表單上的金額欄）
  final bool isReturn;
  final void Function(int index) onTap;
  final VoidCallback onAdd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final sum = itemsTotal(items);
    final diff = total == null ? null : round2(total! - sum);
    final unsure = items.where((it) => !it.sure).length;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.inventory_2_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('品項明細', style: TextStyle(fontWeight: FontWeight.w600))),
          if (items.isNotEmpty)
            Text('${items.length} 項', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            items.isEmpty
                ? '選填。拍照後會自動列出；也可以自己新增。存檔後會列進本月進貨總表。'
                : '存檔後會列進本月進貨總表；點一行可以修改',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.4),
          ),
        ),
        if (unsure > 0) _Notice(color: AppColors.warn, text: '$unsure 行字看不清楚，請對照單據'),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.line),
          _ItemRow(item: items[i], onTap: enabled ? () => onTap(i) : null),
        ],
        if (items.isNotEmpty) ...[
          Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 8),
          _SumLine(label: '品項合計', value: ntd(sum)),
          if (diff != null && diff != 0)
            _SumLine(
              label: '其他差額',
              value: '${diff > 0 ? '＋' : '−'}${ntd(diff.abs())}',
              note: '運費、稅、折讓等，存檔時另記一行',
              warn: diff.abs() > (total!.abs() * 0.2) && diff.abs() >= 100,
            ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增一行'),
          ),
        ),
      ]),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: AppType.small, color: color, height: 1.4))),
        ]),
      );
}

class _SumLine extends StatelessWidget {
  const _SumLine({required this.label, required this.value, this.note, this.warn = false});
  final String label;
  final String value;
  final String? note;
  final bool warn;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: AppColors.muted, fontSize: AppType.small))),
            Text(value,
                style: TextStyle(
                    fontWeight: AppFont.label, fontFeatures: tabular, color: warn ? AppColors.warn : null)),
          ]),
          if (note != null)
            Text(warn ? '差額偏大，請確認金額或品項有沒有漏' : note!,
                style: TextStyle(color: warn ? AppColors.warn : AppColors.muted, fontSize: AppType.caption)),
        ]),
      );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});
  final PurchaseItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final unit = item.unit?.trim().isNotEmpty == true ? item.unit! : '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (!item.sure) ...[
                  Icon(Icons.visibility_outlined, size: 15, color: AppColors.warn),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: item.sure ? null : AppColors.warn)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                '${fmtQty(item.qty)}$unit${item.unitPrice == null ? '' : ' × ${ntd(item.unitPrice!)}'}',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small, fontFeatures: tabular),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Text(ntd(item.amount), style: const TextStyle(fontFeatures: tabular)),
        ]),
      ),
    );
  }
}

/// 修改一行的結果：null＝取消、delete＝刪掉這行
sealed class ItemEdit {}

class ItemSaved extends ItemEdit {
  ItemSaved(this.item);
  final PurchaseItem item;
}

class ItemDeleted extends ItemEdit {}

/// 修改一行（底部面板）
Future<ItemEdit?> editPurchaseItem(
  BuildContext context, {
  required PurchaseItem item,
  required bool isNew,
}) =>
    showModalBottomSheet<ItemEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (_) => _ItemSheet(item: item.copy(), isNew: isNew),
    );

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item, required this.isNew});
  final PurchaseItem item;
  final bool isNew;
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _qty = TextEditingController(text: _num(widget.item.qty == 0 ? null : widget.item.qty));
  late final _unit = TextEditingController(text: widget.item.unit ?? '');
  late final _price = TextEditingController(text: _num(widget.item.unitPrice));
  late final _amount =
      TextEditingController(text: widget.item.unitPrice == null ? '' : _num(round2(widget.item.amount)));

  // 單價、小計互相帶（數量不變時）
  void _fromPrice() {
    final q = _parse(_qty.text), p = _parse(_price.text);
    if (q != null && p != null) _amount.text = _num(round2(q * p));
  }

  void _fromAmount() {
    final q = _parse(_qty.text), a = _parse(_amount.text);
    if (q != null && q != 0 && a != null) _price.text = _num(round2(a / q));
  }

  void _done() {
    final name = _name.text.trim();
    final qty = _parse(_qty.text);
    if (name.isEmpty) return showMessage(context, '請填品名', error: true);
    if (qty == null || qty <= 0) return showMessage(context, '數量要大於 0', error: true);
    final price = _parse(_price.text);
    Navigator.pop(
      context,
      ItemSaved(PurchaseItem(
        name: name,
        qty: qty,
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        unitPrice: price == null ? null : round2(price),
        // 原本已經對應庫存的舊明細：沒改品名就保留對應（老闆 2026-11-06 起新的不再對應庫存）
        productId: name == widget.item.name ? widget.item.productId : null,
        stockQty: name == widget.item.name ? widget.item.stockQty : null,
        source: widget.item.source,
        sure: true, // 店員看過、按完成＝已核對
        decided: true,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.isNew ? '新增品項' : '修改品項',
                style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
            if (!widget.item.sure)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('這一行字看不清楚，請對照單據核對',
                    style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: '品名', counterText: ''),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: '數量'),
                  onChanged: (_) => _fromPrice(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _unit,
                  maxLength: 10,
                  decoration: const InputDecoration(labelText: '單位', hintText: '瓶、箱', counterText: ''),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(labelText: '單價', prefixText: '\$ '),
                  onChanged: (_) => _fromPrice(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(labelText: '小計', prefixText: '\$ '),
                  onChanged: (_) => _fromAmount(),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              if (!widget.isNew)
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, ItemDeleted()),
                  icon: Icon(Icons.delete_outline, color: AppColors.bad, size: 18),
                  label: Text('刪掉這行', style: TextStyle(color: AppColors.bad)),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _done,
                style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                child: const Text('完成'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
