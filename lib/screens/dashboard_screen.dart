import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 營運總覽（PRD 畫面 01）。老闆／店長看營收與成本；員工版只顯示零用金與快速操作（營收由資料庫權限隱藏）。
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardData {
  MonthlySummary? summary;
  List<Issue> issues = [];
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
    if (!widget.membership.isManager) d.petty = await repo.pettyCashBalance(id);
    if (widget.membership.isManager) {
      final r = await Future.wait([
        repo.monthlySummary(id, _month),
        repo.consistencyIssues(id),
      ]);
      d.summary = r[0] as MonthlySummary;
      d.issues = r[1] as List<Issue>;
    }
    return d;
  }

  void _reload() => setState(() => _future = _load());

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
              if (widget.membership.isManager) ..._managerView(d) else ..._staffView(d),
            ]),
          );
        },
      );

  List<Widget> _staffView(_DashboardData d) => [
        const SectionCard(
          child: Text('員工版總覽：營收與成本分析只有老闆、店長看得到。\n可以在下方分頁記錄進貨與盤點。',
              style: TextStyle(color: AppColors.muted, height: 1.5)),
        ),
        const SizedBox(height: 12),
        StatTile(label: '零用金結餘', value: d.petty == null ? '—' : ntd(d.petty!)),
      ];

  List<Widget> _managerView(_DashboardData d) {
    final s = d.summary!;
    final monthLabel = DateFormat('yyyy 年 M 月', 'zh_TW').format(d.month);
    final errors = d.issues.where((i) => i.severity == 'error').length;
    final warnings = d.issues.where((i) => i.severity == 'warning').length;
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
          Text(ntd(s.revenue), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(children: [
            _amount('酒水', s.drinksRevenue, AppColors.primary),
            _amount('餐食', s.foodRevenue, AppColors.warn),
            if (s.projectAmount != 0) _amount('專案', s.projectAmount, AppColors.muted),
          ]),
          const SizedBox(height: 10),
          _MixBar(drinks: s.drinksRevenue, food: s.foodRevenue),
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
            value: s.avgTicket == null ? '—' : ntd(s.avgTicket!),
            sub: s.dailyAvgTicket != null && s.dailyAvgTicket != s.avgTicket ? '不含活動 ${ntd(s.dailyAvgTicket!)}' : null,
          ),
        ),
      ]),
      const SizedBox(height: 12),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('進貨成本率', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          if (!s.hasCostRecords && s.revenue > 0)
            const Text('本月尚無進貨資料', style: TextStyle(color: AppColors.warn))
          else
            Row(children: [
              _rate('酒水', s.drinkCostRate),
              _rate('餐食', s.foodCostRate),
              _rate('總進貨', s.totalCostRate),
              _rate('雜項', s.miscCostRate),
            ]),
          const SizedBox(height: 6),
          const Text('雜項＝零用金-其他雜支＋酒水副材料-雜項，÷ 營業收入；不計入總進貨',
              style: TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.notifications_active_outlined, color: AppColors.bad, size: 18),
            const SizedBox(width: 6),
            const Text('營運警報'),
            const Spacer(),
            Text('錯誤 $errors・提醒 $warnings', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          if (d.issues.isEmpty) const Text('沒有異常', style: TextStyle(color: AppColors.good)),
          for (final i in d.issues.where((i) => i.severity != 'info').take(6))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.circle, size: 8, color: i.severity == 'error' ? AppColors.bad : AppColors.warn),
                const SizedBox(width: 8),
                Expanded(child: Text('${i.checkName}：${i.detail}', style: const TextStyle(fontSize: 13))),
              ]),
            ),
        ]),
      ),
    ];
  }

  Widget _amount(String label, double v, Color dot) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle, size: 8, color: dot),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 2),
          Text(ntd(v), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _rate(String label, double? v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(pct(v), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// 酒水／餐食占比橫條
class _MixBar extends StatelessWidget {
  const _MixBar({required this.drinks, required this.food});
  final double drinks;
  final double food;
  @override
  Widget build(BuildContext context) {
    final total = drinks + food;
    if (total <= 0) return const SizedBox.shrink();
    final dp = drinks / total;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          Expanded(flex: (dp * 1000).round(), child: Container(height: 8, color: AppColors.primary)),
          Expanded(flex: ((1 - dp) * 1000).round(), child: Container(height: 8, color: AppColors.warn)),
        ]),
      ),
      const SizedBox(height: 6),
      Text('酒水 ${pct(dp)}・餐食 ${pct(1 - dp)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }
}
