import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/payslip_print.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 薪資（老闆、店長；ops 0110）：每月帶入薪率與打卡時數 → 逐人填獎金、勞健保、加班 → 發布給員工看薪資單。
/// 店長看不到、改不到自己的那一列，月報也不給總計（避免反推）。發布後不能改，老闆寫原因才能重新開啟。
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, required this.membership, required this.attendanceEnabled});
  final Membership membership;
  final bool attendanceEnabled; // 有開打卡的店：時數、天數從已確認的出勤帶入
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(v * 10 % 1 == 0 ? 1 : 2);

class _PayrollScreenState extends State<PayrollScreen> {
  late DateTime _month = DateTime(bizToday().year, bizToday().month - 1, 1); // 預設上個月
  late Future<({PayrollSettings settings, PayrollReport report, List<PayrollRow> rows})> _future = _load();
  bool _busy = false;

  Repository get _repo => AppScope.of(context).repo;
  bool get _owner => widget.membership.role == Role.owner;
  String get _store => widget.membership.storeId;

  Future<({PayrollSettings settings, PayrollReport report, List<PayrollRow> rows})> _load() async {
    final repo = AppScope.of(context).repo;
    final r = await Future.wait([
      repo.payrollSettings(_store),
      repo.payrollReport(_store, _month),
      repo.payrollMonth(_store, _month),
    ]);
    return (settings: r[0] as PayrollSettings, report: r[1] as PayrollReport, rows: r[2] as List<PayrollRow>);
  }

  void _reload() => setState(() => _future = _load());

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

