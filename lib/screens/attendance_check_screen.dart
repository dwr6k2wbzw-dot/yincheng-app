import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/store_features.dart';
import '../services/attendance_csv.dart';
import '../services/clock.dart';
import '../services/pl_export.dart' deferred as pl;
import '../theme.dart';
import '../widgets/common.dart';

/// 打卡跟班表比對、加班申請（ops 0127，老闆 2026-11-17 六點需求的第 5、6 點）。
/// ⑤ 比班表早到、晚走、遲到、早退超過 30 分鐘，沒排班有打卡、有排班沒打卡都列異常，可以匯出成報表
/// ⑥ 加班要先申請、核准；沒有事先申請的，事後在 App 申請並寫原因。核准的時數自動帶進那個月的薪資（月薪制）

final _md = DateFormat('M/d（E）', 'zh_TW');
final _hmFmt = DateFormat('HH:mm');
String _hm(DateTime? t) => t == null ? '—' : _hmFmt.format(toTaipei(t));

/// 期間：近 7 天／本月／上個月（營業日）
enum _Span { week, month, lastMonth }

({DateTime from, DateTime to}) _spanDates(_Span s) {
  final t = bizToday();
  return switch (s) {
    _Span.week => (from: t.subtract(const Duration(days: 6)), to: t),
    _Span.month => (from: DateTime(t.year, t.month, 1), to: t),
    _Span.lastMonth => (from: DateTime(t.year, t.month - 1, 1), to: DateTime(t.year, t.month, 0)),
  };
}

Widget _spanChips(_Span value, ValueChanged<_Span> onChanged) => Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    for (final (s, label) in [(_Span.week, '近 7 天'), (_Span.month, '本月'), (_Span.lastMonth, '上個月')])
      SelectChip(label: Text(label), selected: value == s, onSelected: (_) => onChanged(s)),
  ],
);

/// 遲到、早退、沒打卡＝紅；早到、晚走、沒排班＝黃
/// 跟班表差超過 30 分鐘（早到、遲到、早退、晚走）和整天沒打卡都標紅（老闆 2026-11-18）
Color _issueColor(String k) => switch (k) {
  'early_in' || 'late_in' || 'early_out' || 'late_out' || 'no_punch' => AppColors.bad,
  _ => AppColors.warn,
};

Widget _pill(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.14),
    border: Border.all(color: color.withValues(alpha: 0.6)),
    borderRadius: BorderRadius.circular(AppRadius.sm),
  ),
  child: Text(
    text,
    style: TextStyle(color: color, fontSize: AppType.small, fontWeight: AppFont.label),
  ),
);

/// 分頁切走再回來不要重讀；別的分頁審核、補登成功（changed 加一）才重讀
mixin _Reload<T extends StatefulWidget> on State<T>, AutomaticKeepAliveClientMixin<T> {
  ValueNotifier<int> get changed;
  void reload();
  @override
  bool get wantKeepAlive => true;
  void _on() {
    if (mounted) reload();
  }

  @override
  void initState() {
    super.initState();
    changed.addListener(_on);
  }

  @override
  void dispose() {
    changed.removeListener(_on);
    super.dispose();
  }
}

// =====================================================================
// 比對班表
// =====================================================================

class ScheduleCheckTab extends StatefulWidget {
  const ScheduleCheckTab({super.key, required this.membership, required this.data, required this.codeTimes, required this.changed});
  final Membership membership;
  final ShiftMonth data;
  final Map<String, String> codeTimes;
  final ValueNotifier<int> changed;
  @override
  State<ScheduleCheckTab> createState() => _ScheduleCheckTabState();
}

class _ScheduleCheckTabState extends State<ScheduleCheckTab> with AutomaticKeepAliveClientMixin, _Reload {
  _Span _span = _Span.week;
  String? _filter; // 只看某一種異常
  late Future<(List<ScheduleCheckRow>, List<ShiftMarkTime>)> _future = _load();
  bool _exporting = false;

