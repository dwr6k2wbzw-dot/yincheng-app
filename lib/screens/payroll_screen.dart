import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 薪資（老闆、店長；ops 0110）：每月帶入薪率與打卡時數 → 逐人填獎金、勞健保、加班 → 發布給員工看薪資單。
/// 店長看不到、改不到自己的那一列，月報也不給總計（避免反推）。發布後不能改，老闆寫原因才能重新開啟。
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, required this.membership, required this.attendanceEnabled, this.onOpenStaff});
  final Membership membership;
  final bool attendanceEnabled; // 有開打卡的店：時數、天數從已確認的出勤帶入
  final Future<void> Function()? onOpenStaff; // 缺薪率時「前往員工資料」
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(v * 10 % 1 == 0 ? 1 : 2);

/// 載入的結果和它是哪個月份綁在一起：切月時畫面上還是舊月份的資料，所有操作都用這個 month，不用 [_PayrollScreenState._month]
/// estimate：薪資預估（ops 0129）；讀不到（例如資料庫還沒更新）＝null，不影響其他部分
typedef _MonthData = ({DateTime month, PayrollSettings settings, PayrollReport report, List<PayrollRow> rows, PayrollEstimate? estimate});

class _PayrollScreenState extends State<PayrollScreen> {
  late DateTime _month = DateTime(bizToday().year, bizToday().month - 1, 1); // 預設上個月（正在看／正在載入的月份）
  late Future<_MonthData> _future = _load();
  bool _busy = false;

  Repository get _repo => AppScope.of(context).repo;
  bool get _owner => widget.membership.role == Role.owner;
  String get _store => widget.membership.storeId;

  Future<_MonthData> _load() async {
    final repo = AppScope.of(context).repo;
    final m = _month;
    final r = await Future.wait([
      repo.payrollSettings(_store),
      repo.payrollReport(_store, m),
      repo.payrollMonth(_store, m),
      repo.payrollEstimate(_store, m).then<PayrollEstimate?>((v) => v, onError: (_) => null),
    ]);
    return (
      month: m,
      settings: r[0] as PayrollSettings,
      report: r[1] as PayrollReport,
      rows: r[2] as List<PayrollRow>,
      estimate: r[3] as PayrollEstimate?,
    );
  }

  void _reload() => setState(() {
        _future = _load();
      });

  void _shiftMonth(int d) => setState(() {
        _month = DateTime(_month.year, _month.month + d, 1);
        _future = _load();
      });

