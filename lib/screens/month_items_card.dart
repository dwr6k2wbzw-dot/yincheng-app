// 本月進貨總表（老闆 2026-11-01）：進貨頁下方，列出本月進了哪些品項、數量、單價、總金額
// 資料來自進貨的品項明細（0087：拍照辨識或手動填的）；日報表帶入的進貨沒有品項明細。
import 'package:flutter/material.dart';

import '../data/purchase_items_math.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'stock_counts_screen.dart' show fmtQty;

class MonthItemsCard extends StatefulWidget {
  const MonthItemsCard({super.key, required this.rows, this.error = false});
  final List<ItemSummary> rows;
  final bool error;
  @override
  State<MonthItemsCard> createState() => _MonthItemsCardState();
}

class _MonthItemsCardState extends State<MonthItemsCard> {
  static const _fold = 10; // 超過就先收起來
  bool _all = false;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final q = _q.toLowerCase();
    final hit = q.isEmpty ? rows : rows.where((r) => r.name.toLowerCase().contains(q)).toList();
    final shown = _all || q.isNotEmpty ? hit : hit.take(_fold).toList();
    final total = round2(rows.fold<double>(0, (t, r) => t + r.total));
    final muted = TextStyle(color: AppColors.muted, fontSize: AppType.caption);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.receipt_long_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('本月進貨總表', style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppType.title))),
          if (rows.isNotEmpty) Text('${rows.length} 項', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        ]),
        const SizedBox(height: 4),
        Text(
          widget.error
              ? '品項明細暫時讀不到，下拉可以重新整理'
              : rows.isEmpty
                  ? '這個月還沒有品項明細。新增進貨時拍送貨單，就會自動列出品項、數量和單價。'
                  : '只算有品項明細的進貨（拍照辨識或手動填的），不含運費、稅等差額；日報表帶入的進貨沒有品項',
          style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.45),
        ),
        if (rows.isNotEmpty) ...[
          if (rows.length > _fold) ...[
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: '搜尋品項', isDense: true),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ],
          const SizedBox(height: 12),
          // 表頭
          Row(children: [
            Expanded(flex: 5, child: Text('品項', style: muted)),
            Expanded(flex: 3, child: Text('數量', style: muted, textAlign: TextAlign.right)),
            Expanded(flex: 3, child: Text('單價', style: muted, textAlign: TextAlign.right)),
            Expanded(flex: 4, child: Text('金額', style: muted, textAlign: TextAlign.right)),
          ]),
          const SizedBox(height: 6),
          Divider(height: 1, color: AppColors.line),
          for (final r in shown) _row(r),
          if (hit.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('沒有符合的品項', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            ),
          if (q.isEmpty && rows.length > _fold)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? '收起' : '看全部 ${rows.length} 項'),
              ),
            ),
          Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('品項合計', style: TextStyle(color: AppColors.muted, fontSize: AppType.small))),
            Text(ntd(total),
                style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.label, fontFeatures: tabular)),
          ]),
          const SizedBox(height: 4),
        ],
      ]),
    );
  }

  Widget _row(ItemSummary r) {
    final num = TextStyle(fontFeatures: tabular, fontSize: AppType.small, color: r.qty < 0 ? AppColors.bad : null);
    final price = r.unitPrice;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 5,
          child: Text(r.name,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppType.small, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 3,
          child: Text('${fmtQty(r.qty)}${r.unit ?? ''}', textAlign: TextAlign.right, style: num),
        ),
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(price == null ? '—' : ntd(price), textAlign: TextAlign.right, style: num),
            if (r.priceVaries)
              Text('平均', style: TextStyle(color: AppColors.muted, fontSize: AppType.micro)),
          ]),
        ),
        Expanded(
          flex: 4,
          child: Text(ntd(r.total), textAlign: TextAlign.right, style: num.copyWith(fontWeight: AppFont.label)),
        ),
      ]),
    );
  }
}
