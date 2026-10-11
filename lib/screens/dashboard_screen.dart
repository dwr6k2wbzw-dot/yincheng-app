import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/revenue_mix.dart';
import 'handover_screen.dart';

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
  DateTime month = DateTime.now();

  double itemsOf(String category) => items.where((e) => e.category == category).fold(0.0, (a, e) => a + e.amount);
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
    if (widget.membership.isPartTime) return d; // 兼職只看交接、提醒
    if (!widget.membership.canSeeRevenue) d.petty = await repo.pettyCashBalance(id);
    if (widget.membership.canSeeRevenue) {
      final r = await Future.wait([
        repo.monthlySummary(id, _month),
        if (_isOwner) repo.fixedCosts(id, _month),
      ]);
      d.summary = r[0] as MonthlySummary;
      if (_isOwner) {
        d.fixed = r[1] as FixedCosts;
        d.items = await repo.expenseItems(id, _month);
      }
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
              HandoverSummaryCard(key: ValueKey('hs-${widget.membership.storeId}'), membership: widget.membership),
              if (widget.membership.isPartTime)
                const Text('兼職帳號：可以看班表、交接與提醒。點上面的卡片寫交接、打勾提醒。',
                    style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5))
              else if (widget.membership.canSeeRevenue)
                ..._managerView(d)
              else
                ..._staffView(d),
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
            () {
              // 老闆：雜項＝進貨雜項＋手動雜項支出（老闆 2026-10-11 決定）；員工看進貨口徑
              final miscAmt = s.miscCost + (_isOwner ? d.itemsOf('misc') : 0);
              final miscRate = s.revenue > 0 ? miscAmt / s.revenue : null;
              return Row(children: [
                _rate('酒水', s.drinkCostRate, s.drinkCost),
                _rate('餐食', s.foodCostRate, s.foodCost),
                _rate('總進貨', s.totalCostRate, s.totalCost),
                _rate('雜項', miscRate, miscAmt),
              ]);
            }(),
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
    // 手動支出明細：加在既有租金／人事之上；雜項＝進貨雜項＋手動雜項
    final rentItems = d.itemsOf('rent'), payrollItems = d.itemsOf('payroll'), miscItems = d.itemsOf('misc');
    final rent = (d.fixed.rent ?? 0) + rentItems;
    final payroll = (d.fixed.payroll ?? 0) + payrollItems;
    final misc = s.miscCost + miscItems;
    final profit = s.revenue - s.purchaseCost - misc - rent - payroll;
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
        line('雜項${miscItems != 0 ? '（含手動 ${ntd(miscItems)}）' : ''}', misc),
        line('租金${rentItems != 0 ? '（含手動 ${ntd(rentItems)}）' : ''}', rent),
        line('人事${payrollItems != 0 ? '（含手動 ${ntd(payrollItems)}）' : ''}', payroll),
        const Divider(height: 20),
        Row(children: [
          _fixedItem(d, 'rent', '租金（基底）', d.fixed.rent, s.revenue),
          const SizedBox(width: 12),
          _fixedItem(d, 'payroll', '人事（基底）', d.fixed.payroll, s.revenue),
        ]),
        const SizedBox(height: 4),
        const Text('租金、人事的單一金額當基底；下面的支出明細會另外加上去。', style: TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 12),
        _expenseItemsSection(d),
      ]),
    );
  }

  // 其他支出明細（勞保、電費、營業稅…）：老闆新增，金額加進所選大類
  Widget _expenseItemsSection(_DashboardData d) {
    const catLabel = ExpenseItem.categoryLabels;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('其他支出明細', style: TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton.icon(onPressed: () => _editItem(d, null), icon: const Icon(Icons.add, size: 18), label: const Text('新增')),
      ]),
      if (d.items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('還沒有。可新增勞保、健保、電費、營業稅…，選租金／人事／雜項，金額會加進該大項。',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        )
      else
        for (final it in d.items)
          Material(
            color: AppColors.cardHigh,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _editItem(d, it),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(6)),
                    child: Text(catLabel[it.category] ?? it.category, style: const TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(it.name, style: const TextStyle(fontSize: 13))),
                  Text(ntd(it.amount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
                ]),
              ),
            ),
          ),
    ]);
  }

  Future<void> _editItem(_DashboardData d, ExpenseItem? item) async {
    final name = TextEditingController(text: item?.name ?? '');
    final amount = TextEditingController(text: item == null ? '' : item.amount.round().toString());
    var category = item?.category ?? 'misc';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(item == null ? '新增支出' : '修改支出', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
            const Text('算進哪個大項', style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
              if (item != null)
                TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('刪除', style: TextStyle(color: AppColors.bad))),
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
    );
    if (result == null || !mounted) return;
    final repo = AppScope.of(context).repo;
    try {
      if (result == 'delete' && item != null) {
        await repo.deleteExpenseItem(item.id);
      } else if (result == 'save') {
        await repo.saveExpenseItem(
          widget.membership.storeId, d.month,
          ExpenseItem(id: item?.id ?? '', name: name.text.trim(), category: category, amount: double.parse(amount.text)),
          isNew: item == null,
        );
      }
      if (mounted) { showMessage(context, '已儲存'); _reload(); }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
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