  Repository get _repo => AppScope.of(context).repo;
  @override
  ValueNotifier<int> get changed => widget.changed;
  @override
  void reload() => setState(() => _future = _load());

  Future<(List<ScheduleCheckRow>, List<ShiftMarkTime>)> _load() async {
    final d = _spanDates(_span);
    final store = widget.membership.storeId;
    final r = await Future.wait([_repo.scheduleCheck(store, d.from, d.to), _repo.shiftMarkTimes(store)]);
    return (r[0] as List<ScheduleCheckRow>, r[1] as List<ShiftMarkTime>);
  }

  /// 班表用 V（沒開班別代碼）而且還沒設 V 的時間：早到、遲到、早退、晚走比不出來
  bool _needsVTime(List<ShiftMarkTime> times) =>
      !StoreFeatures.of(widget.membership.storeName).shiftCodes && !times.any((t) => t.mark == 'V');

  Future<void> _editTimes() async {
    final changed = await editShiftMarkTimes(context, widget.membership.storeId);
    if (changed && mounted) reload();
  }

  Future<void> _export(List<ScheduleCheckRow> rows) async {
    setState(() => _exporting = true);
    try {
      final d = _spanDates(_span);
      await pl.loadLibrary();
      final name = scheduleCheckCsvName(widget.membership.storeName, d.from, d.to);
      final r = await pl.saveFile(scheduleCheckCsvBytes(rows), name, csvMime);
      if (mounted && r == 'downloaded') showMessage(context, '已下載 $name');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _overtimeLine(ScheduleCheckRow r) {
    if (!r.issues.contains('late_out')) return const SizedBox.shrink();
    final (text, color) = (r.otApproved ?? 0) > 0
        ? ('已核准加班 ${hoursLabel(r.otApproved!)} 小時', AppColors.good)
        : r.otPending
        ? ('加班申請待審', AppColors.warn)
        : ('沒有申請加班', AppColors.muted);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.more_time, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: color, fontSize: AppType.small),
          ),
        ],
      ),
    );
  }

  Widget _rowCard(ScheduleCheckRow r) {
    const offMarks = {'休', '指休', '特休'};
    final times = '${_hm(r.planStart)}–${_hm(r.planEnd)}';
    final plan = r.mark == null
        ? '沒排班'
        : offMarks.contains(r.mark)
        ? '排${r.mark}'
        : r.planStart == null
        ? '班 ${r.mark}（沒設時間）'
        : r.mark!.contains(':')
        ? '班 $times'
        : '班 ${r.mark} $times';
    final noPunch = r.firstIn == null && r.lastOut == null;
    // 差超過 30 分鐘的那個時間標紅
    final inOff = r.issues.contains('early_in') || r.issues.contains('late_in');
    final outOff = r.issues.contains('early_out') || r.issues.contains('late_out');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.personName,
                    style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading),
                  ),
                ),
                Text(
                  _md.format(r.businessDate),
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$plan｜'),
                if (noPunch)
                  const TextSpan(text: '沒有打卡')
                else ...[
                  const TextSpan(text: '打卡 '),
                  TextSpan(text: _hm(r.firstIn), style: inOff ? TextStyle(color: AppColors.bad, fontWeight: AppFont.label) : null),
                  const TextSpan(text: '–'),
                  TextSpan(text: _hm(r.lastOut), style: outOff ? TextStyle(color: AppColors.bad, fontWeight: AppFont.label) : null),
                ],
                if (r.punchPending) const TextSpan(text: '（有待確認的卡）'),
              ]),
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small, fontFeatures: tabular),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final i in r.issues) _pill(r.issueText(i), _issueColor(i))]),
            _overtimeLine(r),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () async => reload(),
      child: FutureBuilder<(List<ScheduleCheckRow>, List<ShiftMarkTime>)>(
        future: _future,
        builder: (context, snap) {
          final rows = snap.data?.$1 ?? const <ScheduleCheckRow>[];
          final times = snap.data?.$2 ?? const <ShiftMarkTime>[];
          final counts = <String, int>{};
          for (final r in rows) {
            for (final i in r.issues) {
              counts[i] = (counts[i] ?? 0) + 1;
            }
          }
          final shown = _filter == null ? rows : rows.where((r) => r.issues.contains(_filter)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _spanChips(
                _span,
                (s) => setState(() {
                  _span = s;
                  _filter = null;
                  _future = _load();
                }),
              ),
              const InfoLine(
                text: '跟班表差超過 30 分鐘就列出來',
                icon: Icons.info_outline,
                detail:
                    '早到、遲到、早退、晚走都是跟班表上的時間比；沒排班（或排休）卻有打卡、有排班卻整天沒打卡也列出來。'
                    '「不採用」的打卡不算，待確認的照樣比。這裡只是報表，不會改打卡、不影響工時。漏打上班／下班在「異常」分頁處理。',
              ),
              if (snap.hasData && _needsVTime(times))
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                  decoration: BoxDecoration(
                    color: AppColors.warn.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.warn),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '「V」還沒設上班時間',
                        style: TextStyle(color: AppColors.warn, fontSize: AppType.title, fontWeight: AppFont.heading),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '班表上的 V 沒有幾點到幾點，早到、遲到、早退、晚走比不出來；先設好平常（和週五六）的時間',
                        style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: _editTimes, child: const Text('設定班的時間')),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  TextButton.icon(onPressed: _editTimes, icon: const Icon(Icons.schedule, size: 18), label: const Text('班的時間')),
                  const Spacer(),
                  if (rows.isNotEmpty)
                    TextButton.icon(
                      onPressed: _exporting ? null : () => _export(rows),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('匯出報表'),
                    ),
                ],
              ),
              if (counts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SelectChip(
                        label: Text('全部 ${rows.length}'),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      for (final k in const ['late_in', 'early_out', 'no_punch', 'early_in', 'late_out', 'no_schedule'])
                        if (counts[k] != null)
                          SelectChip(
                            label: Text('${scheduleIssueLabel(k)} ${counts[k]}'),
                            selected: _filter == k,
                            onSelected: (_) => setState(() => _filter = _filter == k ? null : k),
                          ),
                    ],
                  ),
                ),
              if (snap.hasError) ErrorView(message: friendlyError(snap.error!), onRetry: reload),
              if (!snap.hasData && !snap.hasError)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (snap.hasData && rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('這段期間打卡都跟班表對得上')),
                ),
              for (final r in shown) _rowCard(r),
            ],
          );
        },
      ),
    );
  }
}

