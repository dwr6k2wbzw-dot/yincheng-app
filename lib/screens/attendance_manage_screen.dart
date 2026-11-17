import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/attendance_csv.dart';
import '../services/clock.dart';
import '../services/pl_export.dart' deferred as pl;
import '../theme.dart';
import '../widgets/common.dart';
import 'attendance_check_screen.dart';
import 'attendance_screen.dart';
import 'kiosk_screen.dart' show kioskIdPref;
import 'pin_punch_screen.dart' show editPunchPin;

/// 出勤管理（老闆、店長）：每天看異常清單、確認待確認的打卡、審補登、看出勤、匯出 CSV、設打卡機；
/// 員工資料：老闆全部可改（含薪率、身分證、帳號）；店長看得到遮罩的身分證、帳號，薪率看得到、可改別人的（ops 0110），自己的只能看。
/// staffOnly：還沒開放打卡的店（小城外）只有員工資料，老闆照樣能確認帳號綁定，員工才能到隱城掃碼支援。
class AttendanceManageScreen extends StatefulWidget {
  const AttendanceManageScreen(
      {super.key, required this.membership, required this.data, required this.codeTimes, this.staffOnly = false});
  final Membership membership;
  final ShiftMonth data;
  final Map<String, String> codeTimes;
  final bool staffOnly;

  @override
  State<AttendanceManageScreen> createState() => _AttendanceManageScreenState();
}

class _AttendanceManageScreenState extends State<AttendanceManageScreen> {
  /// 審核、補登成功就加一；異常、出勤、原始紀錄分頁聽這個重新讀取，切回來不會看到舊的合計
  final _changed = ValueNotifier<int>(0);

  @override
  void dispose() {
    _changed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.membership;
    if (widget.staffOnly) {
      return Scaffold(appBar: AppBar(title: Text('員工資料・${m.storeName}')), body: _StaffTab(membership: m));
    }
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text('出勤管理・${m.storeName}'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: '異常'), Tab(text: '比對班表'), Tab(text: '加班'), Tab(text: '出勤'), Tab(text: '原始紀錄'), Tab(text: '打卡機'), Tab(text: '員工資料')
          ]),
        ),
        body: TabBarView(children: [
          _AnomalyTab(membership: m, data: widget.data, codeTimes: widget.codeTimes, changed: _changed),
          ScheduleCheckTab(membership: m, data: widget.data, codeTimes: widget.codeTimes, changed: _changed),
          OvertimeTab(membership: m, changed: _changed),
          _SessionTab(membership: m, changed: _changed),
          _RawTab(membership: m, changed: _changed),
          _KioskTab(membership: m),
          _StaffTab(membership: m),
        ]),
      ),
    );
  }
}

/// 異常、出勤、原始紀錄分頁：切走也保留（選的期間不會跳回「今天」），
/// 所以靠 [changed] 在別的分頁審核、補登成功後重新讀取
mixin _ReloadOnChange<T extends StatefulWidget> on AutomaticKeepAliveClientMixin<T> {
  ValueNotifier<int> get changed;
  void reloadData();

  @override
  bool get wantKeepAlive => true;

  void _onChanged() {
    if (mounted) reloadData();
  }

  @override
  void initState() {
    super.initState();
    changed.addListener(_onChanged);
  }

  @override
  void dispose() {
    changed.removeListener(_onChanged);
    super.dispose();
  }
}

final _md = DateFormat('M/d（E）', 'zh_TW');
String _mdHm(DateTime t) => DateFormat('M/d HH:mm').format(toTaipei(t));

/// 期間：今天／近 7 天／本月（營業日）
enum _Range { today, week, month }

({DateTime from, DateTime to}) _rangeDates(_Range r) {
  final t = bizToday();
  return switch (r) {
    _Range.today => (from: t, to: t),
    _Range.week => (from: t.subtract(const Duration(days: 6)), to: t),
    _Range.month => (from: DateTime(t.year, t.month, 1), to: t),
  };
}

Widget _rangeChips(_Range value, ValueChanged<_Range> onChanged) => Wrap(spacing: 8, children: [
      for (final (r, label) in [(_Range.today, '今天'), (_Range.week, '近 7 天'), (_Range.month, '本月')])
        SelectChip(label: Text(label), selected: value == r, onSelected: (_) => onChanged(r)),
    ]);

Future<String?> _askReason(BuildContext context, String title, {bool required = true}) async {
  final c = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, maxLength: 200, decoration: const InputDecoration(labelText: '原因')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
        FilledButton(
            onPressed: () {
              if (required && c.text.trim().isEmpty) return;
              Navigator.pop(d, c.text.trim());
            },
            child: const Text('確定')),
      ],
    ),
  );
  // 不在這裡 dispose：對話框關閉動畫還在用這個 controller（關掉後馬上 dispose 會出錯）
  return r;
}

// ---------------- 異常清單 ----------------

class _AnomalyTab extends StatefulWidget {
  const _AnomalyTab({required this.membership, required this.data, required this.codeTimes, required this.changed});
  final Membership membership;
  final ShiftMonth data;
  final Map<String, String> codeTimes;
  final ValueNotifier<int> changed;
  @override
  State<_AnomalyTab> createState() => _AnomalyTabState();
}