  Future<bool> _confirm(String title, String body, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(ok)),
          ],
        ),
      ) ==
      true;

  Future<void> _prepare(bool again) async {
    if (again &&
        !await _confirm('重新帶入', '重新帶入薪率、計薪方式${widget.attendanceEnabled ? '和打卡時數' : ''}。手動填的天數、時數、獎金、勞健保、加班時數都不會動。', '重新帶入')) {
      return;
    }
    await _run(() => _repo.preparePayroll(_store, _month), again ? '已重新帶入' : '已建立 ${_month.month} 月薪資');
  }

  Future<void> _publish(PayrollReport r) async {
    if (!await _confirm('發布 ${_month.month} 月薪資', '發布後員工看得到自己的薪資單，而且不能再改（要改得請老闆重新開啟）。', '發布')) return;
    await _run(() => _repo.publishPayroll(_store, _month), '已發布');
  }

  Future<void> _reopen() async {
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
    await _run(() => _repo.reopenPayroll(_store, _month, reason), '已重新開啟');
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

  void _print(List<PayrollRow> rows) {
    final slips = [
      for (final r in rows)
        if (!r.hidden && r.gross != null) PayrollSlip.fromPayrollRow(r, _month, widget.membership.storeName),
    ];
    if (slips.isEmpty) return;
    if (!printPayslips(slips)) showMessage(context, '瀏覽器擋住了新視窗，請允許這個網站開啟彈出視窗', error: true);
  }

  Widget _summary(PayrollReport r, PayrollSettings s, List<PayrollRow> rows) {
    final below = rows.where((x) => x.otBelowLaw).toList();
    final hidden = rows.any((x) => x.hidden);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('${_month.year} 年 ${_month.month} 月・${r.people} 人',
                  style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading))),
          Text(r.published ? '已發布' : '草稿', style: TextStyle(color: r.published ? AppColors.good : AppColors.warn)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 24, runSpacing: 8, children: [
          _figure('薪資總計', r.total != null ? ntd(r.total!) : (hidden ? '—' : '算不出來')),
          _figure('營業額', r.revenue != null ? ntd(r.revenue!) : '—'),
          _figure('人事成本率', pct(r.costRate)),
        ]),
        if (hidden)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('不含你自己那一列，看不到總計和成本率；其他人合計 ${ntd(r.visibleTotal ?? 0)}',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          ),
        if (r.missingRate > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${r.missingRate} 人沒有薪率，先到「員工資料」新增，再按重新帶入',
                style: TextStyle(color: AppColors.bad, fontSize: AppType.small)),
          ),
        const Divider(height: 24),
        Row(children: [
          Expanded(
            child: Text('加班費：${otModeLabel(s.otMode)}${s.otMode == 'fixed' ? ' ${_n(s.otRate)} 元／小時' : '（月薪÷240，1.34／1.67）'}',
                style: const TextStyle(fontSize: AppType.small)),
          ),
          if (_owner) TextButton(onPressed: _busy ? null : () => _editOvertime(s), child: const Text('修改')),
        ]),
        if (below.isNotEmpty)
          Text(
              '可能低於勞基法第 24 條：${below.map((x) => '${x.name} 依勞基法前 2 小時約 ${x.lsaRate!.toStringAsFixed(0)} 元').join('、')}',
              style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!r.published) ...[
            FilledButton(onPressed: _busy || r.missingRate > 0 ? null : () => _publish(r), child: const Text('發布給員工')),
            OutlinedButton(onPressed: _busy ? null : () => _prepare(true), child: const Text('重新帶入')),
          ],
          if (r.published && _owner) OutlinedButton(onPressed: _busy ? null : _reopen, child: const Text('重新開啟')),
          OutlinedButton.icon(
              onPressed: () => _print(rows), icon: const Icon(Icons.print_outlined, size: 18), label: const Text('列印全部薪資單')),
        ]),
      ]),
    );
  }

  Widget _figure(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        Text(value, style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.figure)),
      ]);

  String _qty(PayrollRow r) {
    String mark(double? auto, bool edited, String unit) =>
        edited ? '（手動改，帶入 ${auto == null ? '無' : '${_n(auto)} $unit'}）' : (auto != null ? '（打卡）' : '');
    return switch (r.payType) {
      'daily' => '${_n(r.days ?? 0)} 天${mark(r.autoDays, r.daysEdited, '天')}',
      'hourly' => '${_n(r.hours ?? 0)} 小時${mark(r.autoHours, r.hoursEdited, '小時')}',
      _ => r.otHours + r.otHours2 > 0 ? '加班 ${_n(r.otHours + r.otHours2)} 小時' : '',
    };
  }

  Widget _row(PayrollRow r) {
    if (r.hidden) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(r.name),
        subtitle: const Text('你自己的薪資由老闆處理，這裡看不到'),
        leading: const Icon(Icons.lock_outline),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(r.name),
      subtitle: Text([
        payrollTypeLabel(r.payType) + (r.baseAmount != null ? ' ${ntd(r.baseAmount!)}' : ''),
        if (_qty(r).isNotEmpty) _qty(r),
        if (r.bonus != 0) '獎金 ${ntd(r.bonus)}',
        if (r.insurance != 0) '勞健保 −${ntd(r.insurance)}',
        if (r.missingRate) '沒有薪率',
      ].join('・')),
      trailing: Text(r.gross == null ? '—' : ntd(r.gross!),
          style: TextStyle(fontSize: AppType.title, color: r.gross == null ? AppColors.bad : AppColors.text)),
      onTap: () async {
        final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
            builder: (_) => PayrollEditScreen(membership: widget.membership, month: _month, row: r)));
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
            if (snap.hasError) {
              return ListView(padding: const EdgeInsets.all(16), children: [
                header,
                ErrorView(message: friendlyError(snap.error!), onRetry: _reload),
              ]);
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final d = snap.data!;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              header,
              if (d.report.status == null)
                SectionCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_month.month} 月薪資還沒建立', style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
                    const SizedBox(height: 6),
                    Text(
                        widget.attendanceEnabled
                            ? '建立時會帶入每個人的薪率，以及這個月「已確認」的打卡時數、天數（待確認的不算）。勞健保自付額預設帶上個月的。'
                            : '這家店還沒開打卡：建立後時數、天數要手動填。勞健保自付額預設帶上個月的。',
                        style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _busy ? null : () => _prepare(false), child: Text('建立 ${_month.month} 月薪資')),
                  ]),
                )
              else ...[
                _summary(d.report, d.settings, d.rows),
                const SizedBox(height: 8),
                for (final r in d.rows) _row(r),
              ],
            ]);
          },
        ),
      );
}

/// 編輯一個人這個月的薪資；儲存前先試算（和資料庫同一套公式）
class PayrollEditScreen extends StatefulWidget {
  const PayrollEditScreen({super.key, required this.membership, required this.month, required this.row});
  final Membership membership;
  final DateTime month;
  final PayrollRow row;
  @override
  State<PayrollEditScreen> createState() => _PayrollEditScreenState();
}

class _PayrollEditScreenState extends State<PayrollEditScreen> {
  PayrollRow get r => widget.row;
  late final _qty = TextEditingController(
      text: switch (r.payType) { 'daily' => _fmt(r.days), 'hourly' => _fmt(r.hours), _ => '' });
  late final _ot1 = TextEditingController(text: _fmt(r.otMode == 'lsa' ? r.otHours : r.otHours + r.otHours2));
  late final _ot2 = TextEditingController(text: _fmt(r.otHours2));
  late final _bonus = TextEditingController(text: _fmt(r.bonus));
  late final _ins = TextEditingController(text: _fmt(r.insurance));
  late final _note = TextEditingController(text: r.note);
  final _reason = TextEditingController();
  bool _saving = false;