  Future<void> _run(Future<void> Function() f, String done) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reload();
      }
    }
  }

  /// facts：確認視窗上先列出的重點（一行一項）
  Future<bool> _confirm(String title, String body, String ok, {List<String> facts = const []}) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in facts)
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(f, style: const TextStyle(fontWeight: AppFont.heading))),
            if (facts.isNotEmpty) const SizedBox(height: 8),
            Text(body),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(ok)),
          ],
        ),
      ) ==
      true;

  Future<void> _prepare(DateTime month, bool again) async {
    if (again &&
        !await _confirm('重新帶入', '重新帶入薪資、計薪方式${widget.attendanceEnabled ? '和打卡時數' : ''}。手動填的天數、時數、獎金、勞健保、加班時數都不會動。', '重新帶入')) {
      return;
    }
    await _run(() => _repo.preparePayroll(_store, month), again ? '已重新帶入' : '已建立 ${month.month} 月薪資');
  }

  /// 發布前彙總：店別、年月、計薪人數、不計薪人數；總額只給老闆看（店長看不到總額，避免反推自己的薪水）
  Future<void> _publish(_MonthData d) async {
    final month = d.month, r = d.report;
    if (!await _confirm('發布 ${month.month} 月薪資', '發布後員工看得到自己的薪資單，而且不能再改（要改得請老闆重新開啟）。', '發布', facts: [
      '店別：${widget.membership.storeName}',
      '年月：${month.year} 年 ${month.month} 月',
      '計薪人數：${r.people} 人',
      '不計薪人數：${d.rows.where((x) => x.exempt).length} 人',
      if (_owner && r.total != null) '薪資總額：${ntd(r.total!)}',
    ])) {
      return;
    }
    await _run(() => _repo.publishPayroll(_store, month), '已發布');
  }

  /// 不計薪（只有老闆）：不領薪的人從應計薪名單拿掉，才能發布
  Future<void> _setExempt(PayrollRow r, bool exempt) async {
    final ok = await _confirm(
        exempt ? '${r.name} 設為不計薪' : '${r.name} 取消不計薪',
        exempt
            ? '「不計薪」是這個員工的設定，不只這個月：之後每個還沒發布的月份都不會帶入他的薪資，也不算缺人。'
                '已經帶入的薪資列不會刪除，已發布的月份不受影響。\n\n'
                '要恢復：回到薪資清單點他的名字，按「取消不計薪」，有薪資後再按「重新帶入」。'
                '要領薪的人請不要設，改到「員工資料」新增薪資。'
            : '取消後這個人回到應計薪名單（之後每個還沒發布的月份都算），要有薪資、按「重新帶入」後才能發布。',
        exempt ? '設為不計薪' : '取消不計薪');
    if (!ok) return;
    await _run(() => _repo.setPayrollExempt(_store, r.personId, exempt), exempt ? '已設為不計薪' : '已取消不計薪');
  }

  Future<void> _reopen(DateTime month) async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('重新開啟'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('重新開啟後員工暫時看不到這個月的薪資單，改好再發布一次。'),
          TextField(controller: c, autofocus: true, maxLength: 200, decoration: const InputDecoration(labelText: '原因（必填）')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                if (c.text.trim().length < 2) return;
                Navigator.pop(d, c.text.trim());
              },
              child: const Text('重新開啟')),
        ],
      ),
    );
    if (reason == null) return;
    await _run(() => _repo.reopenPayroll(_store, month, reason), '已重新開啟');
  }

  Future<void> _editOvertime(PayrollSettings s) async {
    var mode = s.otMode;
    final rate = TextEditingController(text: _n(s.otRate));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('加班費算法（月薪制）'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            RadioGroup<String>(
              groupValue: mode,
              onChanged: (v) => set(() => mode = v!),
              child: const Column(children: [
                RadioListTile(contentPadding: EdgeInsets.zero, value: 'fixed', title: Text('固定時薪')),
                RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: 'lsa',
                    title: Text('依勞基法計算'),
                    subtitle: Text('月薪÷240，每次前 2 小時 ×1.34、第 3 小時起 ×1.67')),
              ]),
            ),
            if (mode == 'fixed')
              TextField(
                  controller: rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '加班時薪')),
            const SizedBox(height: 8),
            Text('改了之後按「重新帶入」才會套用到還沒發布的月份', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('儲存')),
          ],
        ),
      ),
    );
    final r = double.tryParse(rate.text.trim());
    if (ok != true || (mode == 'fixed' && (r == null || r <= 0))) return;
    await _run(() => _repo.setPayrollOvertime(_store, mode, mode == 'fixed' ? r! : s.otRate), '已儲存加班費算法');
  }

  /// 薪資單抬頭用的公司登記全名（只有老闆能改；空白＝用店名）
  Future<void> _editCompany(PayrollSettings s) async {
    final c = TextEditingController(text: s.companyName ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('薪資單抬頭'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
              labelText: '公司登記全名',
              hintText: '例如：○○股份有限公司',
              helperText: '請填跟扣繳憑單上一樣的公司全名。留空白＝薪資單抬頭用店名。',
              helperMaxLines: 3),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('儲存')),
        ],
      ),
    );
    final name = c.text.trim();
    if (ok != true) return;
    await _run(() => _repo.setPayrollCompany(_store, name), name.isEmpty ? '已清掉，薪資單抬頭改回店名' : '已儲存薪資單抬頭');
  }

  /// 薪資預估（ops 0129）：薪率×班表；過完的月份草稿有填就用草稿的；發布後另外顯示實際應發
  Widget _estimateCard(DateTime month, PayrollEstimate e) {
    final visible = e.rows.where((r) => !r.hidden && r.basis != 'none').toList();
    Widget part(String type, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label・${e.countOf(type)} 人', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
            Text(ntd(e.totalOf(type)), style: const TextStyle(fontSize: AppType.small, fontFeatures: tabular)),
          ]),
        );
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text('${month.month} 月薪資預估', style: TextStyle(color: AppColors.muted))),
          if (e.published) Text('已發布', style: TextStyle(color: AppColors.good, fontSize: AppType.small)),
        ]),
        const SizedBox(height: 2),
        Text(ntd(e.total), style: const TextStyle(fontSize: AppType.display, fontWeight: AppFont.figure, fontFeatures: tabular)),
        if (e.actualTotal != null)
          Text('實際應發 ${ntd(e.actualTotal!)}',
              style: TextStyle(color: AppColors.good, fontSize: AppType.small, fontFeatures: tabular)),
        const SizedBox(height: 10),
        Row(children: [part('monthly', '月薪'), part('daily', '日薪'), part('hourly', '時薪')]),
        const SizedBox(height: 10),
        Text('應發＝扣勞健保前。月薪算整月，日薪、時薪照班表的天數、時數；月份過完、薪資有填的改用填的。',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        if (_owner)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('總覽的人事（基底）沒手動填時，自動用${e.published ? '實際應發' : '這個數字'}。',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
          ),
        if (e.missingNames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${e.missingNames.join('、')} 沒有薪資資料，預估算 0 元。到「員工資料」新增薪資後會自動算進來。',
                style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
          ),
        if (e.untimed > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('有 ${e.untimed} 班沒有設時間，沒算進時數。到「出勤管理 → 比對班表 → 班的時間」設定後會自動算進來。',
                style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
          ),
        if (e.hasHidden)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('不含你自己那一列', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text('每個人怎麼算（${visible.length} 人）', style: const TextStyle(fontSize: AppType.small)),
            children: [
              for (final r in visible)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.name, style: const TextStyle(fontSize: AppType.small)),
                        Text(
                            [
                              r.howLabel,
                              if ((r.extra ?? 0) != 0) '獎金、加班等 ＋${ntd(r.extra!)}',
                              if (r.untimed > 0 && r.basis == 'schedule') '${r.untimed} 班沒設時間',
                            ].join('・'),
                            style: TextStyle(
                                color: r.untimed > 0 && r.basis == 'schedule' ? AppColors.warn : AppColors.muted, fontSize: AppType.caption)),
                      ]),
                    ),
                    Text(ntd(r.estimate ?? 0), style: const TextStyle(fontSize: AppType.small, fontFeatures: tabular)),
                  ]),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  /// locked：載入中（切月、重新整理）或正在做事，所有按鈕都先停用
  Widget _summary(_MonthData d, bool locked) {
    final r = d.report, s = d.settings, rows = d.rows, month = d.month;
    final hidden = rows.any((x) => x.hidden);
    final missing = r.missingNames.isNotEmpty || r.missingRate > 0;
    final missingCount = r.missingNames.isNotEmpty ? r.missingNames.length : r.missingRate;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('${month.year} 年 ${month.month} 月・${r.people} 人',
                  style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading))),
          Text(r.published ? '已發布' : '草稿', style: TextStyle(color: r.published ? AppColors.good : AppColors.warn)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 24, runSpacing: 8, children: [
          _figure('薪資總計', r.total != null ? ntd(r.total!) : (hidden ? '—' : '待補齊薪資資料')),
          _figure('營業額', r.revenue != null ? ntd(r.revenue!) : '—'),
          _figure('人事成本率', pct(r.costRate)),
        ]),
        if (hidden)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('不含你自己那一列，看不到總計和成本率；其他人合計 ${ntd(r.visibleTotal ?? 0)}',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          ),
        if (missing)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$missingCount 人缺少薪資，還不能發布',
                  style: TextStyle(color: AppColors.bad, fontSize: AppType.small, fontWeight: AppFont.heading)),
              if (r.missingNames.isNotEmpty)
                Text(r.missingNames.join('、'), style: TextStyle(color: AppColors.bad, fontSize: AppType.small)),
              Text(
                  '沒有薪資的先到「員工資料」新增，薪資是之後才加的按「重新帶入」${_owner ? '；不領薪的人可以在下面點他設為不計薪' : '；不領薪的人請老闆設為不計薪'}',
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              if (widget.onOpenStaff != null)
                TextButton.icon(
                    onPressed: locked
                        ? null
                        : () async {
                            await widget.onOpenStaff!();
                            if (mounted) _reload();
                          },
                    icon: const Icon(Icons.badge_outlined, size: 18),
                    label: const Text('前往員工資料')),
            ]),
          ),
        const Divider(height: 24),
        Row(children: [
          Expanded(
            child: Text('加班費：${otModeLabel(s.otMode)}${s.otMode == 'fixed' ? ' ${_n(s.otRate)} 元／小時' : '（月薪÷240，1.34／1.67）'}',
                style: const TextStyle(fontSize: AppType.small)),
          ),
          if (_owner) TextButton(onPressed: locked ? null : () => _editOvertime(s), child: const Text('修改')),
        ]),
        Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: '薪資單抬頭：'),
                TextSpan(text: s.companyName ?? widget.membership.storeName),
                if (s.companyName == null)
                  TextSpan(
                      text: _owner ? '（還沒填公司登記全名）' : '（公司登記全名請老闆填）',
                      style: TextStyle(color: AppColors.warn)),
              ]),
              style: const TextStyle(fontSize: AppType.small),
            ),
          ),
          if (_owner) TextButton(onPressed: locked ? null : () => _editCompany(s), child: Text(s.companyName == null ? '填寫' : '修改')),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!r.published) ...[
            FilledButton(onPressed: locked || missing ? null : () => _publish(d), child: const Text('發布給員工')),
            OutlinedButton(onPressed: locked ? null : () => _prepare(month, true), child: const Text('重新帶入')),
          ],
          if (r.published && _owner) OutlinedButton(onPressed: locked ? null : () => _reopen(month), child: const Text('重新開啟')),
        ]),
      ]),
    );
  }

  Widget _figure(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        Text(value, style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.figure)),
      ]);

  /// 手動調整過的天數／時數：清單上標「已手動調整」，原始帶入的放下一行（見 [_row]）
  String _qty(PayrollRow r) {
    String mark(double? auto, bool edited, String unit) => !edited && auto != null ? '（打卡）' : '';
    return switch (r.payType) {
      'daily' => '${_n(r.days ?? 0)} 天${mark(r.autoDays, r.daysEdited, '天')}',
      'hourly' => '${_n(r.hours ?? 0)} 小時${mark(r.autoHours, r.hoursEdited, '小時')}',
      _ => r.otHours + r.otHours2 > 0 ? '加班 ${_n(r.otHours + r.otHours2)} 小時' : '',
    };
  }

  Widget _tag(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(border: Border.all(color: AppColors.warn), borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(color: AppColors.warn, fontSize: AppType.caption)),
      );

  /// 已發布的月份不在這裡改應計薪名單（要改先重新開啟）
  Widget _row(DateTime month, PayrollRow r, bool locked, bool published, String? companyName) {
    if (r.hidden) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(r.name),
        subtitle: const Text('你自己的薪資由老闆處理，這裡看不到'),
        leading: const Icon(Icons.lock_outline),
      );
    }
    final edited = (r.payType == 'daily' && r.daysEdited) || (r.payType == 'hourly' && r.hoursEdited);
    final auto = r.payType == 'daily' ? r.autoDays : r.autoHours, unit = r.payType == 'daily' ? '天' : '小時';
    final info = Text(r.missingRate
          ? '應計薪但還沒帶入（沒有薪資，或薪資是之後才加的）${_owner && !published ? '・點這裡可設為不計薪' : ''}'
          : r.exempt
              ? '不計薪${_owner && !published ? '・點這裡取消' : ''}'
              : [
                  payrollTypeLabel(r.payType) + (r.baseAmount != null ? ' ${ntd(r.baseAmount!)}' : ''),
                  if (_qty(r).isNotEmpty) _qty(r),
                  if (r.bonus + r.extras.income != 0) '獎金等 ＋${ntd(r.bonus + r.extras.income)}',
                  if (r.insurance + r.deduction + r.extras.deduction != 0)
                    '支出 −${ntd(r.insurance + r.deduction + r.extras.deduction)}',
                  if (r.extras.cashPaid != 0) '領現 ${ntd(r.extras.cashPaid)}',
                ].join('・'));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(r.name),
      // 還沒有這個月薪資列的人（缺人、不計薪）只顯示狀態
      subtitle: !edited
          ? info
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [info, _tag('已手動調整')]),
              Text('原始帶入 ${auto == null ? '無' : '${_n(auto)} $unit'}',
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
            ]),
      trailing: Text(r.exempt ? '' : (r.gross == null ? '—' : ntd(r.gross!)),
          style: TextStyle(fontSize: AppType.title, color: r.gross == null ? AppColors.bad : AppColors.text)),
      onTap: locked
          ? null
          : r.missingRate || r.exempt
              // 還沒有這個月的薪資列：沒東西可改，老闆可以設／取消不計薪
              ? (_owner && !published ? () => _setExempt(r, !r.exempt) : null)
              : () async {
                  final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                      builder: (_) => PayrollEditScreen(
                          membership: widget.membership, month: month, row: r, companyName: companyName)));
                  if (changed == true && mounted) _reload();
                },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('薪資・${widget.membership.storeName}')),
        body: FutureBuilder(
          future: _future,
          builder: (context, snap) {
            final header = Row(children: [
              IconButton(tooltip: '上個月', onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(
                  child: Text('${_month.year} 年 ${_month.month} 月',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: AppType.title))),
              IconButton(tooltip: '下個月', onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
            ]);
            final loading = snap.connectionState != ConnectionState.done;
            if (snap.hasError && !loading) {
              return ListView(padding: const EdgeInsets.all(16), children: [
                header,
                ErrorView(message: friendlyError(snap.error!), onRetry: _reload),
              ]);
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            // 切月時 FutureBuilder 先留著上一個月的資料：顯示「載入中」並停用所有操作，月份一律用資料自己的 d.month
            final d = snap.data!;
            final locked = _busy || loading;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              header,
              if (loading) ...[
                const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('載入 ${_month.year} 年 ${_month.month} 月中，下面還是 ${d.month.year} 年 ${d.month.month} 月的資料',
                      style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                ),
              ],
              if (d.estimate != null) ...[_estimateCard(d.month, d.estimate!), const SizedBox(height: 8)],
              if (d.report.status == null)
                SectionCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${d.month.month} 月薪資還沒建立', style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
                    const SizedBox(height: 6),
                    Text(
                        widget.attendanceEnabled
                            ? '建立時會帶入每個人的薪資，以及這個月「已確認」的打卡時數、天數（待確認的不算）。勞保、健保預設帶上個月的。'
                            : '這家店還沒開打卡：建立後時數、天數要手動填。勞保、健保預設帶上個月的。',
                        style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: locked ? null : () => _prepare(d.month, false), child: Text('建立 ${d.month.month} 月薪資')),
                  ]),
                )
              else ...[
                _summary(d, locked),
                const SizedBox(height: 8),
                for (final r in d.rows) _row(d.month, r, locked, d.report.published, d.settings.companyName),
              ],
            ]);
          },
        ),
      );
}

