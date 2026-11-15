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
  const PayrollScreen({super.key, required this.membership, required this.attendanceEnabled, this.onOpenStaff});
  final Membership membership;
  final bool attendanceEnabled; // 有開打卡的店：時數、天數從已確認的出勤帶入
  final Future<void> Function()? onOpenStaff; // 缺薪率時「前往員工資料」
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(v * 10 % 1 == 0 ? 1 : 2);

/// 載入的結果和它是哪個月份綁在一起：切月時畫面上還是舊月份的資料，所有操作都用這個 month，不用 [_PayrollScreenState._month]
typedef _MonthData = ({DateTime month, PayrollSettings settings, PayrollReport report, List<PayrollRow> rows});

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
    ]);
    return (month: m, settings: r[0] as PayrollSettings, report: r[1] as PayrollReport, rows: r[2] as List<PayrollRow>);
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
        !await _confirm('重新帶入', '重新帶入薪率、計薪方式${widget.attendanceEnabled ? '和打卡時數' : ''}。手動填的天數、時數、獎金、勞健保、加班時數都不會動。', '重新帶入')) {
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
                '要恢復：回到薪資清單點他的名字，按「取消不計薪」，有薪率後再按「重新帶入」。'
                '要領薪的人請不要設，改到「員工資料」新增薪率。'
            : '取消後這個人回到應計薪名單（之後每個還沒發布的月份都算），要有薪率、按「重新帶入」後才能發布。',
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

  void _print(DateTime month, List<PayrollRow> rows) {
    final slips = [
      for (final r in rows)
        if (!r.hidden && r.gross != null) PayrollSlip.fromPayrollRow(r, month, widget.membership.storeName),
    ];
    if (slips.isEmpty) return;
    if (!printPayslips(slips)) showMessage(context, '瀏覽器擋住了新視窗，請允許這個網站開啟彈出視窗', error: true);
  }

  /// locked：載入中（切月、重新整理）或正在做事，所有按鈕都先停用
  Widget _summary(_MonthData d, bool locked) {
    final r = d.report, s = d.settings, rows = d.rows, month = d.month;
    final below = rows.where((x) => x.otBelowLaw).toList();
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
              Text('$missingCount 人缺少薪率，還不能發布',
                  style: TextStyle(color: AppColors.bad, fontSize: AppType.small, fontWeight: AppFont.heading)),
              if (r.missingNames.isNotEmpty)
                Text(r.missingNames.join('、'), style: TextStyle(color: AppColors.bad, fontSize: AppType.small)),
              Text(
                  '沒有薪率的先到「員工資料」新增，薪率是之後才加的按「重新帶入」${_owner ? '；不領薪的人可以在下面點他設為不計薪' : '；不領薪的人請老闆設為不計薪'}',
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
        if (below.isNotEmpty) ...[
          Text('加班費可能低於勞基法第 24 條（元／小時）',
              style: TextStyle(color: AppColors.warn, fontSize: AppType.small, fontWeight: AppFont.heading)),
          for (final x in below)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 12, runSpacing: 2, children: [
                Text(x.name, style: const TextStyle(fontSize: AppType.small, fontWeight: AppFont.heading)),
                Text('目前設定 ${_n(x.otRate)}', style: const TextStyle(fontSize: AppType.small)),
                Text('依法比較：前 2 小時 ${_n(x.lsaFirst2!)}、第 3 小時起 ${_n(x.lsaFrom3!)}',
                    style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!r.published) ...[
            FilledButton(onPressed: locked || missing ? null : () => _publish(d), child: const Text('發布給員工')),
            OutlinedButton(onPressed: locked ? null : () => _prepare(month, true), child: const Text('重新帶入')),
          ],
          if (r.published && _owner) OutlinedButton(onPressed: locked ? null : () => _reopen(month), child: const Text('重新開啟')),
          OutlinedButton.icon(
              onPressed: locked ? null : () => _print(month, rows),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('列印全部薪資單')),
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
  Widget _row(DateTime month, PayrollRow r, bool locked, bool published) {
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
          ? '應計薪但還沒帶入（沒有薪率，或薪率是之後才加的）${_owner && !published ? '・點這裡可設為不計薪' : ''}'
          : r.exempt
              ? '不計薪${_owner && !published ? '・點這裡取消' : ''}'
              : [
                  payrollTypeLabel(r.payType) + (r.baseAmount != null ? ' ${ntd(r.baseAmount!)}' : ''),
                  if (_qty(r).isNotEmpty) _qty(r),
                  if (r.bonus != 0) '獎金 ${ntd(r.bonus)}',
                  if (r.insurance != 0) '勞健保 −${ntd(r.insurance)}',
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
                      builder: (_) => PayrollEditScreen(membership: widget.membership, month: month, row: r)));
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
              if (d.report.status == null)
                SectionCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${d.month.month} 月薪資還沒建立', style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
                    const SizedBox(height: 6),
                    Text(
                        widget.attendanceEnabled
                            ? '建立時會帶入每個人的薪率，以及這個月「已確認」的打卡時數、天數（待確認的不算）。勞健保自付額預設帶上個月的。'
                            : '這家店還沒開打卡：建立後時數、天數要手動填。勞健保自付額預設帶上個月的。',
                        style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: locked ? null : () => _prepare(d.month, false), child: Text('建立 ${d.month.month} 月薪資')),
                  ]),
                )
              else ...[
                _summary(d, locked),
                const SizedBox(height: 8),
                for (final r in d.rows) _row(d.month, r, locked, d.report.published),
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
  };

  /// 這個人會用到的數字欄位（欄位、哪一類）
  List<(TextEditingController, String)> get _fields => [
        if (r.payType == 'daily') (_qty, '天數'),
        if (r.payType == 'hourly') (_qty, '時數'),
        if (r.payType == 'monthly') (_ot1, '時數'),
        if (r.payType == 'monthly' && _lsa) (_ot2, '時數'),
        (_bonus, '金額'),
        if (r.payType != 'daily') (_ins, '金額'),
      ];

  /// 有欄位格式、小數位數、上限不對或時數不是 0.5 的倍數：停止試算、不能存。回傳要顯示的哪一類（時數／天數／金額）
  String? get _blocked {
    for (final (c, kind) in _fields) {
      if (_error(c) != null) return kind;
    }
    return _halfError != null ? '時數' : null;
  }
  bool get _lsa => r.otMode == 'lsa';
  double? get _auto => r.payType == 'daily' ? r.autoDays : r.autoHours;

  @override
  void dispose() {
    for (final c in [_qty, _ot1, _ot2, _bonus, _ins, _note, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 天數／時數：留空或跟打卡帶入的一樣＝不算手動改（存 null，用帶入值；秘書 2026-11-15）
  double? get _override {
    final v = _parse(_qty);
    return v == null || v == _auto ? null : v;
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
        insurance: r.payType == 'daily' ? 0 : _parse(_ins) ?? 0,
      );

  Future<void> _save() async {
    if (_blocked != null) return;
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

  void _printOne() {
    if (!printPayslips([PayrollSlip.fromPayrollRow(r, widget.month, widget.membership.storeName)])) {
      showMessage(context, '瀏覽器擋住了新視窗，請允許這個網站開啟彈出視窗', error: true);
    }
  }

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
      _ro('計薪方式', '${payrollTypeLabel(r.payType)} ${r.baseAmount == null ? '（沒有薪率）' : ntd(r.baseAmount!)}'),
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
      _ro('獎金', ntd(r.bonus)),
      if (r.payType != 'daily') _ro('勞健保自付額', r.insurance == 0 ? ntd(0) : '−${ntd(r.insurance)}'),
      if (r.note != null && r.note!.isNotEmpty) _ro('備註', r.note!),
      const Divider(height: 24),
      Row(children: [
        const Expanded(child: Text('實發金額', style: TextStyle(fontWeight: AppFont.heading))),
        Text(r.gross == null ? '—' : ntd(r.gross!), style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading)),
      ]),
      const SizedBox(height: 16),
      if (r.gross != null)
        OutlinedButton.icon(
            onPressed: _printOne, icon: const Icon(Icons.print_outlined, size: 18), label: const Text('列印／存成 PDF')),
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
            text: '${payrollTypeLabel(r.payType)} ${r.baseAmount == null ? '（沒有薪率）' : ntd(r.baseAmount!)}',
            icon: Icons.payments_outlined,
            detail: '薪率在「員工資料」改；改完回這裡按重新帶入。'),
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
          if (r.otBelowLaw)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('可能低於勞基法第 24 條：${r.otBelowLawText}', style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
            ),
        ],
        if (_halfError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_halfError!, style: TextStyle(color: AppColors.bad, fontSize: AppType.small)),
          ),
        _num(_bonus, '獎金'),
        if (r.payType != 'daily') _num(_ins, '勞健保自付額', helper: '照投保單位的金額手動填；新月份會先帶上個月的'),
        TextField(controller: _note, enabled: r.editable, maxLength: 200, decoration: const InputDecoration(labelText: '備註（薪資單上看得到）')),
        TextField(controller: _reason, enabled: r.editable, maxLength: 200, decoration: const InputDecoration(labelText: '修改原因（記在修改紀錄，可空白）')),
        const SizedBox(height: 12),
        // 數字格式不對時不顯示新的試算（避免看起來像算好了）
        _blocked != null
            ? Text('實發金額：$_blocked格式待修正，暫不計算',
                style: TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading, color: AppColors.bad))
            : Text('實發金額 ${g == null ? '—' : ntd(g)}',
                style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving || _blocked != null ? null : _save, child: Text(_saving ? '儲存中…' : '儲存')),
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