class _AnomalyTabState extends State<_AnomalyTab> with AutomaticKeepAliveClientMixin, _ReloadOnChange {
  _Range _range = _Range.week;
  late Future<List<AttendanceAnomaly>> _future = _load();

  Repository get _repo => AppScope.of(context).repo;

  Future<List<AttendanceAnomaly>> _load() {
    final d = _rangeDates(_range);
    return _repo.attendanceAnomalies(widget.membership.storeId, d.from, d.to);
  }

  void _reload() => setState(() => _future = _load());
  @override
  ValueNotifier<int> get changed => widget.changed;
  @override
  void reloadData() => setState(() {
        _future = _load();
      });

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) {
        showMessage(context, done);
        widget.changed.value++; // 這個分頁也會跟著重新讀取
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _review(AttendanceAnomaly a, bool confirm) async {
    final reason = await _askReason(context, confirm ? '確認這筆打卡算數' : '這筆打卡不採用');
    if (reason == null) return;
    await _run(() => _repo.reviewPunch(a.punchId!, confirm, reason), confirm ? '已確認' : '已標不採用');
  }

  Future<void> _decide(AttendanceAnomaly a, bool approve) async {
    String? note;
    if (!approve) {
      note = await _askReason(context, '退回補登');
      if (note == null) return;
    }
    await _run(() => _repo.decideAmendment(a.amendmentId!, approve, note: note), approve ? '已核准' : '已退回');
  }

  Future<void> _amendFor(AttendanceAnomaly a) async {
    final ok = await showAmendmentForm(context,
        storeId: widget.membership.storeId,
        personId: a.personId!,
        personName: a.personName,
        data: widget.data,
        codeTimes: widget.codeTimes,
        date: a.businessDate,
        punchType: a.kind == 'missing_in' ? 'in' : 'out');
    if (ok == true && mounted) {
      showMessage(context, '已送出補登，到「待審補登」核准');
      widget.changed.value++;
    }
  }

  /// 替人補登：這家店的人＋來支援過的別家店員工（依這家店的出勤紀錄）
  Future<void> _amendAnyone() async {
    final t = bizToday();
    final List<AttendancePerson> people;
    try {
      people = await _repo.attendancePeople(widget.membership.storeId, t.subtract(const Duration(days: 62)), t);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    final p = await showModalBottomSheet<AttendancePerson>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('替誰補登？'), subtitle: Text('別家店的人：最近在這家店打過卡（來支援）才列出')),
          for (final x in people)
            ListTile(
              title: Text(x.name),
              subtitle: x.crossStore ? Text('${x.homeStoreName ?? '別家店'}・來支援') : null,
              onTap: () => Navigator.pop(c, x),
            ),
        ]),
      ),
    );
    if (p == null || !mounted) return;
    final ok = await showAmendmentForm(context,
        storeId: widget.membership.storeId, personId: p.personId, personName: p.label, data: widget.data, codeTimes: widget.codeTimes);
    if (ok == true && mounted) {
      showMessage(context, '已送出補登，要另一位店長或老闆核准');
      widget.changed.value++;
    }
  }

  List<Widget> _actions(AttendanceAnomaly a) => switch (a.kind) {
        'pending' || 'duplicate' when a.punchId != null => [
            TextButton(onPressed: () => _review(a, true), child: const Text('確認')),
            TextButton(onPressed: () => _review(a, false), child: const Text('不採用')),
          ],
        'amendment' when a.amendmentId != null => [
            TextButton(onPressed: () => _decide(a, true), child: const Text('核准')),
            TextButton(onPressed: () => _decide(a, false), child: const Text('退回')),
          ],
        'missing_out' || 'missing_in' when a.personId != null => [
            TextButton(onPressed: () => _amendFor(a), child: const Text('替他補登')),
          ],
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    super.build(context); // 保留分頁
    return RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<AttendanceAnomaly>>(
          future: _future,
          builder: (context, snap) {
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              _rangeChips(_range, (r) => setState(() {
                    _range = r;
                    _future = _load();
                  })),
              const InfoLine(
                  text: '店長每天看一次：漏打、待確認、待審補登',
                  icon: Icons.info_outline,
                  detail: '確認／不採用都要寫原因，會記在異動紀錄。店長不能審自己的打卡和補登（老闆可以）。原始打卡不會被改掉，「不採用」只是不算。已經審過的要改，到「原始紀錄」點那一筆重新審核。'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _amendAnyone, icon: const Icon(Icons.edit_calendar, size: 18), label: const Text('替人補登（含來支援的）')),
              ),
              if (snap.hasError) ErrorView(message: friendlyError(snap.error!), onRetry: _reload),
              if (!snap.hasData && !snap.hasError) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (snap.hasData && snap.data!.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('沒有異常'))),
              if (snap.hasData)
                for (final a in snap.data!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SectionCard(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(anomalyKindLabel(a.kind),
                              style: TextStyle(color: a.kind == 'amendment' ? AppColors.primary : AppColors.warn, fontWeight: AppFont.label)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(a.personName, style: const TextStyle(fontWeight: AppFont.heading))),
                          if (a.businessDate != null) Text(_md.format(a.businessDate!), style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                            [
                              if (a.punchType != null && a.at != null) '${punchTypeLabel(a.punchType!)} ${_mdHm(a.at!)}',
                              if (a.detail != null && a.detail!.isNotEmpty) a.detail!,
                            ].join('・'),
                            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: _actions(a)),
                      ]),
                    ),
                  ),
            ]);
          },
        ),
      );
  }
}

