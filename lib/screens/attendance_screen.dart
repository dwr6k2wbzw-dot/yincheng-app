import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'attendance_manage_screen.dart';

/// 班表第一階段：QR 打卡（ops 0109，老闆 2026-11-15；先在隱城試行）。
/// 店內打卡機每 30 秒換一個 QR 碼，員工用自己的帳號掃；時間一律是伺服器時間。
/// 掃碼有兩條路：手機內建相機直接掃（打開 App 網址 #/punch?…），或這裡的「掃碼打卡」。

final _hm = DateFormat('HH:mm');
final _mdHm = DateFormat('M/d HH:mm');
final _md = DateFormat('M/d（E）', 'zh_TW');

String _taipeiHm(DateTime t) => _hm.format(toTaipei(t));
String _taipeiMdHm(DateTime t) => _mdHm.format(toTaipei(t));

/// 打卡並顯示結果：店名、上班／下班、伺服器時間；待確認的寫原因
/// 從網址帶進來、還沒打的卡（沒登入時先放著，登入後打）
PunchLink? pendingPunch;

Future<void> punchAndShow(BuildContext context, PunchLink link) async {
  final repo = AppScope.of(context).repo;
  PunchResult r;
  try {
    r = await repo.punch(link);
  } catch (e) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('打卡沒有成功'),
          content: Text(friendlyError(e)),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了'))],
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final color = r.pending ? AppColors.warn : AppColors.good;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(r.pending ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 44),
      title: Text('${r.storeName}・${punchTypeLabel(r.punchType)}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_taipeiHm(r.punchedAt), style: const TextStyle(fontSize: AppType.hero, fontWeight: AppFont.hero, fontFeatures: tabular)),
        Text('伺服器時間・營業日 ${_md.format(r.businessDate)}', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        const SizedBox(height: 12),
        if (r.pending)
          Text('已記下，待店長確認：${r.flags.map(punchFlagLabel).join('、')}',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.warn))
        else
          Text('打卡成功', style: TextStyle(color: AppColors.good)),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('好'))],
    ),
  );
}

/// 班表頁的打卡卡片：這家店沒開放打卡（或資料庫還沒更新）就不顯示
class AttendanceCard extends StatefulWidget {
  const AttendanceCard({super.key, required this.membership, required this.data, required this.codeTimes});
  final Membership membership;
  final ShiftMonth data; // 補登「從班表帶入」用
  final Map<String, String> codeTimes;
  @override
  State<AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<AttendanceCard> {
  Future<AttendanceMe?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  @override
  void didUpdateWidget(AttendanceCard old) {
    super.didUpdateWidget(old);
    if (old.membership.storeId != widget.membership.storeId) _future = _load();
  }

  Future<AttendanceMe?> _load() async {
    try {
      return await AppScope.of(context).repo.attendanceMe(widget.membership.storeId);
    } catch (_) {
      return null; // 打卡讀不到不影響班表
    }
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _scan() async {
    final link = await Navigator.of(context).push<PunchLink>(MaterialPageRoute(builder: (_) => const PunchScanScreen()));
    if (link == null || !mounted) return;
    await punchAndShow(context, link);
    _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AttendanceMe?>(
        future: _future,
        builder: (context, snap) {
          final me = snap.data;
          if (me == null || !me.enabled) return const SizedBox.shrink();
          final last = me.lastPunchedAt;
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.qr_code_2, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('打卡（試行）', style: TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading))),
                  if (me.personId != null)
                    Text(me.onShift ? '上班中' : '未上班',
                        style: TextStyle(color: me.onShift ? AppColors.good : AppColors.muted, fontSize: AppType.small)),
                ]),
                const SizedBox(height: 6),
                if (me.personId == null)
                  Text('先在下面「排班」卡片選你是班表上的誰，才能打卡', style: TextStyle(color: AppColors.warn, fontSize: AppType.small))
                else
                  Text(
                      last == null
                          ? '${me.personName ?? ''}・最近沒有打卡'
                          : '${me.personName ?? ''}・上次${punchTypeLabel(me.lastPunchType ?? 'in')} ${_taipeiMdHm(last)}',
                      style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (me.personId != null)
                    FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('掃碼打卡')),
                  if (me.personId != null)
                    OutlinedButton(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                              builder: (_) => MyAttendanceScreen(
                                  membership: widget.membership, me: me, data: widget.data, codeTimes: widget.codeTimes)))
                          .then((_) => _reload()),
                      child: const Text('我的出勤・補登'),
                    ),
                  if (me.canManage)
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => AttendanceManageScreen(
                              membership: widget.membership, data: widget.data, codeTimes: widget.codeTimes))),
                      child: const Text('出勤管理'),
                    ),
                ]),
                const SizedBox(height: 6),
                Text('也可以直接用手機相機掃店裡打卡機上的 QR 碼', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
              ]),
            ),
          );
        },
      );
}

