// 進貨品項明細（0087，老闆 2026-11-01）
//   拍照辨識送貨單 → 一行一個品項 → 店員核對、改 → 有對應庫存品項的加進庫存
//   老闆決定：辨識結果先填表單、店員核對再存；配不到庫存品項的「建議對應，店員確認」
//   （選一個既有品項、一鍵新增成庫存品項，或標成不入庫存）
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
    required this.products,
    required this.total,
    required this.isReturn,
    required this.onTap,
    required this.onAdd,
    this.enabled = true,
  });
  final List<PurchaseItem> items;
  final List<Product> products;
  final double? total; // 單據金額（表單上的金額欄）
  final bool isReturn;
  final void Function(int index) onTap;
  final VoidCallback onAdd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final p in products) p.id: p};
    final sum = itemsTotal(items);
    final diff = total == null ? null : round2(total! - sum);
    final undecided = items.where((it) => !it.decided).length;
    final unsure = items.where((it) => !it.sure).length;
    final stocked = items.where((it) => it.toStock).length;
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
                ? '選填。拍照後會自動列出；也可以自己新增。對應到庫存品項的，存檔後會${isReturn ? '從庫存扣掉' : '加進庫存'}。'
                : stocked == 0
                    ? '沒有品項會${isReturn ? '從庫存扣掉' : '加進庫存'}'
                    : '$stocked 項存檔後會${isReturn ? '從庫存扣掉' : '加進庫存'}；點一行可以修改',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.4),
          ),
        ),
        if (undecided > 0 || unsure > 0)
          _Notice(
            color: AppColors.warn,
            text: [
              if (unsure > 0) '$unsure 行字看不清楚，請對照單據',
              if (undecided > 0) '$undecided 行還沒決定要不要入庫存',
            ].join('；'),
          ),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.line),
          _ItemRow(item: items[i], product: byId[items[i].productId], isReturn: isReturn, onTap: enabled ? () => onTap(i) : null),
        ],
        if (items.isNotEmpty) ...[
          Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 8),
          _SumLine(label: '品項合計', value: ntd(sum)),
          if (diff != null && diff != 0)
            _SumLine(
              label: '其他差額',
              value: '${diff > 0 ? '＋' : '−'}${ntd(diff.abs())}',
              note: '運費、稅、折讓等，存檔時另記一行（不入庫存）',
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
  const _ItemRow({required this.item, required this.product, required this.isReturn, required this.onTap});
  final PurchaseItem item;
  final Product? product;
  final bool isReturn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final unit = item.unit?.trim().isNotEmpty == true ? item.unit! : '';
    final Widget stock;
    if (!item.decided) {
      stock = _Tag(icon: Icons.help_outline, text: '入庫存？點這裡決定', color: AppColors.warn);
    } else if (item.toStock && product != null) {
      stock = _Tag(
        icon: Icons.inventory_2_outlined,
        text: '${product!.name} ${isReturn ? '−' : '＋'}${fmtQty(item.stockQty!)} ${product!.unit}',
        color: AppColors.good,
      );
    } else {
      stock = _Tag(icon: Icons.remove_circle_outline, text: '不入庫存', color: AppColors.muted);
    }
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
              const SizedBox(height: 6),
              stock,
            ]),
          ),
          const SizedBox(width: 12),
          Text(ntd(item.amount), style: const TextStyle(fontFeatures: tabular)),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.caption, color: color, fontWeight: AppFont.label)),
        ),
      ]);
}

/// 修改一行的結果：null＝取消、delete＝刪掉這行
sealed class ItemEdit {}

class ItemSaved extends ItemEdit {
  ItemSaved(this.item);
  final PurchaseItem item;
}

class ItemDeleted extends ItemEdit {}

/// 修改一行（底部面板）。createProduct：一鍵新增庫存品項，回傳新品項（失敗回傳 null，訊息自己顯示）
Future<ItemEdit?> editPurchaseItem(
  BuildContext context, {
  required PurchaseItem item,
  required List<Product> products,
  required bool isNew,
  required bool isReturn,
  required Future<Product?> Function(String name, String unit) createProduct,
}) =>
    showModalBottomSheet<ItemEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (_) => _ItemSheet(
          item: item.copy(), products: products, isNew: isNew, isReturn: isReturn, createProduct: createProduct),
    );