// =====================================================================
// 加班（老闆、店長審核）
// =====================================================================

class OvertimeTab extends StatefulWidget {
  const OvertimeTab({super.key, required this.membership, required this.changed});
  final Membership membership;
  final ValueNotifier<int> changed;
  @override
  State<OvertimeTab> createState() => _OvertimeTabState();
}

class _OvertimeTabState extends State<OvertimeTab> with AutomaticKeepAliveClientMixin, _Reload {
  _Span _span = _Span.month;
  late Future<List<OvertimeRequest>> _future = _load();

  Repository get _repo => AppScope.of(context).repo;
  @override
  ValueNotifier<int> get changed => widget.changed;
  @override
  void reload() => setState(() => _future = _load());

  Future<List<OvertimeRequest>> _load() {
    final d = _spanDates(_span);
    return _repo.overtimeList(widget.membership.storeId, d.from, d.to);
  }

  Future<void> _approve(OvertimeRequest o) async {
    final hours = await showDialog<double>(
      context: context,
      builder: (_) => _ApproveDialog(o: o),
    );
    if (hours == null) return;
    await _run(() => _repo.decideOvertime(o.id, true, hours: hours), '已核准，月薪制的會自動帶進這個月的薪資');
  }

  Future<void> _reject(OvertimeRequest o) async {
    final c = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('退回 ${o.personName} 的加班'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(labelText: '退回的原因'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (c.text.trim().length < 2) return;
              Navigator.pop(d, c.text.trim());
            },
            child: const Text('退回'),
          ),
        ],
      ),
    );
    if (note == null) return;
    await _run(() => _repo.decideOvertime(o.id, false, note: note), '已退回');
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) {
        showMessage(context, done);
        widget.changed.value++;
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () async => reload(),
      child: FutureBuilder<List<OvertimeRequest>>(
        future: _future,
        builder: (context, snap) {
          final list = snap.data ?? const <OvertimeRequest>[];
          final pending = list.where((o) => o.pending).toList();
          final done = list.where((o) => !o.pending).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _spanChips(
                _span,
                (s) => setState(() {
                  _span = s;
                  _future = _load();
                }),
              ),
              const InfoLine(
                text: '加班要先申請；沒有事先申請的，事後申請要寫原因',
                icon: Icons.info_outline,
                detail:
                    '加班只能本人在「我的出勤」申請（老闆 2026-11-18）。核准時可以改時數（0.5 小時為一格）；退回要寫原因。'
                    '店長不能核准自己的加班（老闆可以）。核准的加班會自動帶進那個月的薪資（月薪制的加班費；時薪、日薪照打卡時數算）；'
                    '薪資已經發布的月份要老闆重新開啟、再按「重新帶入」。',
              ),
              if (snap.hasError) ErrorView(message: friendlyError(snap.error!), onRetry: reload),
              if (!snap.hasData && !snap.hasError)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (snap.hasData && list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('這段期間沒有加班申請')),
                ),
              if (pending.isNotEmpty) _header('待審 ${pending.length}'),
              for (final o in pending) _card(o),
              if (done.isNotEmpty) _header('已處理'),
              for (final o in done) _card(o),
            ],
          );
        },
      ),
    );
  }

  Widget _header(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
    child: Text(
      t,
      style: TextStyle(color: AppColors.muted, fontSize: AppType.small, fontWeight: AppFont.label),
    ),
  );

  Widget _card(OvertimeRequest o) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: OvertimeCard(
      o: o,
      actions: [
        if (o.canDecide) ...[
          TextButton(onPressed: () => _reject(o), child: const Text('退回')),
          FilledButton.tonal(onPressed: () => _approve(o), child: const Text('核准')),
        ] else if (o.pending)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '要另一位店長或老闆核准',
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
            ),
          ),
      ],
    ),
  );
}