// ---------------- 出勤與匯出 ----------------

class _SessionTab extends StatefulWidget {
  const _SessionTab({required this.membership, required this.changed});
  final Membership membership;
  final ValueNotifier<int> changed;
  @override
  State<_SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends State<_SessionTab> with AutomaticKeepAliveClientMixin, _ReloadOnChange {
  _Range _range = _Range.today;
  late Future<List<AttendanceSession>> _future = _load();
  bool _exporting = false;

  @override
  ValueNotifier<int> get changed => widget.changed;
  @override
  void reloadData() => setState(() {
        _future = _load();
      });

  Repository get _repo => AppScope.of(context).repo;

  Future<List<AttendanceSession>> _load() {
    final d = _rangeDates(_range);
    return _repo.attendanceSessions(widget.membership.storeId, d.from, d.to);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final d = _rangeDates(_range);
      final rows = await _repo.attendanceExport(widget.membership.storeId, d.from, d.to);
      await pl.loadLibrary();
      final name = attendanceCsvName(widget.membership.storeName, d.from, d.to);
      final r = await pl.saveFile(attendanceCsvBytes(rows), name, csvMime);
      if (mounted && r == 'downloaded') showMessage(context, '已下載 $name');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _dur(int? m) => m == null ? '—' : '${m ~/ 60} 小時 ${m % 60} 分';

  Widget _totals(List<AttendanceSession> rows) {
    final counted = rows.fold<int>(0, (a, s) => a + s.countedMinutes);
    final pending = rows.where((s) => s.pending).length;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '計入工時合計 ${_dur(counted)}', style: const TextStyle(fontWeight: AppFont.label, fontFeatures: tabular)),
        if (pending > 0) TextSpan(text: '・$pending 段待確認不計入', style: TextStyle(color: AppColors.warn)),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 保留分頁
    return FutureBuilder<List<AttendanceSession>>(
        future: _future,
        builder: (context, snap) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Row(children: [
            Expanded(
                child: _rangeChips(_range, (r) => setState(() {
                      _range = r;
                      _future = _load();
                    }))),
            OutlinedButton.icon(
                onPressed: _exporting ? null : _export, icon: const Icon(Icons.download, size: 18), label: const Text('匯出 CSV')),
          ]),
          const InfoLine(
              text: '待確認的打卡，確認前不計入工時',
              icon: Icons.info_outline,
              detail: '上班配 14 小時內的下班，營業日早上 6 點換日。有一筆還在待確認的段會標「待確認・不計入」，工時合計不算它；到「異常」或「原始紀錄」確認後才算。不採用的打卡不算。匯出 CSV 會列出每一筆原始打卡，「算不算」一欄標「待確認（不算）」。這階段不算薪資。'),
          if (snap.hasData && snap.data!.isNotEmpty) _totals(snap.data!),
          if (snap.hasError) ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load())),
          if (!snap.hasData && !snap.hasError) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (snap.hasData && snap.data!.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('這段期間沒有出勤'))),
          if (snap.hasData)
            for (final s in snap.data!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${s.personName}・${_md.format(s.businessDate)}'),
                subtitle: Text.rich(TextSpan(children: [
                  TextSpan(text: '${s.inAt == null ? '沒有上班' : _mdHm(s.inAt!)} → ${s.outAt == null ? '沒有下班' : _mdHm(s.outAt!)}'),
                  if (s.pending) TextSpan(text: '\n待確認・不計入工時', style: TextStyle(color: AppColors.warn)),
                ])),
                trailing: Text(_dur(s.minutes),
                    style: TextStyle(
                        fontFeatures: tabular,
                        color: s.pending ? AppColors.muted : null,
                        decoration: s.pending && s.minutes != null ? TextDecoration.lineThrough : null)),
              ),
        ]),
      );
  }
}

// ---------------- 原始紀錄（每一筆打卡；可以重新審核） ----------------

class _RawTab extends StatefulWidget {
  const _RawTab({required this.membership, required this.changed});
  final Membership membership;
  final ValueNotifier<int> changed;
  @override
  State<_RawTab> createState() => _RawTabState();
}

class _RawTabState extends State<_RawTab> with AutomaticKeepAliveClientMixin, _ReloadOnChange {
  _Range _range = _Range.week;
  late Future<List<AttendanceExportRow>> _future = _load();

  @override
  ValueNotifier<int> get changed => widget.changed;
  @override
  void reloadData() => setState(() {
        _future = _load();
      });

