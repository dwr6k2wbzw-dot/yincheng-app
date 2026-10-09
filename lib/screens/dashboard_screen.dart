import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/revenue_mix.dart';

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
  DateTime month = DateTime.now();
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
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final d = _DashboardData()..month = _month;
    if (!widget.membership.canSeeRevenue) d.petty = await repo.pettyCashBalance(id);
    if (widget.membership.canSeeRevenue) {
      final r = await Future.wait([
        repo.monthlySummary(id, _month),
        if (_isOwner) repo.fixedCosts(id, _month),
      ]);
      d.summary = r[0] as MonthlySummary;
      if (_isOwner) d.fixed = r[1] as FixedCosts;
    }
    return d;
  }

  void _reload() => setState(() => _future = _load());

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
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              if (widget.membership.canSeeRevenue) ..._managerView(d) else ..._staffView(d),
            ]),
          );
        },
      );

  List<Widget> _staffView(_DashboardData d) => [
        const SectionCard(
          child: Text('這個身分看不到營收與成本分析。\n可以在下方分頁記錄進貨與盤點。',
              style: TextStyle(color: AppColors.muted, height: 1.5)),
        ),
        const SizedBox(height: 12),
        StatTile(label: '零用金結餘', value: d.petty == null ? '—' : ntd(d.petty!)),
      ];

  List<Widget> _managerView(_DashboardData d) {
    final s = d.summary!;
    final monthLabel = DateFormat('yyyy 年 M 月', 'zh_TW').format(d.month);
    final multi = isMultiLineStore(widget.membership.storeName);
    final parts = revenueParts(widget.membership.storeName,
        drinks: s.drinksRevenue, food: s.foodRevenue, project: s.projectAmount,
        coffee: s.coffeeRevenue, ramen: s.ramenRevenue, deposit: s.deposit);
    // 小城外的客單＝調酒收入 ÷ 來客數（與小城外 Excel 相同）
    final cocktail = s.drinksRevenue + s.foodRevenue + s.projectAmount;
    final avgTicket = multi ? (s.guests > 0 ? cocktail / s.guests : null) : s.avgTicket;
    return [
      Row(children: [
        IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text(monthLabel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16))),
        IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 4),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('本月營收', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(ntd(s.revenue), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _payRow('現金', s.cash),
              _payRow('刷卡', s.card),
              if (s.deposit != 0 && !multi) _payRow('訂金', s.deposit),
            ]),
          ]),
          const SizedBox(height: 10),
          Row(children: [for (final p in parts) _amount(p.label, p.amount, p.color)]),
          const SizedBox(height: 10),
          MixBar(parts: parts),
          const SizedBox(height: 16),
          if (s.targetAmount != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (s.targetRate ?? 0).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.cardHigh,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text('目標 ${ntd(s.targetAmount!)}　達成 ${pct(s.targetRate)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ] else
            const Text('尚未設定本月營收目標', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: StatTile(label: '來客數', value: money.format(s.guests))),
        const SizedBox(width: 12),
        Expanded(
          child: StatTile(
            label: '客單價',
            value: avgTicket == null ? '—' : ntd(avgTicket.round()),
            sub: multi
                ? '調酒收入 ÷ 來客數'
                : s.dailyAvgTicket != null && s.dailyAvgTicket != s.avgTicket ? '不含活動 ${ntd(s.dailyAvgTicket!)}' : null,
          ),
        ),
      ]),
      if (widget.membership.canSeeRevenue) ...[
      const SizedBox(height: 12),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('進貨成本率', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          if (!s.hasCostRecords && s.revenue > 0)
            const Text('本月尚無進貨資料', style: TextStyle(color: AppColors.warn))
          else
            Row(children: [
              _rate('酒水', s.drinkCostRate, s.drinkCost),
              _rate('餐食', s.foodCostRate, s.foodCost),
              _rate('總進貨', s.totalCostRate, s.totalCost),
              _rate('雜項', s.miscCostRate, s.miscCost),
            ]),
          const SizedBox(height: 6),
          Text(
              multi
                  ? '酒水、餐食只算酒吧；總進貨含咖啡吧與拉麵；雜項＝各區雜項 ÷ 營業收入，不計入總進貨'
                  : '雜項＝零用金-其他雜支＋酒水副材料-雜項，÷ 營業收入；不計入總進貨',
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
      ),
      ],
      const SizedBox(height: 12),
      if (_isOwner) _profitCard(d, s),
    ];
  }

  /// 本月損益（只有老闆：含人事成本）
  /// 損益＝營收 − 進貨 − 雜項 − 租金 − 人事（老闆 2026-10-09 確認：酒水副材料-雜項歸雜項，不重複扣）
  Widget _profitCard(_DashboardData d, MonthlySummary s) {
    final rent = d.fixed.rent ?? 0;
    final payroll = d.fixed.payroll ?? 0;
    final profit = s.revenue - s.purchaseCost - s.miscCost - rent - payroll;
    final missing = [if (d.fixed.rent == null) '租金', if (d.fixed.payroll == null) '人事'];
    Widget line(String k, double v, {bool minus = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(k, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const Spacer(),
            Text('${minus ? '−' : ''}${ntd(v)}', style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        );
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('本月損益', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 6),
        Text(ntd(profit),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: profit >= 0 ? AppColors.good : AppColors.bad)),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('尚未輸入${missing.join('、')}，損益還不完整',
                style: const TextStyle(color: AppColors.warn, fontSize: 12)),
          ),
        const SizedBox(height: 10),
        line('營業收入', s.revenue, minus: false),
        line('進貨（不含雜項類）', s.purchaseCost),
        line('雜項', s.miscCost),
        line('租金', rent),
        line('人事', payroll),
        const Divider(height: 20),
        Row(children: [
          _fixedItem(d, 'rent', '租金', d.fixed.rent, s.revenue),
          const SizedBox(width: 12),
          _fixedItem(d, 'payroll', '人事', d.fixed.payroll, s.revenue),
        ]),
        const SizedBox(height: 8),
        const Text('點租金、人事輸入或修改；占比＝金額 ÷ 本月營業收入。只有老闆看得到',
            style: TextStyle(color: AppColors.muted, fontSize: 11)),
      ]),
    );
  }

  Widget _fixedItem(_DashboardData d, String category, String label, double? v, double revenue) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _editFixed(d.month, category, label, v),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.cardHigh, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const Spacer(),
                const Icon(Icons.edit_outlined, size: 14, color: AppColors.muted),
              ]),
              const SizedBox(height: 4),
              Text(v == null ? '尚未輸入' : ntd(v),
                  style: TextStyle(fontSize: v == null ? 14 : 18, fontWeight: FontWeight.w700,
                      color: v == null ? AppColors.warn : null)),
              const SizedBox(height: 2),
              Text(v == null ? '' : '占營收 ${revenue > 0 ? pct(v / revenue) : '—'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _payRow(String label, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(width: 8),
          Text(ntd(v), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _amount(String label, double v, Color dot) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle, size: 8, color: dot),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(ntd(v), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _rate(String label, double? v, double amount) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(pct(v), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(ntd(amount.round()), style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ),
        ]),
      );
}
