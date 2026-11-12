import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme.dart';
import 'format.dart';
import 'revenue_colors.dart';

/// 品項分「酒水」「餐食」兩區：每區標題列有小計與份數，區內依金額排序，前 [top] 名、可展開全部。
/// 每日營收卡片與「當月銷售品項累計」共用。
class ItemSections extends StatelessWidget {
  const ItemSections({super.key, required this.items, this.top = 3});
  final List<ItemSale> items;
  final int top;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final drink in [true, false])
          if (items.any((x) => x.isDrink == drink))
            _ItemSection(
                key: ValueKey(drink),
                title: drink ? '酒水' : '餐食',
                color: drink ? AppColors.primary : ramenColor,
                items: [for (final x in items) if (x.isDrink == drink) x],
                top: top),
      ]);
}

class _ItemSection extends StatefulWidget {
  const _ItemSection({super.key, required this.title, required this.color, required this.items, required this.top});
  final String title;
  final Color color;
  final List<ItemSale> items;
  final int top;
  @override
  State<_ItemSection> createState() => _ItemSectionState();
}

class _ItemSectionState extends State<_ItemSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final list = widget.items;
    final shown = _open ? list : list.take(widget.top).toList();
    final qty = list.fold<double>(0, (a, x) => a + x.qty);
    final total = list.fold<double>(0, (a, x) => a + x.amount);
    const num = [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.circle, size: 8, color: widget.color),
          const SizedBox(width: 6),
          Text(widget.title, style: const TextStyle(fontSize: AppType.small, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('${list.length} 項・${_n(qty)} 份', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
          const Spacer(),
          Text('小計 ${ntd(total)}',
              style: const TextStyle(fontSize: AppType.small, fontWeight: FontWeight.w600, fontFeatures: num)),
        ]),
        const SizedBox(height: 4),
        for (var i = 0; i < shown.length; i++) _row(i + 1, shown[i]),
        if (list.length > widget.top)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                  minimumSize: const Size(44, 40),
                  foregroundColor: AppColors.muted),
              onPressed: () => setState(() => _open = !_open),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_open ? '收起' : '全部 ${list.length} 項', style: const TextStyle(fontSize: AppType.small)),
                const SizedBox(width: 2),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _row(int rank, ItemSale x) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
            width: 22,
            child: Text('$rank',
                style: TextStyle(
                    color: AppColors.muted,
                    fontSize: AppType.caption,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Expanded(
            child: Text(x.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppType.small)),
          ),
          Text('× ${_n(x.qty)}',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          SizedBox(
            width: 84,
            child: Text(ntd(x.amount),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: AppType.small, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]),
      );
}

String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