/// 掃碼畫面：認得打卡 QR 碼就回傳；其他 QR 碼提示不是打卡用的
class PunchScanScreen extends StatefulWidget {
  const PunchScanScreen({super.key});
  @override
  State<PunchScanScreen> createState() => _PunchScanScreenState();
}

class _PunchScanScreenState extends State<PunchScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture c) {
    if (_done) return;
    for (final b in c.barcodes) {
      final link = PunchLink.parse(b.rawValue ?? '');
      if (link != null) {
        _done = true;
        Navigator.of(context).pop(link);
        return;
      }
    }
    if (_hint == null) setState(() => _hint = '這不是打卡用的 QR 碼，請掃店裡打卡機上的');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('掃碼打卡')),
        body: Column(children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? '沒有相機權限。請到瀏覽器設定允許這個網站使用相機，或改用手機內建相機直接掃 QR 碼。'
                        : '相機打不開（${error.errorCode.name}）。可以改用手機內建相機直接掃 QR 碼。',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_hint ?? '對準打卡機上的 QR 碼', style: TextStyle(color: _hint == null ? AppColors.muted : AppColors.warn)),
          ),
        ]),
      );
}

/// 我的出勤：最近 62 天的打卡與補登；可申請補登、撤回待審的補登
class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({super.key, required this.membership, required this.me, required this.data, required this.codeTimes});
  final Membership membership;
  final AttendanceMe me;
  final ShiftMonth data;
  final Map<String, String> codeTimes;
  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  late Future<List<MyAttendanceRecord>> _future = _load();

  Future<List<MyAttendanceRecord>> _load() {
    final today = bizToday();
    return AppScope.of(context).repo.myAttendance(widget.membership.storeId, today.subtract(const Duration(days: 62)), today);
  }

  Future<void> _amend() async {
    final ok = await showAmendmentForm(context,
        storeId: widget.membership.storeId,
        personId: widget.me.personId!,
        personName: widget.me.personName ?? '',
        data: widget.data,
        codeTimes: widget.codeTimes);
    if (ok == true && mounted) setState(() => _future = _load());
  }

  Future<void> _cancel(MyAttendanceRecord r) async {
    try {
      await AppScope.of(context).repo.cancelAmendment(r.id);
      if (mounted) setState(() => _future = _load());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('我的出勤')),
        floatingActionButton: FloatingActionButton.extended(onPressed: _amend, icon: const Icon(Icons.edit_calendar), label: const Text('補登')),
        body: FutureBuilder<List<MyAttendanceRecord>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load()));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              const InfoLine(
                  text: '最近 62 天・時間是伺服器時間（台北）',
                  icon: Icons.info_outline,
                  detail: '忘了打卡可以按「補登」，店長核准後才算。待確認的打卡（例如 QR 碼過期）由店長確認。原始打卡紀錄不能修改、刪除。'),
              if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('還沒有打卡紀錄'))),
              for (final r in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(r.isPunch ? Icons.qr_code_2 : Icons.edit_calendar,
                      color: r.status == 'pending' ? AppColors.warn : AppColors.muted),
                  title: Text('${punchTypeLabel(r.punchType)}・${_taipeiMdHm(r.at)}'),
                  subtitle: Text([
                    r.storeName,
                    r.statusLabel,
                    if (r.flags.isNotEmpty) r.flags.map(punchFlagLabel).join('、'),
                    if (r.note != null && r.note!.isNotEmpty) r.note!,
                  ].join('・')),
                  trailing: !r.isPunch && r.status == 'pending'
                      ? TextButton(onPressed: () => _cancel(r), child: const Text('撤回'))
                      : null,
                ),
            ]);
          },
        ),
      );
}