/// 一筆加班申請：誰、哪天、幾小時、事後申請、原因、狀態
class OvertimeCard extends StatelessWidget {
  const OvertimeCard({super.key, required this.o, this.actions = const [], this.showName = true});
  final OvertimeRequest o;
  final List<Widget> actions;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (o.status) {
      'pending' => AppColors.warn,
      'approved' => AppColors.good,
      'rejected' => AppColors.bad,
      _ => AppColors.muted,
    };
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  showName ? '${o.personName}・${_md.format(o.businessDate)}' : _md.format(o.businessDate),
                  style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading),
                ),
              ),
              Text(
                '${hoursLabel(o.hours)} 小時',
                style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading, fontFeatures: tabular),
              ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(o.statusLabel, statusColor),
              _pill(o.afterTheFact ? '事後申請' : '事先申請', o.afterTheFact ? AppColors.warn : AppColors.muted),
            ],
          ),
          const SizedBox(height: 6),
          Text(o.reason, style: const TextStyle(fontSize: AppType.body)),
          const SizedBox(height: 2),
          Text(
            [
              '${o.requestedByName ?? '—'} 送出',
              if (o.decidedAt != null) '${o.decidedByName ?? '—'} ${o.status == 'cancelled' ? '撤回' : '處理'}',
              if (o.decisionNote != null && o.decisionNote!.isNotEmpty) '「${o.decisionNote}」',
            ].join('・'),
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
          ),
          if (actions.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          if (actions.isEmpty) const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.o});
  final OvertimeRequest o;
  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  late double _hours = widget.o.hours;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('核准 ${widget.o.personName} 的加班'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_md.format(widget.o.businessDate)}・申請 ${hoursLabel(widget.o.hours)} 小時',
          style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
        ),
        const SizedBox(height: 12),
        HoursStepper(value: _hours, onChanged: (v) => setState(() => _hours = v)),
        if (_hours != widget.o.hours)
          Text(
            '照 ${hoursLabel(_hours)} 小時核准',
            style: TextStyle(color: AppColors.warn, fontSize: AppType.small),
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(context, _hours), child: const Text('核准')),
    ],
  );
}