/// 編輯一個人這個月的薪資；儲存前先試算（和資料庫同一套公式）
class PayrollEditScreen extends StatefulWidget {
  const PayrollEditScreen({super.key, required this.membership, required this.month, required this.row, this.companyName});
  final Membership membership;
  final DateTime month;
  final PayrollRow row;
  final String? companyName; // 薪資單抬頭（列印用）
  @override
  State<PayrollEditScreen> createState() => _PayrollEditScreenState();
}

class _PayrollEditScreenState extends State<PayrollEditScreen> {
  PayrollRow get r => widget.row;
  // 天數／時數：0 也照實顯示（空白代表「用打卡帶入的」，不能和 0 混在一起）
  late final _qty = TextEditingController(text: switch (r.payType) {
    'daily' => r.days == null ? '' : _n(r.days!),
    'hourly' => r.hours == null ? '' : _n(r.hours!),
    _ => '',
  });
  late final _ot1 = TextEditingController(text: _fmt(r.otMode == 'lsa' ? r.otHours : r.otHours + r.otHours2));
  late final _ot2 = TextEditingController(text: _fmt(r.otHours2));
  late final _bonus = TextEditingController(text: _fmt(r.bonus));
  late final _ins = TextEditingController(text: _fmt(r.insurance));
  late final _ded = TextEditingController(text: _fmt(r.deduction));
  // ops 0126：全勤獎金、勞保、健保、眷屬健保、所得稅、領現、自訂項目
  late final _att = TextEditingController(text: _fmt(r.extras.attendanceBonus));
  late final _lab = TextEditingController(text: _fmt(r.extras.laborIns));
  late final _hea = TextEditingController(text: _fmt(r.extras.healthIns));
  late final _dep = TextEditingController(text: _fmt(r.extras.dependentsIns));
  late final _tax = TextEditingController(text: _fmt(r.extras.incomeTax));
  late final _cash = TextEditingController(text: _fmt(r.extras.cashPaid));
  late final List<PayItem> _items = [...r.extras.items];
  late final _note = TextEditingController(text: r.note);
  final _reason = TextEditingController();
  bool _saving = false;