  Future<List<AttendanceExportRow>> _load() {
    final d = _rangeDates(_range);
    return AppScope.of(context).repo.attendanceExport(widget.membership.storeId, d.from, d.to);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 保留分頁
    return RefreshIndicator(
        onRefresh: () async => setState(() => _future = _load()),
        child: FutureBuilder<List<AttendanceExportRow>>(
          future: _future,
          builder: (context, snap) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            _rangeChips(_range, (r) => setState(() {
                  _range = r;
                  _future = _load();
                })),
            const InfoLine(
                text: '每一筆原始打卡；點一筆看歷程、重新審核',
                icon: Icons.info_outline,
                detail: '已確認、不採用的也可以再改，每一次都要寫原因，舊的審核留在歷程裡，以最新一次為準。原始打卡本身不能改。'),
            if (snap.hasError) ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load())),
            if (!snap.hasData && !snap.hasError) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (snap.hasData && snap.data!.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('這段期間沒有打卡'))),
            if (snap.hasData)
              for (final r in snap.data!.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(r.source == 'amendment' ? Icons.edit_calendar : (r.source == 'pin' ? Icons.dialpad : Icons.qr_code_2),
                      color: r.awaitingReview ? AppColors.warn : (r.counted ? AppColors.good : AppColors.muted)),
                  title: Text('${r.personName}・${punchTypeLabel(r.punchType)} ${_mdHm(r.punchedAt)}'),
                  subtitle: Text([
                    if (r.storeName != widget.membership.storeName) r.storeName,
                    if (!r.awaitingReview) rawReviewLabel(r), // 待確認已寫在最後的「待確認（不算）」
                    if (r.flags.isNotEmpty) r.flags.split(' ').where((f) => f.isNotEmpty).map(punchFlagLabel).join('、'),
                    r.countedLabel,
                  ].join('・')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    // 審核成功就通知出勤、異常分頁一起更新（這個分頁也會重新讀取）
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PunchDetailScreen(row: r, onReviewed: () => widget.changed.value++)));
                  },
                ),
          ]),
        ),
      );
  }
}

String rawReviewLabel(AttendanceExportRow r) => switch (r.review) {
      'confirmed' => '已確認',
      'rejected' => '不採用',
      _ => r.status == 'pending' ? '待確認' : (r.source == 'amendment' ? '補登' : '正常'),
    };

/// 一筆打卡：歷程（打卡、補登、每一次審核）＋重新審核
class PunchDetailScreen extends StatefulWidget {
  const PunchDetailScreen({super.key, required this.row, this.onReviewed});
  final AttendanceExportRow row;
  final VoidCallback? onReviewed;
  @override
  State<PunchDetailScreen> createState() => _PunchDetailScreenState();
}

class _PunchDetailScreenState extends State<PunchDetailScreen> {
  late Future<List<PunchHistoryEntry>> _future = _load();
  String? _decision; // 這次審核後的結果（畫面上先更新）

  Repository get _repo => AppScope.of(context).repo;
  Future<List<PunchHistoryEntry>> _load() => _repo.punchHistory(widget.row.punchId);