/// 補登表單（本人自己申請，或店長替店裡的人申請）。核准後才算；班表只能預填時間。
Future<bool?> showAmendmentForm(BuildContext context,
    {required String storeId,
    required String personId,
    required String personName,
    required ShiftMonth data,
    required Map<String, String> codeTimes,
    DateTime? date,
    String? punchType}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AmendmentForm(
          storeId: storeId, personId: personId, personName: personName, data: data, codeTimes: codeTimes, date: date, punchType: punchType),
    );

class _AmendmentForm extends StatefulWidget {
  const _AmendmentForm(
      {required this.storeId,
      required this.personId,
      required this.personName,
      required this.data,
      required this.codeTimes,
      this.date,
      this.punchType});
  final String storeId, personId, personName;
  final ShiftMonth data;
  final Map<String, String> codeTimes;
  final DateTime? date;
  final String? punchType;
  @override
  State<_AmendmentForm> createState() => _AmendmentFormState();
}

class _AmendmentFormState extends State<_AmendmentForm> {
  late DateTime _date = widget.date ?? bizToday();
  late String _type = widget.punchType ?? 'in';
  TimeOfDay? _time;
  bool _fromSchedule = false;
  final _reason = TextEditingController();
  bool _saving = false;

  /// 班表那天這個人的記號（只看班表頁目前那個月）
  String? get _mark {
    final m = widget.data.month;
    if (_date.year != m.year || _date.month != m.month) return null;
    return widget.data.mark(widget.personId, _date.day);
  }

  ({int inH, int inM, int outH, int outM})? get _sched => scheduleTimes(_mark, widget.codeTimes);

  void _prefill() {
    final s = _sched;
    if (s == null) return;
    setState(() {
      _time = _type == 'in' ? TimeOfDay(hour: s.inH, minute: s.inM) : TimeOfDay(hour: s.outH, minute: s.outM);
      _fromSchedule = true;
    });
  }

  Future<void> _save() async {
    if (_time == null || _reason.text.trim().isEmpty) {
      showMessage(context, '請填時間和原因', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).repo.requestAmendment(
          widget.storeId, widget.personId, _type, taipeiInstant(_date, _time!.hour, _time!.minute), _reason.text.trim(),
          fromSchedule: _fromSchedule);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sched = _sched;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('補登・${widget.personName}', style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading)),
        const SizedBox(height: 4),
        Text('店長核准後才算；凌晨 6 點前的時間算前一個營業日', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        const SizedBox(height: 12),
        Row(children: [
          SelectChip(label: const Text('上班'), selected: _type == 'in', onSelected: (_) => setState(() { _type = 'in'; _fromSchedule = false; })),
          const SizedBox(width: 8),
          SelectChip(label: const Text('下班'), selected: _type == 'out', onSelected: (_) => setState(() { _type = 'out'; _fromSchedule = false; })),
        ]),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text('營業日 ${_md.format(_date)}'),
          onTap: () async {
            final today = bizToday();
            final d = await showDatePicker(
                context: context, initialDate: _date, firstDate: today.subtract(const Duration(days: 62)), lastDate: today);
            if (d != null) setState(() { _date = d; _fromSchedule = false; _time = null; });
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(_time == null ? '選時間' : '${punchTypeLabel(_type)} ${_time!.format(context)}${_fromSchedule ? '（班表帶入）' : ''}'),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 18, minute: 0));
            if (t != null) setState(() { _time = t; _fromSchedule = false; });
          },
          trailing: sched == null ? null : TextButton(onPressed: _prefill, child: const Text('從班表帶入')),
        ),
        TextField(
          controller: _reason,
          maxLength: 200,
          decoration: const InputDecoration(labelText: '原因（例如：忘了打卡、手機沒電）'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? '送出中…' : '送出補登')),
        ),
      ]),
    );
  }
}