  static String _fmt(double? v) => v == null || v == 0 ? '' : _n(v);
  static double? _parse(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  /// 各欄位的小數位數與上限，照 ops 0110 payroll_entries 欄位定義：
  /// 天數 numeric(4,1) 0–31；時數 0–744、加班 0–400（都要 0.5 的倍數，見 [_halfError]）；金額 numeric(10,2)
  String? _error(TextEditingController c) {
    final (decimals, max) = _rules[c]!;
    return payrollNumberError(c.text, decimals: decimals, max: max);
  }
  Map<TextEditingController, (int, int)> get _rules => {
    _qty: r.payType == 'daily' ? (1, 31) : (1, 744),
    _ot1: (1, 400),
    _ot2: (1, 400),
    _bonus: (2, 99999999),
    _ins: (2, 99999999),
    _ded: (2, 99999999),
    _att: (2, 99999999),
    _lab: (2, 99999999),
    _hea: (2, 99999999),
    _dep: (2, 99999999),
    _tax: (2, 99999999),
    _cash: (2, 99999999),
  };

  /// 舊的「勞健保自付額」（合計）：只有已經填過的才顯示，之後分開填勞保、健保
  bool get _legacyIns => r.payType != 'daily' && r.insurance != 0;

  /// 這個人會用到的數字欄位（欄位、哪一類）
  List<(TextEditingController, String)> get _fields => [
        if (r.payType == 'daily') (_qty, '天數'),
        if (r.payType == 'hourly') (_qty, '時數'),
        if (r.payType == 'monthly') (_ot1, '時數'),
        if (r.payType == 'monthly' && _lsa) (_ot2, '時數'),
        (_bonus, '金額'),
        (_att, '金額'),
        if (r.payType != 'daily') ...[(_lab, '金額'), (_hea, '金額'), (_dep, '金額')],
        (_tax, '金額'),
        if (_legacyIns) (_ins, '金額'),
        (_ded, '金額'),
        (_cash, '金額'),
      ];

  /// 有欄位格式、小數位數、上限不對或時數不是 0.5 的倍數：停止試算、不能存。回傳要顯示的哪一類（時數／天數／金額）
  String? get _blocked {
    for (final (c, kind) in _fields) {
      if (_error(c) != null) return kind;
    }
    return _halfError != null ? '時數' : null;
  }

  /// 畫面上現在填的其他項目（日薪制不扣勞健保）
  PayExtras get _extras {
    final ins = r.payType != 'daily';
    return PayExtras(
        attendanceBonus: _parse(_att) ?? 0,
        laborIns: ins ? _parse(_lab) ?? 0 : 0,
        healthIns: ins ? _parse(_hea) ?? 0 : 0,
        dependentsIns: ins ? _parse(_dep) ?? 0 : 0,
        incomeTax: _parse(_tax) ?? 0,
        cashPaid: _parse(_cash) ?? 0,
        items: _items);
  }

  /// 領現是實發裡發現金的那一部分，不能比實發多
  String? get _cashError {
    final g = _preview, c = _parse(_cash) ?? 0;
    return g != null && c > g ? '領現金額不能比實發金額多（實發 ${ntd(g)}）' : null;
  }
  bool get _lsa => r.otMode == 'lsa';
  double? get _auto => r.payType == 'daily' ? r.autoDays : r.autoHours;

  @override
  void dispose() {
    for (final c in [_qty, _ot1, _ot2, _bonus, _ins, _ded, _att, _lab, _hea, _dep, _tax, _cash, _note, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 天數／時數：留空或跟打卡帶入的一樣＝不算手動改（存 null，用帶入值；秘書 2026-11-15）
  double? get _override {
    final v = _parse(_qty);
    return v == null || v == _auto ? null : v;
  }

  /// 核准的加班（加班申請核准後自動帶入）；跟目前填的不一樣時可以一鍵改回
  Widget _approvedOt(PayrollRow r) {
    final a1 = r.autoOtHours ?? 0, a2 = r.autoOtHours2 ?? 0;
    final same = _lsa ? (_parse(_ot1) ?? 0) == a1 && (_parse(_ot2) ?? 0) == a2 : (_parse(_ot1) ?? 0) == a1 + a2;
    final text = a1 + a2 == 0
        ? '這個月沒有核准的加班'
        : _lsa
            ? '核准的加班：前 2 小時 ${_n(a1)}、第 3 小時起 ${_n(a2)} 小時'
            : '核准的加班 ${_n(a1 + a2)} 小時';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Icon(same ? Icons.check_circle_outline : Icons.edit_note, size: 18, color: same ? AppColors.good : AppColors.warn),
        const SizedBox(width: 6),
        Expanded(
            child: Text(same ? '$text（自動帶入）' : '$text；目前填的不一樣，之後核准的不會自動帶入',
                style: TextStyle(color: same ? AppColors.muted : AppColors.warn, fontSize: AppType.small))),
        if (!same)
          TextButton(
              onPressed: () => setState(() {
                    _ot1.text = _fmt(_lsa ? a1 : a1 + a2);
                    _ot2.text = _fmt(_lsa ? a2 : 0);
                  }),
              child: const Text('改回核准的')),
      ]),
    );
  }

  /// 時數、加班時數只能 0.5 的倍數（老闆 2026-11-15）
  String? get _halfError {
    final fields = [
      if (r.payType == 'hourly') _parse(_qty),
      if (r.payType == 'monthly') _parse(_ot1),
      if (r.payType == 'monthly' && _lsa) _parse(_ot2),
    ];
    return fields.any((v) => v != null && !isHalfHour(v)) ? '時數只能填 0.5 小時的倍數（例如 4、4.5）' : null;
  }

  int? get _preview => payrollTotal(
        payType: r.payType,
        base: r.baseAmount,
        days: r.payType == 'daily' ? (_override ?? _auto) : null,
        hours: r.payType == 'hourly' ? (_override ?? _auto) : null,
        otHours: r.payType == 'monthly' ? _parse(_ot1) ?? 0 : 0,
        otHours2: r.payType == 'monthly' && _lsa ? _parse(_ot2) ?? 0 : 0,
        otMode: r.otMode,
        otRate: r.otRate,
        bonus: _parse(_bonus) ?? 0,
        insurance: _legacyIns ? _parse(_ins) ?? 0 : 0,
        deduction: _parse(_ded) ?? 0,
        extras: _extras,
      );

  Future<void> _save() async {
    if (_blocked != null || _cashError != null) return;
    setState(() => _saving = true);
    try {
      final o = _override;
      await AppScope.of(context).repo.savePayrollEntry(widget.membership.storeId, r.personId, widget.month,
          days: r.payType == 'daily' ? o : null,
          hours: r.payType == 'hourly' ? o : null,
          otHours: r.payType == 'monthly' ? _parse(_ot1) ?? 0 : 0,
          otHours2: r.payType == 'monthly' && _lsa ? _parse(_ot2) ?? 0 : 0,
          bonus: _parse(_bonus) ?? 0,
          insurance: _legacyIns ? _parse(_ins) ?? 0 : 0,
          deduction: _parse(_ded) ?? 0,
          extras: _extras,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  Widget _num(TextEditingController c, String label, {String? helper}) => TextField(
        controller: c,
        enabled: r.editable,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            labelText: label, helperText: helper, helperMaxLines: 3, errorText: _error(c), errorMaxLines: 2),
      );

  Widget _ro(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.muted)),
          const SizedBox(width: 16),
          Expanded(child: Text(value, textAlign: TextAlign.right)),
        ]),
      );

  Widget _head(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 2),
        child: Text(text, style: TextStyle(color: AppColors.primary, fontSize: AppType.small, fontWeight: AppFont.heading)),
      );

  /// 自訂項目：新增一項（收入或支出、名稱、金額）
  Future<void> _addItem(bool income) async {
    final name = TextEditingController(), amount = TextEditingController();
    String? err;
    final item = await showDialog<PayItem>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(income ? '新增收入項目' : '新增支出項目'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                autofocus: true,
                maxLength: payItemLabelMax,
                decoration: InputDecoration(labelText: '項目名稱', hintText: income ? '例如：交通津貼' : '例如：制服費')),
            TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(labelText: '金額', errorText: err, errorMaxLines: 2)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
            FilledButton(
                onPressed: () {
                  final e = name.text.trim().isEmpty
                      ? '請填項目名稱'
                      : payrollNumberError(amount.text, decimals: 2, max: 9999999) ??
                          ((double.tryParse(amount.text.trim()) ?? 0) <= 0 ? '金額要大於 0' : null);
                  if (e != null) return set(() => err = e);
                  Navigator.pop(d, PayItem(income: income, label: name.text.trim(), amount: double.parse(amount.text.trim())));
                },
                child: const Text('新增')),
          ],
        ),
      ),
    );
    name.dispose();
    amount.dispose();
    if (item != null && mounted) setState(() => _items.add(item));
  }

  /// 自訂項目（收入或支出那一邊）：每一項可以拿掉；最多 [payItemsMax] 項
  List<Widget> _itemRows(bool income) => [
        for (final i in _items)
          if (i.income == income)
            Row(children: [
              Expanded(child: Text(i.label)),
              Text('${income ? '' : '−'}${ntd(i.amount)}'),
              IconButton(
                  tooltip: '拿掉「${i.label}」',
                  onPressed: () => setState(() => _items.remove(i)),
                  icon: const Icon(Icons.close, size: 20)),
            ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              onPressed: _items.length >= payItemsMax ? null : () => _addItem(income),
              icon: const Icon(Icons.add, size: 18),
              label: Text(income ? '自己加一個收入項目' : '自己加一個支出項目')),
        ),
      ];

  /// 已發布：清楚的唯讀文字（不是整片灰掉的輸入框）
  Widget _readOnly() {
    final unit = r.payType == 'daily' ? '天' : '小時';
    final q = r.payType == 'daily' ? r.days : r.hours;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: AppColors.warn), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(Icons.lock_outline, color: AppColors.warn, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('已發布，無法編輯（要改請老闆重新開啟這個月）', style: TextStyle(color: AppColors.warn))),
        ]),
      ),
      const SizedBox(height: 8),
      if (r.payType != 'monthly')
        _ro(r.payType == 'daily' ? '上班天數' : '上班時數',
            '${_n(q ?? 0)} $unit${_auto == null ? '' : (q == _auto ? '（打卡帶入）' : '（已手動調整，原始帶入 ${_n(_auto!)} $unit）')}'),
      if (r.payType == 'monthly') ...[
        if (_lsa) ...[
          _ro('加班時數（前 2 小時 ×1.34）', '${_n(r.otHours)} 小時'),
          _ro('加班時數（第 3 小時起 ×1.67）', '${_n(r.otHours2)} 小時'),
        ] else
          _ro('加班時數', '${_n(r.otHours + r.otHours2)} 小時 × ${_n(r.otRate)} 元'),
      ],
      const Divider(height: 24),
      PayslipTable(
          slip: PayrollSlip.fromPayrollRow(r, widget.month, widget.membership.storeName, companyName: widget.companyName)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!r.editable) {
      return Scaffold(appBar: AppBar(title: Text('${r.name}・${widget.month.month} 月')), body: _readOnly());
    }
    final unit = r.payType == 'daily' ? '天' : '小時';
    final g = _preview;
    return Scaffold(
      appBar: AppBar(title: Text('${r.name}・${widget.month.month} 月')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        InfoLine(
            text: '${payrollTypeLabel(r.payType)} ${r.baseAmount == null ? '（沒有薪資）' : ntd(r.baseAmount!)}',
            icon: Icons.payments_outlined,
            detail: '薪資在「員工資料」改；改完回這裡按重新帶入。'),
        if (r.payType != 'monthly')
          _num(_qty, r.payType == 'daily' ? '上班天數' : '上班時數',
              helper: _auto == null
                  ? (r.payType == 'hourly' ? '手動填，0.5 小時的倍數' : '手動填')
                  : '留空會使用打卡帶入的 ${_n(_auto!)} $unit（只算已確認的${r.payType == 'hourly' ? '，每段四捨五入到半小時' : ''}）；改了會保留原始值和修改紀錄'),
        if (r.payType != 'monthly' && _auto != null && _override != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: () => setState(() => _qty.text = _n(_auto!)), child: Text('改回打卡帶入的 ${_n(_auto!)} $unit')),
          ),
        if (r.payType == 'monthly') ...[
          if (_lsa) ...[
            _num(_ot1, '加班時數：每次前 2 小時（×1.34）'),
            _num(_ot2, '加班時數：每次第 3 小時起（×1.67）'),
          ] else
            _num(_ot1, '加班時數', helper: '× ${_n(r.otRate)} 元／小時'),
          // ops 0127：核准的加班自動帶入；手動改過的不會被蓋掉，可以一鍵改回
          if (r.autoOtHours != null) _approvedOt(r),
        ],
        if (_halfError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_halfError!, style: TextStyle(color: AppColors.bad, fontSize: AppType.small)),
          ),
        _head('收入（有填金額的才會出現在薪資單上）'),
        _num(_att, '全勤獎金'),
        _num(_bonus, '獎金'),
        ..._itemRows(true),
        _head('支出'),
        if (r.payType != 'daily') ...[
          _num(_lab, '勞保費（自付）', helper: '照投保單位的金額手動填；勞保、健保、眷屬健保新月份會先帶上個月的'),
          _num(_hea, '健保費（自付）'),
          _num(_dep, '眷屬健保費'),
        ],
        _num(_tax, '所得稅（代扣）'),
        if (_legacyIns) _num(_ins, '勞健保自付額（舊的合計欄位）', helper: '之後請分開填勞保、健保；這一格改成空白就不會再出現'),
        _num(_ded, '其他扣項'),
        ..._itemRows(false),
        _head('發薪方式'),
        TextField(
          controller: _cash,
          enabled: r.editable,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: '領現金額',
              helperText: '實發金額裡發現金的部分（沒有就留空）；實際入帳＝實發−領現',
              helperMaxLines: 3,
              errorText: _error(_cash) ?? (_blocked == null ? _cashError : null),
              errorMaxLines: 2),
        ),
        const SizedBox(height: 8),
        TextField(controller: _note, enabled: r.editable, maxLength: 200, decoration: const InputDecoration(labelText: '備註（薪資單上看得到）')),
        TextField(controller: _reason, enabled: r.editable, maxLength: 200, decoration: const InputDecoration(labelText: '修改原因（記在修改紀錄，可空白）')),
        const SizedBox(height: 12),
        // 數字格式不對時不顯示新的試算（避免看起來像算好了）
        _blocked != null
            ? Text('實際入帳金額：$_blocked格式待修正，暫不計算',
                style: TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading, color: AppColors.bad))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 老闆 2026-11-18：「實發金額」改叫「實際入帳金額」；有領現時先列實領金額
                if (g != null && (_parse(_cash) ?? 0) > 0 && _cashError == null) ...[
                  Text('實際入帳金額 ${ntd(g - roundYuan(_parse(_cash)!))}',
                      style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading)),
                  Text('實領 ${ntd(g)}・領現 ${ntd(_parse(_cash)!)}', style: TextStyle(color: AppColors.muted)),
                ] else
                  Text('實際入帳金額 ${g == null ? '—' : ntd(g)}',
                      style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading)),
              ]),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: _saving || _blocked != null || _cashError != null ? null : _save, child: Text(_saving ? '儲存中…' : '儲存')),
      ]),
    );
  }
}

