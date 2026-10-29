import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../services/load_timing.dart';
import '../data/month_compare.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
// 匯出損益表用的 Excel 工具很大：按「匯出」時才下載（老闆 2026-10-16：加快打開速度）
import '../services/pl_export.dart' deferred as pl;
import '../widgets/revenue_mix.dart';
import 'reservations_screen.dart';

/// 營運總覽（PRD 畫面 01）。老闆／店長看營收與成本；員工版只顯示零用金與快速操作（營收由資料庫權限隱藏）。
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardData {
  MonthlySummary? summary;
  FixedCosts fixed = const FixedCosts();
  double? petty;
  List<ExpenseItem> items = const [];
  List<RecurringExpenseItem> recurring = const []; // 每月固定支出（0039）
  double cardFeeRate = 0.02; // 刷卡手續費率（0039）
  DateTime month = DateTime.now();
  List<DailyRevenue> days = const []; // 本月與上個月每日營收（趨勢線、較上月同期）
  /// 前 3 個月的月彙總（[0]＝上個月；上個月／近 3 個月平均的來客與客單，老闆 2026-10-29）；讀不到的月份＝null
  List<MonthlySummary?> prev = const [];

  /// 本月累計 vs 上月累計；較上月同期＝本月 1～N 日 ÷ 上月 1～N 日（N＝本月最後有資料的那天）
  _Trend trend() {
    final dim = DateTime(month.year, month.month + 1, 0).day;
    final prevMonth = DateTime(month.year, month.month - 1);
    final prevDim = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
    final cur = List<double>.filled(dim, 0), prev = List<double>.filled(prevDim, 0);
    var lastDay = 0;
    for (final r in days) {
      if (r.date.year == month.year && r.date.month == month.month) {
        cur[r.date.day - 1] += r.revenue;
        if (r.revenue != 0 && r.date.day > lastDay) lastDay = r.date.day;
      } else if (r.date.year == prevMonth.year && r.date.month == prevMonth.month) {
        prev[r.date.day - 1] += r.revenue;
      }
    }
    if (lastDay == 0) return _Trend(const [], const [], dim, null);
    List<double> cum(List<double> v, int n) {
      var t = 0.0;
      return [for (var i = 0; i < n; i++) t += v[i]];
    }
    final c = cum(cur, lastDay);
    final p = cum(prev, prevDim);
    final prevSame = p.isEmpty ? 0.0 : p[(lastDay < prevDim ? lastDay : prevDim) - 1];
    return _Trend(c, p, dim, prevSame > 0 ? c.last / prevSame - 1 : null);
  }

  double itemsOf(String category) => items.where((e) => e.category == category).fold(0.0, (a, e) => a + e.amount);
  double recurringOf(String category) =>
      recurring.where((e) => e.category == category).fold(0.0, (a, e) => a + e.amount);
  /// 這個月有沒有舊版手動輸入的「刷卡手續費」明細（0037 舊 UI 可能已輸入過）
  bool get hasManualCardFee => items.any((e) => e.name.trim() == '刷卡手續費');
  /// 當月刷卡手續費＝刷卡金額 × 費率（歸雜項）。
  /// 若該月已有手動輸入的「刷卡手續費」明細，則自動費用不計（避免與舊資料重複計算）。
  double cardFee(MonthlySummary s) => hasManualCardFee ? 0 : s.card * cardFeeRate;
  /// 老闆視角：加進雜項的手動金額＝一次性雜項＋每月固定雜項＋刷卡手續費
  double ownerMiscAdd(MonthlySummary s) => itemsOf('misc') + recurringOf('misc') + cardFee(s);
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _initial = _peek();
    _future = _load();
  }

  /// 手機裡存的上次資料（打開先顯示，背景再更新；老闆 2026-10-16）。缺任何一塊就不用（避免損益算錯）。
  _DashboardData? _initial;
  _DashboardData? _peek() {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final d = _DashboardData()..month = _month;
    if (widget.membership.isPartTime) return d;
    if (!widget.membership.canSeeRevenue) {
      final p = repo.peekPettyCashBalance(id);
      if (p == null) return null;
      d.petty = p.$1;
      return d;
    }
    final s = repo.peekMonthlySummary(id, _month);
    if (s == null) return null;
    d.summary = s;
    d.days = repo.peekDailyRevenueBetween(id, DateTime(_month.year, _month.month - 1, 1), DateTime(_month.year, _month.month + 1, 0)) ??
        const <DailyRevenue>[];
    d.prev = [for (var i = 1; i <= 3; i++) repo.peekMonthlySummary(id, DateTime(_month.year, _month.month - i))];
    if (_isOwner) {
      final fixed = repo.peekFixedCosts(id, _month);
      final items = repo.peekExpenseItems(id, _month);
      final recurring = repo.peekRecurringExpenseItems(id);
      final rate = repo.peekCardFeeRate(id);
      if (fixed == null || items == null || recurring == null || rate == null) return null;
      d.fixed = fixed;
      d.items = items;
      d.recurring = recurring;
      d.cardFeeRate = rate;
    }
    return d;
  }

  Future<_DashboardData> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final d = _DashboardData()..month = _month;
    if (widget.membership.isPartTime) return d; // 兼職只看交接、提醒
    if (!widget.membership.canSeeRevenue) d.petty = await repo.pettyCashBalance(id);
    if (widget.membership.canSeeRevenue) {
      // 全部同時查（原本老闆要一個等一個查 5 次）
      final r = await Future.wait<dynamic>([
        repo.monthlySummary(id, _month),
        // 趨勢線用；讀不到不影響總覽
        repo
            .dailyRevenueBetween(id, DateTime(_month.year, _month.month - 1, 1), DateTime(_month.year, _month.month + 1, 0))
            .then<List<DailyRevenue>>((v) => v, onError: (_) => const <DailyRevenue>[]),
        // 上個月／近 3 個月平均用；讀不到不影響總覽
        Future.wait([
          for (var i = 1; i <= 3; i++)
            repo
                .monthlySummary(id, DateTime(_month.year, _month.month - i))
                .then<MonthlySummary?>((v) => v, onError: (_) => null),
        ]),
        if (_isOwner) ...[
          repo.fixedCosts(id, _month),
          repo.expenseItems(id, _month),
          repo.recurringExpenseItems(id),
          repo.cardFeeRate(id),
        ],
      ]);
      d.summary = r[0] as MonthlySummary;
      d.days = r[1] as List<DailyRevenue>;
      d.prev = r[2] as List<MonthlySummary?>;
      if (_isOwner) {
        d.fixed = r[3] as FixedCosts;
        d.items = r[4] as List<ExpenseItem>;
        d.recurring = r[5] as List<RecurringExpenseItem>;
        d.cardFeeRate = r[6] as double;
      }
    }
    markLoad('總覽資料');
    return d;
  }

  int _gen = 0; // 每次重新整理加 1，讓訂位卡片跟著重讀
  void _reload() => setState(() {
        _gen++;
        _initial = _peek();
        _future = _load();
      });

  bool get _isOwner => widget.membership.role == Role.owner;

  Future<void> _editFixed(DateTime month, String category, String label, double? current) async {
    final ctrl = TextEditingController(text: current == null ? '' : current.round().toString());
    final v = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${DateFormat('M 月', 'zh_TW').format(month)}$label'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
          decoration: const InputDecoration(prefixText: '\$ ', labelText: '金額（元）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text)), child: const Text('儲存')),
        ],
      ),
    );
    if (v == null || !mounted) return;
    try {
      await AppScope.of(context).repo.saveFixedCost(widget.membership.storeId, month, category, v);
      if (mounted) showMessage(context, '已儲存$label');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  void _shiftMonth(int delta) {
    _month = DateTime(_month.year, _month.month + delta);
    _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_DashboardData>(
        key: ValueKey(_gen), // 換月份／重新整理：重新從上次資料開始
        future: _future,
        initialData: _initial,
        builder: (context, snap) {
          // 讀不到最新資料但有上次的：照樣顯示上次的，最上面提示
          final offline = snap.hasError && _initial != null;
          if (snap.hasError && !offline) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
          if (!snap.hasData && !offline) return const Center(child: CircularProgressIndicator());
          final d = offline ? _initial! : snap.data!;
          final updating = !offline && snap.connectionState != ConnectionState.done;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              // 先顯示上次的資料時，最上面一條細線表示正在更新
              if (offline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('連不上資料庫，先顯示上次的資料（下拉可重試）', style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
                ),
              if (updating)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: LinearProgressIndicator(minHeight: 2, color: AppColors.primary, backgroundColor: AppColors.line),
                  ),
                ),
              if (widget.membership.isPartTime) ...[
                // 0065（老闆 2026-10-19）：訂位所有成員都看得到
                ReservationSummaryCard(key: ValueKey('rs-${widget.membership.storeId}-$_gen'), membership: widget.membership),
                const SizedBox(height: 12),
                Text('兼職帳號：可以看訂位、班表、交接與提醒。點右上角小鈴鐺左邊的「交接・提醒」圖示寫交接、打勾提醒。',
                    style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.5)),
              ] else if (widget.membership.canSeeRevenue)
                ..._managerView(d)
              else
                ..._staffView(d),
            ]),
          );
        },
      );

  List<Widget> _staffView(_DashboardData d) => [
        ReservationSummaryCard(key: ValueKey('rs-${widget.membership.storeId}-$_gen'), membership: widget.membership),
        const SizedBox(height: 12),
        SectionCard(
          child: Text('這個身分看不到營收與成本分析。\n可以在下方分頁記錄進貨與盤點。',
              style: TextStyle(color: AppColors.muted, height: 1.5)),
        ),
        const SizedBox(height: 12),
        StatTile(label: '零用金結餘', value: d.petty == null ? '—' : ntd(d.petty!)),
      ];

  List<Widget> _managerView(_DashboardData d) {
    final s = d.summary!;
    final multi = isMultiLineStore(widget.membership.storeName);
    final parts = revenueParts(widget.membership.storeName,
        drinks: s.drinksRevenue, food: s.foodRevenue, project: s.projectAmount,
        coffee: s.coffeeRevenue, ramen: s.ramenRevenue, deposit: s.deposit);
    // 小城外的客單＝調酒收入 ÷ 來客數（與小城外 Excel 相同）
    final cocktail = s.drinksRevenue + s.foodRevenue + s.projectAmount;
    final avgTicket = multi ? (s.guests > 0 ? cocktail / s.guests : null) : s.avgTicket;
    final gold = AppColors.p.style == DashboardStyle.gold;
    // 雜項：老闆＝進貨雜項＋手動雜項支出＋每月固定雜項＋刷卡手續費（老闆 2026-10-11）；員工看進貨口徑
    final miscAmt = s.miscCost + (_isOwner ? d.ownerMiscAdd(s) : 0);
    final miscRate = s.revenue > 0 ? miscAmt / s.revenue : null;
    final noCost = !s.hasCostRecords && s.revenue > 0 && !(_isOwner && d.ownerMiscAdd(s) != 0);
    final costNote = (multi
            ? '餐食含咖啡吧、拉麵食材（10 月起）；總進貨含咖啡吧與拉麵；雜項 ÷ 營業收入，不計入總進貨'
            : '雜項＝雜項類進貨（含以前的零用金-其他雜支、酒水副材料-雜項）÷ 營業收入；不計入總進貨') +
        (_isOwner ? '；老闆另含手動支出、每月固定與刷卡手續費' : '');
    final reservation =
        ReservationSummaryCard(key: ValueKey('rs-${widget.membership.storeId}-$_gen'), membership: widget.membership, compact: !gold);
    final trend = d.trend();
    final cmp = _compareSides(d, multi);
    final avgText = avgTicket == null ? '—' : money.format(avgTicket.round());
    final avgSub = multi
        ? '調酒收入 ÷ 來客數'
        : s.dailyAvgTicket != null && s.dailyAvgTicket != s.avgTicket ? '不含活動 ${ntd(s.dailyAvgTicket!)}' : null;

    if (gold) {
      // ── A 沉穩黑金（小城外）──
      return [
        Row(children: [
          IconButton(tooltip: '上個月', onPressed: () => _shiftMonth(-1), icon: Icon(Icons.chevron_left, color: AppColors.muted)),
          Expanded(
            child: Text('${d.month.year} · ${d.month.month} 月',
                textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.body, letterSpacing: 3, color: AppColors.text)),
          ),
          IconButton(tooltip: '下個月', onPressed: () => _shiftMonth(1), icon: Icon(Icons.chevron_right, color: AppColors.muted)),
        ]),
        const SizedBox(height: 6),
        reservation,
        const SizedBox(height: 14),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _label('本月營收')),
              if (trend.delta != null) _delta(trend.delta!, suffix: ' 較上月同期'),
            ]),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('NT\$ ', style: TextStyle(fontSize: AppType.title, color: AppColors.primary)),
                Text(money.format(s.revenue),
                    style: const TextStyle(fontSize: AppType.hero, fontWeight: FontWeight.w500, letterSpacing: -1, fontFeatures: tabular)),
              ]),
            ),
            if (trend.cumulative.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: CustomPaint(painter: _TrendPainter(trend, AppColors.primary, AppColors.muted.withValues(alpha: 0.45), AppColors.line)),
              ),
              const SizedBox(height: 4),
              Row(children: [
                Container(width: 10, height: 2, color: AppColors.primary),
                const SizedBox(width: 4),
                Text('本月累計', style: TextStyle(fontSize: AppType.caption, color: AppColors.muted)),
                const SizedBox(width: 12),
                Container(width: 10, height: 2, color: AppColors.muted.withValues(alpha: 0.45)),
                const SizedBox(width: 4),
                Text('上月', style: TextStyle(fontSize: AppType.caption, color: AppColors.muted)),
              ]),
            ],
            const SizedBox(height: 14),
            Divider(height: 1, color: AppColors.line),
            const SizedBox(height: 14),
            Row(children: [
              _figure('現金', s.cash),
              _figure('刷卡', s.card),
              if (!multi) _figure('訂金', s.deposit),
            ]),
            const SizedBox(height: 14),
            Row(children: [for (final p in parts) _amount(p.label, p.amount, p.color)]),
            const SizedBox(height: 10),
            MixBar(parts: parts, height: 4),
            const SizedBox(height: 16),
            _target(s),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: StatTile(label: '來客數', value: money.format(s.guests), unit: '人', trailing: cmp.guests)),
          const SizedBox(width: 14),
          Expanded(child: StatTile(label: '客單價', value: avgText, unit: avgTicket == null ? null : '元', sub: avgSub, trailing: cmp.ticket)),
        ]),
        const SizedBox(height: 14),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(child: _label('進貨成本率')),
              if (!noCost) Text(pct(s.totalCostRate), style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w500, fontFeatures: tabular)),
            ]),
            if (!noCost) Text('總進貨 ${ntd(s.totalCost.round())}', textAlign: TextAlign.right,
                style: TextStyle(fontSize: AppType.caption, color: AppColors.muted)),
            const SizedBox(height: 12),
            if (noCost)
              Text('本月尚無進貨資料', style: TextStyle(color: AppColors.warn))
            else ...[
              _rateBar('酒水', s.drinkCostRate, s.drinkCost, AppColors.primary),
              _rateBar('餐食', s.foodCostRate, s.foodCost, ramenColor),
              _rateBar('雜項', miscRate, miscAmt, coffeeColor),
            ],
            const SizedBox(height: 4),
            Text(costNote, style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
          ]),
        ),
        const SizedBox(height: 14),
        if (_isOwner) _profitCard(d, s),
      ];
    }

    // ── C 品牌色系（隱城）──
    final profit = _isOwner ? _profitOf(d, s) : null;
    final pal = AppColors.p;
    return [
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
        decoration: BoxDecoration(color: pal.hero, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${d.month.year} 年 ${d.month.month} 月營收', style: TextStyle(fontSize: AppType.small, color: pal.heroMuted))),
            _roundArrow(Icons.chevron_left, '上個月', () => _shiftMonth(-1)),
            const SizedBox(width: 6),
            _roundArrow(Icons.chevron_right, '下個月', () => _shiftMonth(1)),
          ]),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(ntd(s.revenue),
                style: TextStyle(fontSize: AppType.hero, fontWeight: FontWeight.w600, letterSpacing: -1, color: pal.text, fontFeatures: tabular)),
          ),
          if (trend.delta != null) _delta(trend.delta!, suffix: ' 較上月同期', muted: pal.heroMuted),
          const SizedBox(height: 16),
          _target(s, track: pal.heroTrack, muted: pal.heroMuted),
        ]),
      ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
        children: [
          reservation,
          if (profit != null)
            _tile('本月損益', _short(profit), color: profit >= 0 ? AppColors.good : AppColors.bad,
                sub: s.revenue > 0 ? '占營收 ${pct(profit / s.revenue)}' : null)
          else
            _tile('目標達成', s.targetRate == null ? '—' : pct(s.targetRate), sub: s.targetAmount == null ? '尚未設定目標' : null),
          _tile('來客數', money.format(s.guests), unit: '人', trailing: cmp.guests),
          _tile('客單價', avgText, unit: avgTicket == null ? null : '元', sub: avgSub, trailing: cmp.ticket),
        ],
      ),
      const SizedBox(height: 12),
      SectionCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(child: _label('進貨成本率')),
            if (!noCost) ...[
              Text('總計 ', style: TextStyle(fontSize: AppType.small, color: AppColors.muted)),
              Text(pct(s.totalCostRate), style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w600, fontFeatures: tabular)),
            ],
          ]),
          const SizedBox(height: 16),
          if (noCost)
            Text('本月尚無進貨資料', style: TextStyle(color: AppColors.warn))
          else
            Row(children: [
              _ring('酒水', s.drinkCostRate, s.drinkCost, AppColors.primary),
              _ring('餐食', s.foodCostRate, s.foodCost, AppColors.warn),
              _ring('雜項', miscRate, miscAmt, AppColors.muted),
            ]),
          const SizedBox(height: 12),
          Text(costNote, style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('營收組成'),
          const SizedBox(height: 10),
          for (final p in parts) _kv(p.label, p.amount, dot: p.color),
          const SizedBox(height: 8),
          MixBar(parts: parts, height: 6),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 10),
          _kv('刷卡', s.card),
          _kv('現金', s.cash),
          if (s.deposit != 0) _kv('訂金', s.deposit),
        ]),
      ),
      const SizedBox(height: 12),
      if (_isOwner) _profitCard(d, s),
    ];
  }

  /// 來客數／客單價框右邊的小字：上月、近 3 個月平均（老闆 2026-10-29）。跟著上方月份走；
  /// 近 3 月＝前 3 個完整月份（不含本月），來客取每月平均、客單依來客加權，沒資料的月份不算。
  ({Widget? guests, Widget? ticket}) _compareSides(_DashboardData d, bool multi) {
    if (d.prev.every((e) => e == null)) return (guests: null, ticket: null);
    final last = d.prev.first == null ? null : monthFigure(d.prev.first!, multi: multi);
    final avg = monthAverage([for (final p in d.prev) if (p != null) monthFigure(p, multi: multi)]);
    String n(num? v) => v == null || v == 0 ? '—' : money.format(v.round());
    Widget side(String a, String b, String unit) {
      final st = TextStyle(fontSize: AppType.caption, color: AppColors.muted, fontFeatures: tabular, height: 1.5);
      return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text('上月 $a${a == '—' ? '' : unit}', style: st),
        Text('近3月 $b${b == '—' ? '' : unit}', style: st),
      ]);
    }
    return (
      guests: side(n(last?.guests), n(avg.guests), '人'),
      ticket: side(n(last?.avgTicket), n(avg.avgTicket), '元'),
    );
  }

  // ── 共用小元件 ──
  Widget _label(String t) => Text(t, style: TextStyle(fontSize: AppType.small, color: AppColors.muted, letterSpacing: 2));

  Widget _delta(double v, {String suffix = '', Color? muted}) {
    final up = v >= 0;
    final c = up ? AppColors.good : AppColors.bad;
    return Text.rich(TextSpan(children: [
      TextSpan(text: '${up ? '▲' : '▼'} ${(v.abs() * 100).toStringAsFixed(1)}%',
          style: TextStyle(color: c, fontWeight: FontWeight.w600, fontFeatures: tabular)),
      TextSpan(text: suffix, style: TextStyle(color: muted ?? AppColors.muted)),
    ]), style: const TextStyle(fontSize: AppType.small));
  }

  Widget _figure(String label, double v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money.format(v), style: const TextStyle(fontSize: AppType.body, fontFeatures: tabular)),
          ),
        ]),
      );

  Widget _target(MonthlySummary s, {Color? track, Color? muted}) {
    if (s.targetAmount == null) {
      return Text('尚未設定本月營收目標', style: TextStyle(color: muted ?? AppColors.muted, fontSize: AppType.small));
    }
    return Column(children: [
      Row(children: [
        Expanded(child: Text('目標 ${money.format(s.targetAmount!)}', style: TextStyle(fontSize: AppType.caption, color: muted ?? AppColors.muted))),
        Text('達成 ${pct(s.targetRate)}', style: TextStyle(fontSize: AppType.caption, color: AppColors.primary, fontFeatures: tabular)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: LinearProgressIndicator(
          value: (s.targetRate ?? 0).clamp(0.0, 1.0),
          minHeight: 5,
          backgroundColor: track ?? AppColors.line,
          color: AppColors.primary,
        ),
      ),
    ]);
  }

  Widget _rateBar(String label, double? rate, double amount, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(children: [
          Row(children: [
            Text(label, style: const TextStyle(fontSize: AppType.small)),
            const SizedBox(width: 8),
            Expanded(child: Text(ntd(amount.round()), style: TextStyle(fontSize: AppType.caption, color: AppColors.muted, fontFeatures: tabular))),
            Text(pct(rate), style: const TextStyle(fontSize: AppType.body, fontFeatures: tabular)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              // 50% 畫滿
              value: ((rate ?? 0) / 0.5).clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: AppColors.line,
              color: color,
            ),
          ),
        ]),
      );

  Widget _ring(String label, double? rate, double amount, Color color) => Expanded(
        child: Column(children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 76,
                height: 76,
                child: CircularProgressIndicator(
                  value: (rate ?? 0).clamp(0.0, 1.0),
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.line,
                  color: color,
                ),
              ),
              Text(rate == null ? '—' : (rate * 100).toStringAsFixed(1),
                  style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w600, fontFeatures: tabular)),
            ]),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: AppType.small)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(ntd(amount.round()), style: TextStyle(fontSize: AppType.caption, color: AppColors.muted, fontFeatures: tabular)),
          ),
        ]),
      );

  Widget _tile(String label, String value, {Color? color, String? sub, Widget? trailing, String? unit}) => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: TextStyle(fontSize: AppType.small, color: AppColors.muted)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            (trailing == null ? (Widget c) => Expanded(child: c) : (Widget c) => Flexible(child: c))(
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: value),
                  if (unit != null)
                    TextSpan(text: ' $unit', style: TextStyle(fontSize: AppType.small, fontWeight: FontWeight.w400, color: AppColors.muted)),
                ]), style: TextStyle(fontSize: AppType.display, fontWeight: FontWeight.w600, color: color, fontFeatures: tabular)),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: trailing))],
          ]),
          if (sub != null)
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppType.caption, color: AppColors.muted)),
        ]),
      );

  Widget _kv(String k, double v, {Color? dot}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          if (dot != null) ...[Icon(Icons.circle, size: 8, color: dot), const SizedBox(width: 8)],
          Expanded(child: Text(k, style: const TextStyle(fontSize: AppType.body))),
          Text(money.format(v), style: const TextStyle(fontSize: AppType.body, fontFeatures: tabular)),
        ]),
      );

  Widget _roundArrow(IconData icon, String tip, VoidCallback onTap) => SizedBox(
        width: 36,
        height: 36,
        child: IconButton.filled(
          tooltip: tip,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(backgroundColor: AppColors.p.heroTrack, foregroundColor: AppColors.p.heroMuted),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
        ),
      );

  /// 金額縮寫：+92,140 → +9.2萬
  String _short(double v) {
    final sign = v < 0 ? '−' : '+';
    final a = v.abs();
    if (a >= 10000) return '$sign${(a / 10000).toStringAsFixed(a >= 1000000 ? 0 : 1)}萬';
    return '$sign${money.format(a.round())}';
  }

  /// 本月損益（與 _profitCard 同一算法）
  double _profitOf(_DashboardData d, MonthlySummary s) {
    final rent = (d.fixed.rent ?? 0) + d.itemsOf('rent') + d.recurringOf('rent');
    final payroll = (d.fixed.payroll ?? 0) + d.itemsOf('payroll') + d.recurringOf('payroll');
    final misc = s.miscCost + d.itemsOf('misc') + d.recurringOf('misc') + d.cardFee(s);
    return s.revenue - s.purchaseCost - misc - rent - payroll;
  }

  /// 本月損益（只有老闆：含人事成本）
  /// 損益＝營收 − 進貨 − 雜項 − 租金 − 人事（老闆 2026-10-09 確認：酒水副材料-雜項歸雜項，不重複扣）
  Widget _profitCard(_DashboardData d, MonthlySummary s) {
    // 手動支出明細（一次性＋每月固定）＋刷卡手續費：加在既有租金／人事之上；雜項＝進貨雜項＋手動雜項＋刷卡手續費
    final rentItems = d.itemsOf('rent') + d.recurringOf('rent');
    final payrollItems = d.itemsOf('payroll') + d.recurringOf('payroll');
    final miscItems = d.itemsOf('misc') + d.recurringOf('misc') + d.cardFee(s);
    final rent = (d.fixed.rent ?? 0) + rentItems;
    final payroll = (d.fixed.payroll ?? 0) + payrollItems;
    final misc = s.miscCost + miscItems;
    final profit = s.revenue - s.purchaseCost - misc - rent - payroll;
    final missing = [if (d.fixed.rent == null) '租金', if (d.fixed.payroll == null) '人事'];
    // 百分比＝占當月營業收入（老闆 2026-10-12）；營收 0 時顯示 —
    String ofRevenue(double v) => pct(s.revenue > 0 ? v / s.revenue : null);
    Widget line(String k, double v, {bool minus = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(color: AppColors.muted, fontSize: AppType.small))),
            Text('${minus ? '−' : ''}${ntd(v)}', style: const TextStyle(fontSize: AppType.small, fontFeatures: [FontFeature.tabularFigures()])),
            SizedBox(
              width: 58,
              child: Text(ofRevenue(v),
                  textAlign: TextAlign.right,
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.small, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ]),
        );
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('本月損益', style: TextStyle(color: AppColors.muted))),
          TextButton.icon(
            onPressed: () => _exportPl(d, s),
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('匯出損益表'),
          ),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(ntd(profit),
              style: TextStyle(fontSize: AppType.display, fontWeight: FontWeight.w800, color: profit >= 0 ? AppColors.good : AppColors.bad)),
          const SizedBox(width: 8),
          Text(ofRevenue(profit),
              style: TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w600, color: profit >= 0 ? AppColors.good : AppColors.bad)),
        ]),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('尚未輸入${missing.join('、')}，損益還不完整',
                style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
          ),
        const SizedBox(height: 10),
        line('營業收入', s.revenue, minus: false),
        line('進貨（不含雜項類）', s.purchaseCost),
        line('雜項${miscItems != 0 ? '（含明細 ${ntd(miscItems)}）' : ''}', misc),
        line('租金${rentItems != 0 ? '（含明細 ${ntd(rentItems)}）' : ''}', rent),
        line('人事${payrollItems != 0 ? '（含明細 ${ntd(payrollItems)}）' : ''}', payroll),
        const SizedBox(height: 2),
        Text('百分比＝占本月營業收入', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        const Divider(height: 20),
        Row(children: [
          _fixedItem(d, 'rent', '租金（基底）', d.fixed.rent, s.revenue),
          const SizedBox(width: 12),
          _fixedItem(d, 'payroll', '人事（基底）', d.fixed.payroll, s.revenue),
        ]),
        const SizedBox(height: 4),
        Text('租金、人事的單一金額當基底；下面的支出明細會另外加上去。', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        const SizedBox(height: 12),
        _expenseItemsSection(d, s),
      ]),
    );
  }

  /// 一鍵匯出當月損益表（Excel），數字與上面卡片同一算法（老闆 2026-10-12）
  Future<void> _exportPl(_DashboardData d, MonthlySummary s) async {
    try {
      await pl.loadLibrary();
    } catch (e) {
      if (mounted) showMessage(context, '匯出工具下載失敗，請檢查網路後再試', error: true);
      return;
    }
    detail(String cat, double? base, String baseLabel) => [
          if (base != null) pl.PlLine(baseLabel, base),
          for (final it in d.recurring.where((e) => e.category == cat)) pl.PlLine(it.name, it.amount, '每月固定'),
          for (final it in d.items.where((e) => e.category == cat)) pl.PlLine(it.name, it.amount),
        ];
    final cardFee = d.cardFee(s);
    final rent = (d.fixed.rent ?? 0) + d.itemsOf('rent') + d.recurringOf('rent');
    final payroll = (d.fixed.payroll ?? 0) + d.itemsOf('payroll') + d.recurringOf('payroll');
    final misc = s.miscCost + d.itemsOf('misc') + d.recurringOf('misc') + cardFee;
    final parts = revenueParts(widget.membership.storeName,
        drinks: s.drinksRevenue, food: s.foodRevenue, project: s.projectAmount,
        coffee: s.coffeeRevenue, ramen: s.ramenRevenue, deposit: s.deposit);
    final p = pl.ProfitStatement(
      storeName: widget.membership.storeName,
      month: d.month,
      revenue: s.revenue,
      revenueParts: [for (final x in parts) pl.PlLine(x.label, x.amount)],
      guests: s.guests,
      cash: s.cash,
      card: s.card,
      purchaseCost: s.purchaseCost,
      drinkCost: s.drinkCost,
      foodCost: s.foodCost,
      misc: misc,
      rent: rent,
      payroll: payroll,
      miscDetail: [
        pl.PlLine('進貨雜項', s.miscCost, '雜項類進貨'),
        if (cardFee != 0) pl.PlLine('刷卡手續費', cardFee, '刷卡 ${ntd(s.card)} × ${_ratePct(d.cardFeeRate)}%'),
        ...detail('misc', null, ''),
      ],
      rentDetail: detail('rent', d.fixed.rent, '租金（基底）'),
      payrollDetail: detail('payroll', d.fixed.payroll, '人事（基底）'),
      warnings: [
        if (d.fixed.rent == null) '尚未輸入租金',
        if (d.fixed.payroll == null) '尚未輸入人事',
      ],
    );
    try {
      final r = await pl.saveFile(pl.buildProfitXlsx(p), p.fileName, pl.xlsxMime);
      if (!mounted) return;
      if (r == 'downloaded') showMessage(context, '已下載 ${p.fileName}');
    } catch (e) {
      if (mounted) showMessage(context, '匯出失敗：$e', error: true);
    }
  }

  // 其他支出明細：刷卡手續費（自動）＋每月固定＋一次性；老闆新增，金額加進所選大類
  Widget _expenseItemsSection(_DashboardData d, MonthlySummary s) {
    final cardFee = d.cardFee(s);
    final noManual = d.items.isEmpty && d.recurring.isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('其他支出明細', style: TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton.icon(onPressed: () => _editItem(d, null), icon: const Icon(Icons.add, size: 18), label: const Text('新增')),
      ]),
      if (noManual)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('可新增勞保、健保、電費、營業稅…，選租金／人事／雜項、可設每月固定；金額會加進該大項。',
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        ),
      // 刷卡手續費（自動：當月刷卡金額 × 費率）——一律顯示，讓老闆隨時能改費率（即使本月刷卡 0 或費率設 0）
      _expItemRow('雜項', '刷卡手續費', cardFee,
          tag: d.hasManualCardFee ? '本月已有手動、未重複計' : '自動 ${_ratePct(d.cardFeeRate)}%',
          onTap: () => _editCardFeeRate(d)),
      // 每月固定支出
      for (final it in d.recurring)
        _expItemRow(ExpenseItem.categoryLabels[it.category] ?? it.category, it.name, it.amount,
            tag: '每月固定', onTap: () => _editRecurring(d, it)),
      // 一次性支出
      for (final it in d.items)
        _expItemRow(ExpenseItem.categoryLabels[it.category] ?? it.category, it.name, it.amount,
            onTap: () => _editItem(d, it)),
    ]);
  }

  /// 費率顯示：百分比最多兩位小數、去掉尾端的 0（2 → "2"、2.25 → "2.25"、2.5 → "2.5"）
  String _ratePct(double rate) {
    var s = (rate * 100).toStringAsFixed(2);
    if (s.contains('.')) s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  Widget _expItemRow(String catLabel, String name, double amount, {String? tag, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: AppColors.cardHigh,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: Text(catLabel, style: const TextStyle(fontSize: AppType.caption)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: const TextStyle(fontSize: AppType.small))),
                if (tag != null) ...[
                  Text(tag, style: TextStyle(fontSize: AppType.caption, color: AppColors.muted)),
                  const SizedBox(width: 8),
                ],
                Text(ntd(amount), style: const TextStyle(fontSize: AppType.small, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
              ]),
            ),
          ),
        ),
      );

  Future<void> _editItem(_DashboardData d, ExpenseItem? item) async {
    final name = TextEditingController(text: item?.name ?? '');
    final amount = TextEditingController(text: item == null ? '' : item.amount.round().toString());
    var category = item?.category ?? 'misc';
    var recurring = false; // 每月固定（只在新增時可選）
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(item == null ? '新增支出' : '修改支出', style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(controller: name, maxLength: 40, decoration: const InputDecoration(labelText: '項目（例：勞保、電費、營業稅）')),
            Wrap(spacing: 8, children: [
              for (final n in ExpenseItem.commonNames)
                ActionChip(label: Text(n), onPressed: () => setSheet(() => name.text = n)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
              decoration: const InputDecoration(prefixText: '\$ ', labelText: '金額'),
            ),
            const SizedBox(height: 12),
            Text('算進哪個大項', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'rent', label: Text('租金')),
                ButtonSegment(value: 'payroll', label: Text('人事')),
                ButtonSegment(value: 'misc', label: Text('雜項')),
              ],
              selected: {category},
              onSelectionChanged: (v) => setSheet(() => category = v.first),
            ),
            if (item == null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('每月固定', style: TextStyle(fontSize: AppType.body)),
                subtitle: const Text('設一次，之後每個月自動帶入，不用再輸入', style: TextStyle(fontSize: AppType.small)),
                value: recurring,
                onChanged: (v) => setSheet(() => recurring = v),
              ),
            const SizedBox(height: 16),
            Row(children: [
              if (item != null)
                TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text('刪除', style: TextStyle(color: AppColors.bad))),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty || (double.tryParse(amount.text) ?? 0) <= 0) return;
                  Navigator.pop(c, 'save');
                },
                child: const Text('儲存'),
              ),
            ]),
          ]),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final repo = AppScope.of(context).repo;
    try {
      if (result == 'delete' && item != null) {
        await repo.deleteExpenseItem(item.id);
      } else if (result == 'save') {
        if (recurring && item == null) {
          await repo.saveRecurringExpenseItem(
            widget.membership.storeId,
            RecurringExpenseItem(id: '', name: name.text.trim(), category: category, amount: double.parse(amount.text)),
            isNew: true,
          );
        } else {
          await repo.saveExpenseItem(
            widget.membership.storeId, d.month,
            ExpenseItem(id: item?.id ?? '', name: name.text.trim(), category: category, amount: double.parse(amount.text)),
            isNew: item == null,
          );
        }
      }
      if (mounted) { showMessage(context, '已儲存'); _reload(); }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  // 修改／刪除每月固定支出
  Future<void> _editRecurring(_DashboardData d, RecurringExpenseItem item) async {
    final name = TextEditingController(text: item.name);
    final amount = TextEditingController(text: item.amount.round().toString());
    var category = item.category;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('每月固定支出', style: TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('改金額會套用到每個月；不要了就刪除。', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              const SizedBox(height: 12),
              TextField(controller: name, maxLength: 40, decoration: const InputDecoration(labelText: '項目')),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
                decoration: const InputDecoration(prefixText: '\$ ', labelText: '金額'),
              ),
              const SizedBox(height: 12),
              Text('算進哪個大項', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'rent', label: Text('租金')),
                  ButtonSegment(value: 'payroll', label: Text('人事')),
                  ButtonSegment(value: 'misc', label: Text('雜項')),
                ],
                selected: {category},
                onSelectionChanged: (v) => setSheet(() => category = v.first),
              ),
              const SizedBox(height: 16),
              Row(children: [
                TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text('刪除', style: TextStyle(color: AppColors.bad))),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (name.text.trim().isEmpty || (double.tryParse(amount.text) ?? 0) <= 0) return;
                    Navigator.pop(c, 'save');
                  },
                  child: const Text('儲存'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final repo = AppScope.of(context).repo;
    try {
      if (result == 'delete') {
        await repo.deleteRecurringExpenseItem(item.id);
      } else {
        await repo.saveRecurringExpenseItem(
          widget.membership.storeId,
          RecurringExpenseItem(id: item.id, name: name.text.trim(), category: category, amount: double.parse(amount.text)),
        );
      }
      if (mounted) { showMessage(context, '已儲存'); _reload(); }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  // 修改刷卡手續費率
  Future<void> _editCardFeeRate(_DashboardData d) async {
    final ctrl = TextEditingController(text: _ratePct(d.cardFeeRate));
    final v = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('刷卡手續費率'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('刷卡手續費＝當月刷卡金額 × 此比率，自動算進雜項。', style: TextStyle(fontSize: AppType.small, color: AppColors.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // 最多兩位小數（資料庫存到 0.01%）
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?'))],
            decoration: const InputDecoration(suffixText: '%', labelText: '比率（最多兩位小數）'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text)), child: const Text('儲存')),
        ],
      ),
    );
    if (v == null || !mounted) return;
    if (v < 0 || v > 100) {
      showMessage(context, '比率要在 0～100% 之間', error: true);
      return;
    }
    try {
      await AppScope.of(context).repo.saveCardFeeRate(widget.membership.storeId, (v * 100).round() / 10000);
      if (mounted) { showMessage(context, '已儲存'); _reload(); }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Widget _fixedItem(_DashboardData d, String category, String label, double? v, double revenue) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => _editFixed(d.month, category, label, v),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.cardHigh, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label, style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                const Spacer(),
                Icon(Icons.edit_outlined, size: 14, color: AppColors.muted),
              ]),
              const SizedBox(height: 4),
              Text(v == null ? '尚未輸入' : ntd(v),
                  style: TextStyle(fontSize: v == null ? 14 : 18, fontWeight: FontWeight.w700,
                      color: v == null ? AppColors.warn : null)),
              const SizedBox(height: 2),
              Text(v == null ? '' : '占營收 ${revenue > 0 ? pct(v / revenue) : '—'}',
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            ]),
          ),
        ),
      );

  Widget _amount(String label, double v, Color dot) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle, size: 8, color: dot),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          ]),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(ntd(v), style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

}