/// 0.5 小時一格的時數（0.5～12）
class HoursStepper extends StatelessWidget {
  const HoursStepper({super.key, required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton.outlined(
        tooltip: '少 0.5 小時',
        onPressed: value > 0.5 ? () => onChanged(value - 0.5) : null,
        icon: const Icon(Icons.remove),
      ),
      SizedBox(
        width: 120,
        child: Text(
          '${hoursLabel(value)} 小時',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: AppType.display, fontWeight: AppFont.figure, fontFeatures: tabular),
        ),
      ),
      IconButton.outlined(tooltip: '多 0.5 小時', onPressed: value < 12 ? () => onChanged(value + 0.5) : null, icon: const Icon(Icons.add)),
    ],
  );
}

// =====================================================================
// 加班申請表（只有本人，ops 0128）
// =====================================================================

Future<bool?> showOvertimeForm(
  BuildContext context, {
  required String storeId,
  required String personId,
  required String personName,
  DateTime? date,
  double? hours,
  String? hint,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _OvertimeForm(storeId: storeId, personId: personId, personName: personName, date: date, hours: hours, hint: hint),
);

class _OvertimeForm extends StatefulWidget {
  const _OvertimeForm({required this.storeId, required this.personId, required this.personName, this.date, this.hours, this.hint});
  final String storeId, personId, personName;
  final DateTime? date;
  final double? hours;
  final String? hint;
  @override
  State<_OvertimeForm> createState() => _OvertimeFormState();
}

class _OvertimeFormState extends State<_OvertimeForm> {
  late DateTime _date = widget.date ?? bizToday();
  late double _hours = widget.hours ?? 1;
  final _reason = TextEditingController();
  bool _saving = false;
  /// 送不出去的原因：顯示在表單裡（提示條會被表單蓋住，看起來像按了沒反應；老闆 2026-11-18）
  String? _error;
  bool _tried = false;

  bool get _after => _date.isBefore(bizToday());

  Future<void> _save() async {
    if (_reason.text.trim().length < 2) {
      setState(() {
        _tried = true;
        _error = '請寫加班的原因（至少 2 個字）';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).repo.requestOvertime(widget.storeId, widget.personId, _date, _hours, _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '申請加班・${widget.personName}',
          style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading),
        ),
        const SizedBox(height: 4),
        Text(
          '加班要先申請、店長核准才算；忘了事先申請的，事後申請要寫清楚原因',
          style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.hint!,
            style: TextStyle(color: AppColors.warn, fontSize: AppType.small),
          ),
        ],
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text('營業日 ${_md.format(_date)}'),
          subtitle: Text(
            _after
                ? '日子已經過了＝事後申請'
                : _date == bizToday()
                ? '今天：還沒下班打卡＝事先申請'
                : '事先申請',
            style: TextStyle(color: _after ? AppColors.warn : AppColors.muted),
          ),
          onTap: () async {
            final today = bizToday();
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: today.subtract(const Duration(days: 62)),
              lastDate: today.add(const Duration(days: 31)),
            );
            if (d != null) setState(() => _date = d);
          },
        ),
        const SizedBox(height: 4),
        HoursStepper(value: _hours, onChanged: (v) => setState(() => _hours = v)),
        const SizedBox(height: 8),
        TextField(
          controller: _reason,
          maxLength: 200,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
              labelText: _after ? '原因（事後申請一定要寫清楚）' : '原因（例如：包場、盤點）',
              errorText: _tried && _reason.text.trim().length < 2 ? '請寫原因' : null),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: AppColors.bad, fontWeight: AppFont.heading)),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? '送出中…' : '送出申請')),
        ),
      ],
    ),
  );
}