enum _Stock { product, none }

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({
    required this.item,
    required this.products,
    required this.isNew,
    required this.isReturn,
    required this.createProduct,
  });
  final PurchaseItem item;
  final List<Product> products;
  final bool isNew;
  final bool isReturn;
  final Future<Product?> Function(String name, String unit) createProduct;
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
  late final _stockQty = TextEditingController(text: _num(widget.item.stockQty));
  late List<Product> _products = widget.products;
  _Stock? _mode;
  Product? _product;
  Product? _suggest;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _product = _products.where((p) => p.id == it.productId).firstOrNull;
    if (it.decided) _mode = _product != null && it.stockQty != null ? _Stock.product : _Stock.none;
    if (_product == null) _suggest = suggestProduct(it.name, _products);
  }

  // 單價、小計互相帶（數量不變時）
  void _fromPrice() {
    final q = _parse(_qty.text), p = _parse(_price.text);
    if (q != null && p != null) _amount.text = _num(round2(q * p));
  }

  void _fromAmount() {
    final q = _parse(_qty.text), a = _parse(_amount.text);
    if (q != null && q != 0 && a != null) _price.text = _num(round2(a / q));
  }

  void _choose(Product p) {
    final cur = PurchaseItem(
        name: _name.text, qty: _parse(_qty.text) ?? 0, unit: _unit.text, stockQty: _parse(_stockQty.text));
    setState(() {
      _product = p;
      _mode = _Stock.product;
      final d = defaultStockQty(cur, p);
      _stockQty.text = _num(d);
    });
  }

  Future<void> _pickProduct() async {
    final p = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (_) => _ProductPicker(products: _products, suggest: _suggest ?? suggestProduct(_name.text, _products)),
    );
    if (p != null && mounted) _choose(p);
  }

  Future<void> _newProduct() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, '先填品名', error: true);
      return;
    }
    setState(() => _creating = true);
    final p = await widget.createProduct(name, _unit.text.trim().isEmpty ? '個' : _unit.text.trim());
    if (!mounted) return;
    setState(() {
      _creating = false;
      if (p != null) _products = [..._products, p];
    });
    if (p != null) _choose(p);
  }

  void _done() {
    final name = _name.text.trim();
    final qty = _parse(_qty.text);
    if (name.isEmpty) return showMessage(context, '請填品名', error: true);
    if (qty == null || qty <= 0) return showMessage(context, '數量要大於 0', error: true);
    if (_mode == null) return showMessage(context, '請選擇要不要入庫存', error: true);
    final sq = _parse(_stockQty.text);
    if (_mode == _Stock.product && (sq == null || sq <= 0)) {
      return showMessage(context, '請填要${widget.isReturn ? '扣掉' : '加進'}庫存幾${_product?.unit ?? ''}', error: true);
    }
    final price = _parse(_price.text);
    Navigator.pop(
      context,
      ItemSaved(PurchaseItem(
        name: name,
        qty: qty,
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        unitPrice: price == null ? null : round2(price),
        productId: _mode == _Stock.product ? _product?.id : null,
        stockQty: _mode == _Stock.product ? sq : null,
        source: widget.item.source,
        sure: true, // 店員看過、按完成＝已核對
        decided: true,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verb = widget.isReturn ? '扣掉' : '加進';
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
              onChanged: (v) {
                if (_product == null) setState(() => _suggest = suggestProduct(v, _products));
              },
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
            Text('$verb庫存', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_mode == _Stock.product && _product != null) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.good.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(children: [
                  Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.good),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${_product!.name}（${_product!.unit}）', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  TextButton(onPressed: _pickProduct, child: const Text('換一個')),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stockQty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  labelText: '$verb庫存幾${_product!.unit}',
                  suffixText: _product!.unit,
                  helperText: _unit.text.trim().isNotEmpty && _unit.text.trim() != _product!.unit
                      ? '單位不同（單上是${_unit.text.trim()}），請換算成${_product!.unit}'
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _mode = _Stock.none),
                  child: const Text('改成不入庫存'),
                ),
              ),
            ] else ...[
              if (_suggest != null && _mode != _Stock.none)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _choose(_suggest!),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text('建議：${_suggest!.name}（${_suggest!.unit}）'),
                  ),
                ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickProduct,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('選庫存品項'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _creating ? null : _newProduct,
                    icon: _creating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add, size: 18),
                    label: const Text('新增成品項'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              _NoneChoice(selected: _mode == _Stock.none, onTap: () => setState(() => _mode = _Stock.none)),
            ],
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

class _NoneChoice extends StatelessWidget {
  const _NoneChoice({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? AppColors.primary : AppColors.line),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18, color: selected ? AppColors.primary : AppColors.muted),
            const SizedBox(width: 10),
            const Expanded(child: Text('不入庫存（冰塊、清潔用品、耗材…）')),
          ]),
        ),
      );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products, this.suggest});
  final List<Product> products;
  final Product? suggest;
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.products.where((p) => q.isEmpty || p.name.toLowerCase().contains(q)).toList();
    final s = widget.suggest;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('選庫存品項', style: TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜尋', isDense: true),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('沒有符合的品項', style: TextStyle(color: AppColors.muted)))
                : ListView(children: [
                    if (s != null && q.isEmpty)
                      ListTile(
                        leading: Icon(Icons.auto_awesome_outlined, color: AppColors.primary),
                        title: Text(s.name),
                        subtitle: Text('建議・${s.category}・${s.unit}', style: const TextStyle(fontSize: AppType.small)),
                        onTap: () => Navigator.pop(context, s),
                      ),
                    for (final p in list)
                      if (!(s != null && q.isEmpty && p.id == s.id))
                        ListTile(
                          title: Text(p.name),
                          subtitle: Text('${p.category}・${p.unit}', style: const TextStyle(fontSize: AppType.small)),
                          onTap: () => Navigator.pop(context, p),
                        ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