  Future<void> _review(bool confirm) async {
    final reason = await _askReason(context, confirm ? '確認這筆打卡算數' : '這筆打卡不採用');
    if (reason == null || !mounted) return;
    try {
      await _repo.reviewPunch(widget.row.punchId, confirm, reason);
      widget.onReviewed?.call();
      if (!mounted) return;
      showMessage(context, confirm ? '已確認' : '已標不採用');
      setState(() {
        _decision = confirm ? 'confirmed' : 'rejected';
        _future = _load();
      });
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final current = _decision ?? r.review;
    return Scaffold(
      appBar: AppBar(title: const Text('打卡紀錄')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text('${r.personName}・${punchTypeLabel(r.punchType)}', style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
        Text('${_mdHm(r.punchedAt)}・${r.storeName}・營業日 ${_md.format(r.businessDate)}', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        Text(switch (current) {
          'confirmed' => '目前：已確認（計入工時）',
          'rejected' => '目前：不採用（不計入）',
          _ => r.status == 'pending' ? '目前：待確認（確認前不計入工時）' : '目前：正常（計入工時）',
        }, style: TextStyle(color: current == null && r.status == 'pending' ? AppColors.warn : null, fontWeight: AppFont.label)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          FilledButton.tonal(onPressed: current == 'confirmed' ? null : () => _review(true), child: Text(current == null ? '確認' : '改成確認')),
          OutlinedButton(onPressed: current == 'rejected' ? null : () => _review(false), child: Text(current == null ? '不採用' : '改成不採用')),
        ]),
        const SizedBox(height: 4),
        Text('要寫原因；店長不能審自己的打卡（老闆可以）', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        const Divider(height: 24),
        Text('歷程', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        FutureBuilder<List<PunchHistoryEntry>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return Text(friendlyError(snap.error!), style: TextStyle(color: AppColors.bad));
            if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            return Column(children: [
              for (final h in snap.data!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                      h.action == 'review' ? (h.decision == 'confirmed' ? Icons.check_circle_outline : Icons.block) : Icons.history,
                      size: 20,
                      color: AppColors.muted),
                  title: Text('${h.label}・${h.actorName ?? '—'}'),
                  subtitle: Text([
                    _mdHm(h.at),
                    if (h.action.endsWith('punch') && h.decision == 'pending') '待確認',
                    if (h.reason != null && h.reason!.isNotEmpty)
                      h.action.endsWith('punch') ? h.reason!.split(' ').map(punchFlagLabel).join('、') : h.reason!,
                  ].join('・')),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

// ---------------- 打卡機 ----------------

class _KioskTab extends StatefulWidget {
  const _KioskTab({required this.membership});
  final Membership membership;
  @override
  State<_KioskTab> createState() => _KioskTabState();
}

class _KioskTabState extends State<_KioskTab> {
  late Future<List<KioskInfo>> _future = _load();
  String? _thisDevice;

  Repository get _repo => AppScope.of(context).repo;
  bool get _owner => widget.membership.role == Role.owner;

  Future<List<KioskInfo>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _thisDevice = prefs.getString(kioskIdPref);
    return _repo.kiosks(widget.membership.storeId);
  }

  /// 換成打卡機畫面：先登出（打卡機畫面自己也會再登出一次），清掉整個頁面堆疊，按返回回不到後台
  Future<void> _openKiosk() async {
    final nav = Navigator.of(context, rootNavigator: true);
    await _repo.signOut();
    nav.pushNamedAndRemoveUntil('/kiosk', (_) => false);
  }

  Future<void> _confirmOpenKiosk() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('打開打卡畫面'),
        content: const Text('打開後這台會登出你的帳號，之後要回後台得重新登入。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('登出並打開')),
        ],
      ),
    );
    if (ok == true && mounted) await _openKiosk();
  }

  /// 老闆：選一個店裡共用的帳號設成打卡用帳號（ops 0112）。權限照舊，登入後第一頁多一個密碼打卡
  Future<void> _setAccount() async {
    final List<KioskAccountCandidate> list;
    try {
      list = await _repo.kioskAccountCandidates(widget.membership.storeId);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    final pick = await showDialog<KioskAccountCandidate>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('設定打卡用帳號'),
        content: SizedBox(
          width: 400,
          child: ListView(shrinkWrap: true, children: [
            const Text('選店裡共用的帳號。原本能用的功能都不變，登入後第一頁多一個「打卡」，員工輸入自己的 4 位數密碼打卡。這個帳號不能連到員工資料，也不能幫自己打卡。'),
            const SizedBox(height: 8),
            if (list.isEmpty) Text('這家店沒有可以選的帳號（老闆、店長不能設）', style: TextStyle(color: AppColors.muted)),
            for (final c in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: c.blocked == null,
                title: Text(c.displayName),
                subtitle: Text(c.blocked ?? roleLabel(roleFrom(c.role))),
                onTap: c.blocked == null ? () => Navigator.pop(d, c) : null,
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消'))],
      ),
    );
    if (pick == null || !mounted) return;
    try {
      await _repo.setKioskAccount(widget.membership.storeId, pick.userId);
      if (!mounted) return;
      showMessage(context, '已把「${pick.displayName}」設成打卡用帳號');
      setState(() {
        _future = _load();
      });
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _disable(KioskInfo k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(k.isAccount ? '取消打卡用帳號「${k.accountName ?? k.name}」？' : '停用「${k.name}」？'),
        content: Text(k.isAccount
            ? '取消後這個帳號登入就沒有「打卡」頁，其他功能照舊。之前的打卡紀錄都保留。'
            : '停用後這台的 QR 碼掃了會標「打卡機已停用」待確認。不能再開回來。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(k.isAccount ? '取消打卡用帳號' : '停用')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.disableKiosk(k.id);
      if (mounted) setState(() => _future = _load());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<KioskInfo>>(
        future: _future,
        builder: (context, snap) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          const InfoLine(
              text: '店裡共用的帳號登入，第一頁就是密碼打卡',
              icon: Icons.info_outline,
              detail: '員工在店裡的平板或手機先點自己的名字、再輸入自己的 4 位數打卡密碼，時間一律是伺服器時間。連錯 5 次鎖 1 分鐘。'
                  '打卡密碼：員工第一次在班表的打卡卡片自己設（4 位數、不能太好猜）；忘記或想換，由店長在「員工資料」點人重設（店長的由老闆設）。'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_owner)
              FilledButton.icon(
                  onPressed: _setAccount, icon: const Icon(Icons.person_pin_outlined), label: const Text('設定打卡用帳號')),
            if (_thisDevice != null)
              OutlinedButton.icon(
                onPressed: _confirmOpenKiosk,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('打開這台的打卡畫面'),
              ),
          ]),
          const SizedBox(height: 8),
          if (snap.hasError) ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load())),
          if (snap.hasData)
            for (final k in snap.data!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(k.isAccount ? Icons.person_pin_outlined : Icons.tablet_mac,
                    color: k.active ? AppColors.good : AppColors.muted),
                title: Text(k.isAccount
                    ? '打卡用帳號：${k.accountName ?? k.name}'
                    : '${k.name}${k.id == _thisDevice ? '（這台）' : ''}'),
                subtitle: Text(k.active
                    ? (k.lastSeenAt == null ? '還沒開過打卡畫面' : '最後連線 ${_mdHm(k.lastSeenAt!)}')
                    : (k.isAccount ? '已取消' : '已停用')),
                // 打卡用帳號只有老闆能取消（店長取消會被資料庫擋）
                trailing: k.active && (!k.isAccount || _owner)
                    ? TextButton(onPressed: () => _disable(k), child: Text(k.isAccount ? '取消' : '停用'))
                    : null,
              ),
        ]),
      );
}

// ---------------- 員工資料 ----------------

class _StaffTab extends StatefulWidget {
  const _StaffTab({required this.membership});
  final Membership membership;
  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  late Future<(List<StaffEntry>, Map<String, PinStatus>?)> _future = _load();

  /// 員工資料＋打卡密碼設了沒（ops 0112；資料庫還沒更新就不顯示密碼）
  Future<(List<StaffEntry>, Map<String, PinStatus>?)> _load() async {
    final repo = AppScope.of(context).repo, store = widget.membership.storeId;
    final pins = repo.pinStatus(store).then<List<PinStatus>?>((v) => v, onError: (_) => null);
    final list = await repo.staffDirectory(store);
    final p = await pins;
    return (list, p == null ? null : {for (final x in p) x.personId: x});
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(List<StaffEntry>, Map<String, PinStatus>?)>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load()));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final owner = widget.membership.role == Role.owner;
          final (staff, pins) = snap.data!;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            InfoLine(
                text: owner ? '老闆看得到全部（含薪資、身分證、帳號）' : '身分證、帳號只顯示遮罩；薪資看得到、改得了別人的，自己的只能看',
                icon: Icons.lock_outline,
                detail: '員工本人只看得到自己的資料。薪資用生效日記歷史：調薪＝新增一筆生效日，打錯了點那一筆可以改。'
                    '${pins == null ? '' : '點人可以設定、重設打卡密碼（4 位數，不能太好猜；員工第一次可以自己設，忘記了由店長在這裡重設；店長的由老闆設定）。'}'),
            for (final s in staff)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${s.name}${s.active ? '' : '（停用）'}${s.leaveDate != null ? '・已離職' : ''}'),
                subtitle: Text([
                  s.kind == 'full' ? '正職' : '兼職',
                  if (s.phone != null) s.phone!,
                  if (s.canSeePay && s.rateAmount != null) '${payTypeLabel(s.ratePayType)} ${ntd(s.rateAmount!)}',
                  bindingLabel(s),
                  if (pins?[s.personId] case final p?) p.hasPin ? '打卡密碼已設定' : '打卡密碼未設定',
                ].join('・')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StaffEditScreen(membership: widget.membership, entry: s, pin: pins?[s.personId])));
                  // 回來重新讀（打卡密碼設了沒也會變）；setState 不能回傳 Future
                  if (mounted) {
                    setState(() {
                      _future = _load();
                    });
                  }
                },
              ),
          ]);
        },
      );
}