// =====================================================================
// 員工自己的加班（我的出勤頁）
// =====================================================================

class MyOvertimeSection extends StatefulWidget {
  const MyOvertimeSection({super.key, required this.storeId, required this.personId, required this.personName});
  final String storeId, personId, personName;
  @override
  State<MyOvertimeSection> createState() => _MyOvertimeSectionState();
}

class _MyOvertimeSectionState extends State<MyOvertimeSection> {
  late Future<List<OvertimeRequest>> _future = _load();

  Future<List<OvertimeRequest>> _load() {
    final t = bizToday();
    return AppScope.of(context).repo.overtimeList(widget.storeId, t.subtract(const Duration(days: 62)), t.add(const Duration(days: 31)));
  }

  Future<void> _new() async {
    final ok = await showOvertimeForm(context, storeId: widget.storeId, personId: widget.personId, personName: widget.personName);
    if (ok == true && mounted) {
      showMessage(context, '已送出加班申請，等店長核准');
      setState(() => _future = _load());
    }
  }

  Future<void> _cancel(OvertimeRequest o) async {
    try {
      await AppScope.of(context).repo.cancelOvertime(o.id);
      if (mounted) setState(() => _future = _load());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<OvertimeRequest>>(
    future: _future,
    builder: (context, snap) {
      final mine = (snap.data ?? const <OvertimeRequest>[]).where((o) => o.personId == widget.personId).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '加班',
                  style: TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading),
                ),
              ),
              FilledButton.tonalIcon(onPressed: _new, icon: const Icon(Icons.more_time), label: const Text('申請加班')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '要加班先申請；忘了先申請的，事後申請寫原因',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
          ),
          const SizedBox(height: 8),
          if (snap.hasError)
            Text(
              friendlyError(snap.error!),
              style: TextStyle(color: AppColors.bad, fontSize: AppType.small),
            ),
          for (final o in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OvertimeCard(
                o: o,
                showName: false,
                actions: [if (o.pending && o.mine) TextButton(onPressed: () => _cancel(o), child: const Text('撤回'))],
              ),
            ),
        ],
      );
    },
  );
}

// =====================================================================
// 班的時間（隱城的 V、O）
// =====================================================================

/// 老闆、店長設 V、O 幾點到幾點（平常一組，週五六之類可以另設）；有改回 true
Future<bool> editShiftMarkTimes(BuildContext context, String storeId) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MarkTimesSheet(storeId: storeId),
    ) ??
    false;

class _MarkTimesSheet extends StatefulWidget {
  const _MarkTimesSheet({required this.storeId});
  final String storeId;
  @override
  State<_MarkTimesSheet> createState() => _MarkTimesSheetState();
}

class _MarkTimesSheetState extends State<_MarkTimesSheet> {
  late Future<List<ShiftMarkTime>> _future = _load();
  bool _changed = false;

  Future<List<ShiftMarkTime>> _load() => AppScope.of(context).repo.shiftMarkTimes(widget.storeId);