class _Trend {
  _Trend(this.cumulative, this.prevCumulative, this.daysInMonth, this.delta);
  final List<double> cumulative; // 本月 1 日到最後有資料那天的累計
  final List<double> prevCumulative; // 上個月整月累計
  final int daysInMonth;
  final double? delta; // 較上月同期
}

/// 本月累計營收線（金）＋上月累計（淡），x 軸＝當月日數
class _TrendPainter extends CustomPainter {
  _TrendPainter(this.t, this.color, this.prevColor, this.baseColor);
  final _Trend t;
  final Color color, prevColor, baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = [...t.cumulative, ...t.prevCumulative].fold<double>(0, (a, b) => b > a ? b : a);
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), Paint()..color = baseColor);
    if (maxV <= 0) return;
    Path path(List<double> v, int days) {
      final p = Path();
      for (var i = 0; i < v.length; i++) {
        final x = days <= 1 ? 0.0 : size.width * i / (days - 1);
        final y = size.height - 3 - (size.height - 6) * v[i] / maxV;
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p;
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (t.prevCumulative.isNotEmpty) {
      canvas.drawPath(path(t.prevCumulative, t.prevCumulative.length), stroke..color = prevColor..strokeWidth = 1.2);
    }
    canvas.drawPath(path(t.cumulative, t.daysInMonth), stroke..color = color..strokeWidth = 2);
    final last = t.cumulative.length - 1;
    final x = t.daysInMonth <= 1 ? 0.0 : size.width * last / (t.daysInMonth - 1);
    final y = size.height - 3 - (size.height - 6) * t.cumulative[last] / maxV;
    canvas.drawCircle(Offset(x, y), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.t != t || old.color != color;
}