String bindingLabel(StaffEntry s) => s.userId == null
    ? '還沒對應 App 帳號'
    : '帳號 ${s.userName ?? '—'}${s.userVerified ? '' : '（還沒生效）'}';

class StaffEditScreen extends StatefulWidget {
  const StaffEditScreen({super.key, required this.membership, required this.entry, this.pin});
  final Membership membership;
  final StaffEntry entry;
  final PinStatus? pin; // 打卡密碼設了沒（ops 0112）；null＝資料庫還沒更新，不顯示
  @override
  State<StaffEditScreen> createState() => _StaffEditScreenState();
}

class _StaffEditScreenState extends State<StaffEditScreen> {
  late final _phone = TextEditingController(text: widget.entry.phone);
  late final _ec = TextEditingController(text: widget.entry.emergencyContact);
  late final _ep = TextEditingController(text: widget.entry.emergencyPhone);
  late final _nid = TextEditingController(text: widget.entry.identityMasked ? '' : widget.entry.nationalId);
  late final _bank = TextEditingController(text: widget.entry.identityMasked ? '' : widget.entry.bankCode);
  late final _acct = TextEditingController(text: widget.entry.identityMasked ? '' : widget.entry.bankAccount);
  late DateTime? _hire = widget.entry.hireDate;
  late DateTime? _leave = widget.entry.leaveDate;
  late String? _payType = widget.entry.payType;
  late bool _verified = widget.entry.userVerified;
  late bool? _hasPin = widget.pin?.hasPin;
  Future<List<PayRate>>? _rates;
  bool _saving = false;

  bool get _owner => widget.membership.role == Role.owner;

  /// 到職日：老闆、店長（班表人員資料的寫入權限，ops 0028）
  bool get _canEditHire => _owner || widget.membership.role == Role.manager;

  /// 離職日看開頁時的資料決定要不要顯示，編輯中清掉不會整行消失
  bool get _showLeave => widget.entry.showsLeaveDate;