  Future<String?> _pickRange(String? current) async {
    TimeOfDay parse(String s) => TimeOfDay(hour: int.parse(s.substring(0, 2)), minute: int.parse(s.substring(3, 5)));
    final parts = current?.split('-');
    final start = await showTimePicker(
      context: context,
      helpText: '上班時間',
      initialTime: parts == null ? const TimeOfDay(hour: 18, minute: 0) : parse(parts[0]),
    );
    if (start == null || !mounted) return null;
    final end = await showTimePicker(
      context: context,
      helpText: '下班時間（過午夜照填，例如 00:30）',
      initialTime: parts == null ? const TimeOfDay(hour: 0, minute: 30) : parse(parts[1]),
    );
    if (end == null) return null;
    String f(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (f(start) == f(end)) {
      if (mounted) showMessage(context, '上班、下班不能同一個時間', error: true);
      return null;
    }
    return '${f(start)}-${f(end)}';
  }

  Future<void> _edit(String mark, int weekday, String? current) async {
    final r = await _pickRange(current);
    if (r == null || !mounted) return;
    try {
      await AppScope.of(context).repo.saveShiftMarkTime(widget.storeId, ShiftMarkTime(mark: mark, weekday: weekday, timeRange: r));
      if (mounted) {
        setState(() {
          _changed = true;
          _future = _load();
        });
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(String mark, int weekday) async {
    try {
      await AppScope.of(context).repo.deleteShiftMarkTime(widget.storeId, mark, weekday);
      if (mounted) {
        setState(() {
          _changed = true;
          _future = _load();
        });
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _addWeekday(String mark, List<ShiftMarkTime> times) async {
    final used = {
      for (final t in times)
        if (t.mark == mark) t.weekday,
    };
    final w = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(title: Text('哪一天的 $mark 時間不一樣？')),
            for (var i = 1; i <= 7; i++)
              if (!used.contains(i)) ListTile(title: Text(weekdayLabels[i]), onTap: () => Navigator.pop(c, i)),
          ],
        ),
      ),
    );
    if (w != null) {
      await _edit(mark, w, markTimeOn(times, mark, DateTime(2026, 1, 4 + w)));
    }
  }

  Widget _markBlock(String mark, String desc, List<ShiftMarkTime> times) {
    final base = times.where((t) => t.mark == mark && t.weekday == 0).firstOrNull;
    final extra = times.where((t) => t.mark == mark && t.weekday != 0).toList()..sort((a, b) => a.weekday.compareTo(b.weekday));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              desc.isEmpty ? mark : '$mark・$desc',
              style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('平常'),
              trailing: Text(
                base?.timeRange.replaceAll('-', '–') ?? '還沒設',
                style: TextStyle(color: base == null ? AppColors.warn : AppColors.text, fontFeatures: tabular),
              ),
              onTap: () => _edit(mark, 0, base?.timeRange),
            ),
            for (final t in extra)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(weekdayLabels[t.weekday]),
                subtitle: const Text('這天另外設'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.timeRange.replaceAll('-', '–'), style: const TextStyle(fontFeatures: tabular)),
                    IconButton(tooltip: '拿掉，改回平常的', onPressed: () => _delete(mark, t.weekday), icon: const Icon(Icons.close)),
                  ],
                ),
                onTap: () => _edit(mark, t.weekday, t.timeRange),
              ),
            if (base != null)
              TextButton.icon(
                onPressed: () => _addWeekday(mark, times),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('某一天的時間不一樣'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.pop(context, _changed);
    },
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: FutureBuilder<List<ShiftMarkTime>>(
          future: _future,
          builder: (context, snap) => ListView(
            shrinkWrap: true,
            children: [
              const Text(
                '班的時間',
                style: TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading),
              ),
              const SizedBox(height: 4),
              Text(
                '打卡比對用：班表上的 V、O 本身沒有時間，在這裡設。班別代碼和兼職時段本來就有時間，不用設。',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
              ),
              const SizedBox(height: 12),
              if (snap.hasError) ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load())),
              if (snap.hasData) ...[_markBlock('V', '上班', snap.data!), _markBlock('O', '', snap.data!)],
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(context, _changed), child: const Text('完成')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