/// 我的薪資單（員工本人：綁定經老闆確認、老闆或店長已發布的月份）
class MyPayslipsScreen extends StatefulWidget {
  const MyPayslipsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<MyPayslipsScreen> createState() => _MyPayslipsScreenState();
}

class _MyPayslipsScreenState extends State<MyPayslipsScreen> {
  late Future<List<PayrollSlip>> _future = AppScope.of(context).repo.myPayslips(widget.membership.storeId);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('我的薪資單')),
        body: FutureBuilder<List<PayrollSlip>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorView(
                  message: friendlyError(snap.error!),
                  onRetry: () => setState(() => _future = AppScope.of(context).repo.myPayslips(widget.membership.storeId)));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data!.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: InfoLine(text: '還沒有發布的薪資單', icon: Icons.receipt_long_outlined, detail: '老闆或店長發布那個月的薪資後，這裡就看得到。'),
              );
            }
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              for (final s in snap.data!) PayslipCard(slip: s),
            ]);
          },
        ),
      );
}

/// 薪資單的表格（老闆 2026-11-17 指定的格式）：分「收入／支出」兩欄、有金額才列；
/// 下面收入合計／支出合計、實際入帳金額（有領現才多「實領金額」「領現金額」）、備註欄。
class PayslipTable extends StatelessWidget {
  const PayslipTable({super.key, required this.slip});
  final PayrollSlip slip;