  /// 薪率、計薪方式：老闆全部；店長改別人的（ops 0110），自己的只能看（比照第一階段自審規則）
  bool get _canEditPay =>
      _owner ||
      (widget.membership.role == Role.manager && widget.entry.canSeePay && widget.entry.userId != _repo.currentUserId);
  Repository get _repo => AppScope.of(context).repo;
  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_owner || widget.entry.canSeePay) _rates ??= _repo.payRates(widget.entry.personId);
  }

  @override
  void dispose() {
    for (final c in [_phone, _ec, _ep, _nid, _bank, _acct]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 帳號對應：平常在「班表人員」指定就生效（ops 0125）。這裡留給老闆確認／取消以前員工自己選的
  Future<void> _verify(bool verify) async {
    final e = widget.entry;
    if (verify) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('確認帳號綁定'),
          content: Text('確定「${e.userName ?? '這個帳號'}」就是 ${e.name} 本人？確認後這個帳號看得到 ${e.name} 的身分證、銀行帳號、薪資，也能用這個名字打卡。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('是本人，確認')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await _repo.verifyBinding(e.personId, e.userId!, verify: verify);
      if (!mounted) return;
      setState(() => _verified = verify);
      showMessage(context, verify ? '已確認' : '已取消確認');
    } catch (err) {
      if (mounted) showMessage(context, friendlyError(err), error: true);
    }
  }

  Widget _binding() {
    final e = widget.entry;
    if (e.userId == null) {
      return const InfoLine(
          text: '還沒對應 App 帳號',
          icon: Icons.link_off,
          detail: '到「班表 → 班表人員」點這個人，替他對應 App 帳號，對應好就生效（老闆、店長都可以；店長自己的由老闆對應）。'
              '沒對應的人登入後 App 不知道他是誰：不能打卡、看不到自己的出勤和薪資單。');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InfoLine(
          text: 'App 帳號 ${e.userName ?? '—'}・${_verified ? '已對應' : '還沒生效'}',
          icon: _verified ? Icons.verified_user_outlined : Icons.hourglass_empty,
          detail: '還沒生效的是以前員工自己選的：這個帳號還看不到這個人的個資和薪資，也不能打卡。'
              '老闆在這裡確認，或店長到「班表人員」重新指定一次同一個帳號，就生效。已經對應好的要改，請找老闆。'),
      if (_owner)
        Align(
          alignment: Alignment.centerLeft,
          child: _verified
              ? TextButton(onPressed: () => _verify(false), child: const Text('取消確認'))
              : FilledButton.tonal(onPressed: () => _verify(true), child: const Text('確認是本人')),
        )
      else if (!_verified)
        Text('到「班表 → 班表人員」點這個人，重新指定一次同一個帳號就生效', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
    ]);
  }

  /// 打卡密碼：已設定／未設定（看不到密碼本身）；老闆、店長可設定、重設、清除，店長的由老闆設定
  Widget _pinRow() {
    final p = widget.pin!;
    final canClear = p.canSet && (_owner || widget.membership.role == Role.manager);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.dialpad, color: _hasPin! ? AppColors.good : AppColors.muted),
      title: Text(_hasPin! ? '打卡密碼：已設定' : '打卡密碼：未設定'),
      subtitle: Text(p.canSet
          ? '4 位數字、不能太好猜；設好之後誰都看不到。員工忘記了在這裡重設'
          : (p.mine ? '店長的打卡密碼請老闆設定' : '只有老闆、店長能設定')),
      trailing: !p.canSet
          ? null
          : OutlinedButton(
              onPressed: () async {
                final changed = await editPunchPin(context,
                    personId: p.personId, name: widget.entry.name, hasPin: _hasPin!, canClear: canClear, self: p.mine);
                if (!changed || !mounted) return;
                // 重新讀一次設了沒（清除、設定都會改）
                final fresh = (await _repo.pinStatus(widget.membership.storeId))?.where((x) => x.personId == p.personId).firstOrNull;
                if (mounted && fresh != null) setState(() => _hasPin = fresh.hasPin);
              },
              child: Text(_hasPin! ? '重設' : '設定'),
            ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final store = widget.membership.storeId, p = widget.entry.personId;
      await _repo.saveStaffHr(store, p,
          phone: _t(_phone),
          emergencyContact: _t(_ec),
          emergencyPhone: _t(_ep),
          leaveDate: _leave,
          payType: _canEditPay ? _payType : null);
      if (_canEditHire && _hire != widget.entry.hireDate) await _repo.saveHireDate(store, p, _hire);
      if (_owner) await _repo.saveStaffIdentity(store, p, nationalId: _t(_nid), bankCode: _t(_bank), bankAccount: _t(_acct));
      if (mounted) {
        showMessage(context, '已儲存');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  /// 新增（old == null）或修改一筆薪資。ops 0123 起已經存在的也可以改、生效日可以往前填。
  Future<void> _editRate([PayRate? old]) async {
    String num0(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
    final amount = TextEditingController(text: old == null ? '' : num0(old.amount)),
        insured = TextEditingController(text: old?.insuredSalary == null ? '' : num0(old!.insuredSalary!)),
        pension = TextEditingController(text: old == null ? '0' : num0(old.pensionSelfRate));
    var type = old?.payType ?? _payType ?? 'hourly';
    var from = old?.effectiveFrom ?? bizToday();
    final r = await showDialog<PayRate>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(old == null ? '新增薪資' : '修改薪資'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                SelectChip(label: const Text('時薪'), selected: type == 'hourly', onSelected: (_) => set(() => type = 'hourly')),
                const SizedBox(width: 8),
                SelectChip(label: const Text('月薪'), selected: type == 'monthly', onSelected: (_) => set(() => type = 'monthly')),
                const SizedBox(width: 8),
                SelectChip(label: const Text('日薪'), selected: type == 'daily', onSelected: (_) => set(() => type = 'daily')),
              ]),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('生效日 ${DateFormat('yyyy/M/d').format(from)}'),
                subtitle: const Text('從這一天起照這個金額算；可以填過去的日期'),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final x = await showDatePicker(
                      context: d, initialDate: from, firstDate: DateTime(2015), lastDate: DateTime(bizToday().year + 2));
                  if (x != null) set(() => from = x);
                },
              ),
              TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '金額')),
              TextField(controller: insured, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '投保薪資級距（可空白）')),
              TextField(controller: pension, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '勞退自提 %（0～6）')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final a = double.tryParse(amount.text.trim());
                final pr = double.tryParse(pension.text.trim()) ?? 0;
                if (a == null || a <= 0 || pr < 0 || pr > 6) return;
                Navigator.pop(
                    d,
                    PayRate(
                        id: old?.id ?? '',
                        effectiveFrom: from,
                        payType: type,
                        amount: a,
                        insuredSalary: double.tryParse(insured.text.trim()),
                        pensionSelfRate: pr));
              },
              child: Text(old == null ? '新增' : '儲存'),
            ),
          ],
        ),
      ),
    );
    for (final c in [amount, insured, pension]) {
      c.dispose();
    }
    if (r == null || !mounted) return;
    try {
      if (old == null) {
        await _repo.addPayRate(widget.membership.storeId, widget.entry.personId, r);
      } else {
        await _repo.updatePayRate(r);
      }
      if (!mounted) return;
      setState(() => _rates = _repo.payRates(widget.entry.personId));
      showMessage(context, old == null ? '已新增' : '已修改。已經發布的薪資單不會跟著變');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteRate(PayRate r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('刪除這筆薪資？'),
        content: Text('${DateFormat('yyyy/M/d').format(r.effectiveFrom)} 起・${payTypeLabel(r.payType)} ${ntd(r.amount)}\n\n已經發布的薪資單不會跟著變。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.deletePayRate(r.id);
      if (mounted) setState(() => _rates = _repo.payRates(widget.entry.personId));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Scaffold(
      appBar: AppBar(title: Text(e.name)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _binding(),
        if (widget.pin != null) _pinRow(),
        const Divider(),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '電話')),
        TextField(controller: _ec, decoration: const InputDecoration(labelText: '緊急聯絡人')),
        TextField(controller: _ep, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '緊急聯絡電話')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_hire == null ? '到職日：未填' : '到職日：${DateFormat('yyyy/M/d').format(_hire!)}'),
          subtitle: _hire == null && _canEditHire ? const Text('點這裡選日期；算薪的名單會用到') : null,
          trailing: _hire == null || !_canEditHire
              ? null
              : IconButton(tooltip: '清除', onPressed: () => setState(() => _hire = null), icon: const Icon(Icons.clear)),
          onTap: !_canEditHire
              ? null
              : () async {
                  final d = await showDatePicker(
                      context: context, initialDate: _hire ?? bizToday(), firstDate: DateTime(2010), lastDate: DateTime(bizToday().year + 1));
                  if (d != null) setState(() => _hire = d);
                },
        ),
        if (_showLeave)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_leave == null ? '離職日：未填' : '離職日：${DateFormat('yyyy/M/d').format(_leave!)}'),
            trailing: _leave == null ? null : IconButton(tooltip: '清除', onPressed: () => setState(() => _leave = null), icon: const Icon(Icons.clear)),
            onTap: () async {
              final d = await showDatePicker(
                  context: context, initialDate: _leave ?? bizToday(), firstDate: DateTime(2020), lastDate: DateTime(bizToday().year + 1));
              if (d != null) setState(() => _leave = d);
            },
          ),
        const Divider(),
        Text('身分證、銀行帳號', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        if (!_owner) ...[
          InfoLine(text: '身分證 ${e.nationalId ?? '未填'}', icon: Icons.badge_outlined),
          InfoLine(text: '帳號 ${e.bankCode ?? ''} ${e.bankAccount ?? '未填'}', icon: Icons.account_balance_outlined),
        ] else ...[
          TextField(controller: _nid, decoration: const InputDecoration(labelText: '身分證字號')),
          TextField(controller: _bank, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '銀行代碼')),
          TextField(
              controller: _acct,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
              decoration: const InputDecoration(labelText: '帳號')),
        ],
        if (_owner || e.canSeePay) ...[
          const Divider(),
          Row(children: [
            Text('計薪方式', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            const SizedBox(width: 12),
            for (final t in const ['hourly', 'monthly', 'daily']) ...[
              SelectChip(
                  label: Text(payTypeLabel(t)),
                  selected: _payType == t,
                  onSelected: _canEditPay ? (_) => setState(() => _payType = t) : null),
              const SizedBox(width: 8),
            ],
          ]),
          if (!_canEditPay) Text('你自己的薪資只能看，要改請找老闆', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          FutureBuilder<List<PayRate>>(
            future: _rates,
            builder: (context, snap) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('薪資（生效日歷史）', style: TextStyle(color: AppColors.muted, fontSize: AppType.small))),
                if (_canEditPay) TextButton.icon(onPressed: () => _editRate(), icon: const Icon(Icons.add, size: 18), label: const Text('新增')),
              ]),
              if (_canEditPay && (snap.data?.isNotEmpty ?? false))
                Text('點一筆可以修改', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              if (snap.hasError) Text(friendlyError(snap.error!), style: TextStyle(color: AppColors.bad)),
              for (final r in snap.data ?? const <PayRate>[])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${DateFormat('yyyy/M/d').format(r.effectiveFrom)} 起・${payTypeLabel(r.payType)} ${ntd(r.amount)}'),
                  subtitle: Text([
                    if (r.insuredSalary != null) '投保 ${ntd(r.insuredSalary!)}',
                    '勞退自提 ${r.pensionSelfRate.toStringAsFixed(r.pensionSelfRate % 1 == 0 ? 0 : 1)}%',
                  ].join('・')),
                  onTap: _canEditPay ? () => _editRate(r) : null,
                  trailing: _canEditPay
                      ? IconButton(tooltip: '刪除', onPressed: () => _deleteRate(r), icon: const Icon(Icons.delete_outline))
                      : null,
                ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? '儲存中…' : '儲存')),
      ]),
    );
  }
}
