import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/repository.dart' show friendlyError;
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
    // 以分加總（不用浮點直接加），小計＝畫面上各列金額的和
    final total = list.fold<int>(0, (a, x) => a + (x.amount * 100).round()) / 100;
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
          Text('小計 ${ntdExact(total)}',
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
            child: Text(ntdExact(x.amount),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: AppType.small, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ]),
      );
}

String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// 當月銷售品項累計（老闆 2026-11-13）：當月到昨天、含服務費，分酒水／餐食兩區；
/// 沒有 iCHEF 資料（但有收入）的日子用警告色列出「未計入」。卡片外框由營收頁的 SectionCard 包。
class MonthItemsCard extends StatelessWidget {
  const MonthItemsCard({super.key, required this.month, required this.items, required this.ichefDays, this.missing = const []});
  final DateTime month;
  final List<ItemSale> items;
  final Set<DateTime> ichefDays;
  final List<DateTime> missing;

  /// 當月、在今天之前、有收入、但沒有 iCHEF 資料的營業日
  static List<DateTime> missingDays(List<RevenueEntry> entries, Set<DateTime> ichef, DateTime month, DateTime today) => [
        for (final e in entries)
          if (e.bizDate.year == month.year &&
              e.bizDate.month == month.month &&
              e.bizDate.isBefore(today) &&
              e.received > 0 &&
              !ichef.contains(DateTime(e.bizDate.year, e.bizDate.month, e.bizDate.day)))
            DateTime(e.bizDate.year, e.bizDate.month, e.bizDate.day)
      ]..sort();

  /// 11/1、11/2、11/3、11/5 → 11/1～11/3、11/5
  static String ranges(List<DateTime> ds) {
    if (ds.isEmpty) return '';
    final f = DateFormat('M/d');
    final out = <String>[];
    var start = ds.first, prev = ds.first;
    for (final d in [...ds.skip(1), null]) {
      if (d != null && d.difference(prev).inDays == 1) {
        prev = d;
        continue;
      }
      out.add(start == prev ? f.format(start) : '${f.format(start)}～${f.format(prev)}');
      if (d != null) start = prev = d;
    }
    return out.join('、');
  }

  @override
  Widget build(BuildContext context) {
    final days = ichefDays.where((d) => d.year == month.year && d.month == month.month).toList()..sort();
    final muted = TextStyle(color: AppColors.muted, fontSize: AppType.small);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${month.month} 月銷售品項累計', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
              'iCHEF ${days.length} 天${days.isEmpty ? '' : '・到 ${DateFormat('M/d').format(days.last)}'}'
              '・金額含服務費・每天早上更新',
              style: muted),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('未計入（那天沒有 iCHEF 資料）：${ranges(missing)}',
                style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
          ],
          ItemSections(items: items, top: 5),
        ]);
  }
}

/// 月累計載入器（營收頁傳 repo.monthItemSales；測試傳假的）
typedef MonthItemsLoader = Future<List<ItemSale>> Function(String storeId, DateTime month);

/// 營收頁的「當月銷售品項累計」區塊（審查 P2）：
/// 店家、[version]（營收頁每次下拉更新／存檔後 +1）或月份（跨月）一變就重新查詢；
/// 查詢失敗顯示錯誤和「重試」，不再當成沒有資料。外框由 [wrap] 包（營收頁傳 SectionCard）。
class MonthItemsSection extends StatefulWidget {
  const MonthItemsSection({
    super.key,
    required this.storeId,
    required this.version,
    required this.load,
    required this.entries,
    required this.ichef,
    this.today,
    this.wrap,
  });
  final String storeId;
  final int version;
  final MonthItemsLoader load;
  final List<RevenueEntry> entries;
  final Set<DateTime> ichef;

  /// 營業日的今天（測試可指定；預設 bizToday()）
  final DateTime Function()? today;
  final Widget Function(Widget child)? wrap;

  @override
  State<MonthItemsSection> createState() => _MonthItemsSectionState();
}

class _MonthItemsSectionState extends State<MonthItemsSection> {
  Future<List<ItemSale>>? _future;
  Object? _key;
  late DateTime _month;

  DateTime get _today => (widget.today ?? bizToday)();

  /// 到昨天為止：1 號看的是上個月
  DateTime _monthOf(DateTime today) {
    final y = today.subtract(const Duration(days: 1));
    return DateTime(y.year, y.month);
  }

  void _ensure({bool force = false}) {
    final month = _monthOf(_today);
    final key = (widget.storeId, widget.version, month);
    if (!force && key == _key) return;
    _key = key;
    _month = month;
    _future = widget.load(widget.storeId, month);
  }

  @override
  Widget build(BuildContext context) {
    _ensure(); // 店家、版本、月份沒變就沿用上一次的查詢
    return FutureBuilder<List<ItemSale>>(
      future: _future,
      builder: (context, snap) {
        final wrap = widget.wrap ?? (w) => w;
        if (snap.hasError) {
          return wrap(Row(children: [
            Icon(Icons.error_outline, color: AppColors.bad, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${_month.month} 月銷售品項累計載入失敗：${friendlyError(snap.error!)}',
                  style: const TextStyle(fontSize: AppType.small)),
            ),
            TextButton(onPressed: () => setState(() => _ensure(force: true)), child: const Text('重試')),
          ]));
        }
        final list = snap.data;
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        return wrap(MonthItemsCard(
          month: _month,
          items: list,
          ichefDays: widget.ichef,
          missing: MonthItemsCard.missingDays(widget.entries, widget.ichef, _month, _today),
        ));
      },
    );
  }
}