  static String _fmt(double? v) => v == null || v == 0 ? '' : _n(v);
  static double? _parse(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());
  bool get _lsa => r.otMode == 'lsa';
  double? get _auto => r.payType == 'daily' ? r.autoDays : r.autoHours;

  @override
  void dispose() {
    for (final c in [_qty, _ot1, _ot2, _bonus, _ins, _note, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 天數／時數：跟打卡帶入的一樣＝不算手動改（存 null）
  double? get _override {
    final v = _parse(_qty);
    if (v == null) return _auto == null ? null : 0;
    return v == _auto ? null : v;
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
        insurance: r.payType == 'daily' ? 0 : _parse(_ins) ?? 0,
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final o = _override;
      await AppScope.of(context).repo.savePayrollEntry(widget.membership.storeId, r.personId, widget.month,
          days: r.payType == 'daily' ? o : null,
          hours: r.payType == 'hourly' ? o : null,
          otHours: r.payType == 'monthly' ? _parse(_ot1) ?? 0 : 0,
          otHours2: r.payType == 'monthly' && _lsa ? _parse(_ot2) ?? 0 : 0,
          bonus: _parse(_bonus) ?? 0,
          insurance: r.payType == 'daily' ? 0 : _parse(_ins) ?? 0,
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
        decoration: InputDecoration(labelText: label, helperText: helper),
      );

  @override
  Widget build(BuildContext context) {
    final unit = r.payType == 'daily' ? '天' : '小時';
    final g = _preview;
    return Scaffold(
      appBar: AppBar(title: Text('${r.name}・${widget.month.month} 月')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        InfoLine(
            text: '${payrollTypeLabel(r.payType)} ${r.baseAmount == null ? '（沒有薪率）' : ntd(r.baseAmount!)}',
            icon: Icons.payments_outlined,
            detail: '薪率在「員工資料」改；改完回這裡按重新帶入。'),
        if (!r.editable)
          Text('這個月已經發布，不能再改', style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
        if (r.payType != 'monthly')
          _num(_qty, r.payType == 'daily' ? '上班天數' : '上班時數',
              helper: _auto == null ? '手動填' : '打卡帶入 ${_n(_auto!)} $unit（只算已確認的）；改了會保留原始值和修改紀錄'),
        if (r.payType != 'monthly' && _auto != null && _override != null && r.editable)
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
          if (r.otBelowLaw)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('可能低於勞基法第 24 條：依勞基法前 2 小時加班時薪約 ${r.lsaRate!.toStringAsFixed(0)} 元',
                  style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
            ),
        ],
        _num(_bonus, '獎金'),
        if (r.payType != 'daily') _num(_ins, '勞健保自付額', helper: '照投保單位的金額手動填；新月份會先帶上個月的'),
        TextField(controller: _note, enabled: r.editable, maxLength: 200, decoration: const InputDecoration(labelText: '備註（薪資單上看得到）')),
        TextField(controller: _reason, enabled: r.editable, maxLength: 200, decoration: const InputDecoration(labelText: '修改原因（記在修改紀錄，可空白）')),
        const SizedBox(height: 12),
        Text('實發金額 ${g == null ? '—' : ntd(g)}', style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading)),
        const SizedBox(height: 16),
        if (r.editable) FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? '儲存中…' : '儲存')),
        if (!r.editable && r.gross != null)
          OutlinedButton.icon(
            onPressed: () {
              if (!printPayslips([PayrollSlip.fromPayrollRow(r, widget.month, widget.membership.storeName)])) {
                showMessage(context, '瀏覽器擋住了新視窗，請允許這個網站開啟彈出視窗', error: true);
              }
            },
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('列印／存成 PDF'),
          ),
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

/// 一張薪資單（每一項、實發金額、列印）
class PayslipCard extends StatelessWidget {
  const PayslipCard({super.key, required this.slip});
  final PayrollSlip slip;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${slip.storeName} ${slip.month.year} 年 ${slip.month.month} 月',
                style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
            const SizedBox(height: 8),
            for (final l in slip.lines())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.label),
                      if (l.detail.isNotEmpty) Text(l.detail, style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
                    ]),
                  ),
                  Text(l.amount < 0 ? '−${ntd(-l.amount.round())}' : ntd(l.amount.round())),
                ]),
              ),
            const Divider(),
            Row(children: [
              const Expanded(child: Text('實發金額', style: TextStyle(fontWeight: AppFont.heading))),
              Text(slip.gross == null ? '—' : ntd(slip.gross!.round()),
                  style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading)),
            ]),
            if (slip.note != null && slip.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('備註：${slip.note}', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                if (!printPayslips([slip])) showMessage(context, '瀏覽器擋住了新視窗，請允許這個網站開啟彈出視窗', error: true);
              },
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('列印／存成 PDF'),
            ),
          ]),
        ),
      );
}