  static String _m(double v) => v < 0 ? '−${ntd(-v.round())}' : ntd(v.round());

  Widget _column(String head, List<SlipLine> lines, String totalLabel, double total) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(head, style: TextStyle(color: AppColors.primary, fontSize: AppType.small, fontWeight: AppFont.heading)),
          const SizedBox(height: 4),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.label),
                    if (l.detail.isNotEmpty) Text(l.detail, style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
                  ]),
                ),
                const SizedBox(width: 6),
                Text(_m(l.amount)),
              ]),
            ),
          if (lines.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('—', style: TextStyle(color: AppColors.muted))),
          const Spacer(),
          const Divider(height: 16),
          Row(children: [
            Expanded(child: Text(totalLabel, style: TextStyle(color: AppColors.muted, fontSize: AppType.small))),
            Text(_m(total), style: const TextStyle(fontWeight: AppFont.heading)),
          ]),
        ],
      );

  Widget _total(String label, String value, {bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: big ? AppFont.heading : null))),
          Text(value, style: big ? const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading) : null),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cash = slip.cashPaid;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _column('收入', slip.incomeLines(), '收入合計', slip.incomeTotal)),
          const VerticalDivider(width: 24),
          Expanded(child: _column('支出', slip.deductionLines(), '支出合計', slip.deductionTotal)),
        ]),
      ),
      const Divider(height: 20),
      // 老闆 2026-11-18：「實發金額」改叫「實際入帳金額」；有領現時多列實領、領現
      if (cash == 0)
        _total('實際入帳金額', slip.gross == null ? '—' : ntd(slip.gross!.round()), big: true)
      else ...[
        _total('實領金額', slip.gross == null ? '—' : ntd(slip.gross!.round())),
        _total('領現金額', ntd(cash.round())),
        _total('實際入帳金額', slip.transfer == null ? '—' : ntd(slip.transfer!.round()), big: true),
      ],
      // 備註欄：一定有這一欄，沒寫就空著（老闆 2026-11-18）
      const Divider(height: 20),
      Text('備註', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      const SizedBox(height: 2),
      Text(slip.note == null || slip.note!.trim().isEmpty ? '—' : slip.note!,
          style: TextStyle(color: slip.note == null || slip.note!.trim().isEmpty ? AppColors.muted : null)),
    ]);
  }
}

/// 一張薪資單：抬頭（公司登記全名）、年月、姓名（全名）、收入／支出、備註。員工直接在 App 看（老闆 2026-11-18 拿掉列印）
class PayslipCard extends StatelessWidget {
  const PayslipCard({super.key, required this.slip});
  final PayrollSlip slip;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(slip.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
            Text('${slip.month.year} 年 ${slip.month.month} 月薪資單', textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('姓名：${slip.personName}'),
            const Divider(height: 20),
            PayslipTable(slip: slip),
          ]),
        ),
      );
}
