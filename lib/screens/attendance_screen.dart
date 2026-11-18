import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'attendance_check_screen.dart' show MyOvertimeSection;
import 'attendance_manage_screen.dart';
import 'payroll_screen.dart';
import 'pin_punch_screen.dart' show editPunchPin;

/// 班表第一階段：打卡（ops 0109，老闆 2026-11-15；先在隱城試行）；時間一律是伺服器時間。
/// 2026-11-16 起改成在店裡的打卡用帳號輸入自己的 4 位數密碼（ops 0112），App 不再有掃碼打卡；
/// 已經設好的 QR 打卡機用手機相機掃（#/punch?…）還是打得到。

final _hm = DateFormat('HH:mm');
final _mdHm = DateFormat('M/d HH:mm');
final _md = DateFormat('M/d（E）', 'zh_TW');

String _taipeiHm(DateTime t) => _hm.format(toTaipei(t));
String _taipeiMdHm(DateTime t) => _mdHm.format(toTaipei(t));

/// 打卡並顯示結果：店名、上班／下班、伺服器時間；待確認的寫原因
/// 從網址帶進來、還沒打的卡（沒登入時先放著，登入後打）
PunchLink? pendingPunch;

/// 掃碼後去收信再登入：那次的碼沒帶過來，打卡沒打到
Future<void> showMissedPunch(BuildContext context) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.error_outline, color: AppColors.bad, size: 44),
        title: const Text('這次沒打到卡'),
        content: const Text('剛剛掃的打卡 QR 碼在登入（收確認信）的過程中沒有送出，這次打卡沒有記錄。\n請回打卡機重新掃碼。'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('知道了'))],
      ),
    );

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
  PinStatus? _myPin; // 自己的打卡密碼設了沒（看不到密碼本身）
  // 班表頁第二批：打卡卡片預設收起來，班表往上移；按標題展開，記在這支手機（讀寫不到就照預設）
  static const _openKey = 'attendance_card_open';
  bool _open = false;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final v = (await SharedPreferences.getInstance()).getBool(_openKey) ?? false;
        if (mounted && v != _open) setState(() => _open = v);
      } catch (_) {}
    }();
  }

  void _toggle() {
    setState(() => _open = !_open);
    () async {
      try {
        await (await SharedPreferences.getInstance()).setBool(_openKey, _open);
      } catch (_) {}
    }();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  @override
  void didUpdateWidget(AttendanceCard old) {
    super.didUpdateWidget(old);
    if (old.membership.storeId != widget.membership.storeId) {
      _myPin = null;
      _future = _load();
    }
  }

  Future<AttendanceMe?> _load() async {
    final repo = AppScope.of(context).repo;
    final store = widget.membership.storeId;
    try {
      final me = await repo.attendanceMe(store);
      if (me != null && me.enabled && me.personId != null && !me.bindingPending) _loadPin(repo, store);
      return me;
    } catch (_) {
      return null; // 打卡讀不到不影響班表
    }
  }

  Future<void> _loadPin(Repository repo, String store) async {
    try {
      final mine = (await repo.pinStatus(store))?.where((p) => p.mine).firstOrNull;
      if (mounted && store == widget.membership.storeId) setState(() => _myPin = mine);
    } catch (_) {}
  }

  void _reload() => setState(() {
        _future = _load();
      });

  /// 自己設打卡密碼（只有還沒設的時候；店長的請老闆設定）
  Future<void> _editPin(PinStatus p) async {
    final changed = await editPunchPin(context, personId: p.personId, name: p.name, hasPin: p.hasPin, self: true);
    if (changed && mounted) _reload();
  }

  /// 還沒開放打卡的店：員工資料、確認本人跟打卡開關分開（程式審查 2026-11-15 第二輪）。
  /// 老闆、店長照樣進得了員工資料（老闆在這裡確認帳號綁定）；員工確認後才能到隱城掃碼支援。
  /// 薪資（第二階段 ops 0110）：老闆、店長做薪資；綁定經老闆確認的員工看自己的薪資單
  List<Widget> _payrollButtons(AttendanceMe me) => [
        if (me.canManage)
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PayrollScreen(
                    membership: widget.membership,
                    attendanceEnabled: me.enabled,
                    onOpenStaff: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AttendanceManageScreen(
                            membership: widget.membership,
                            data: widget.data,
                            codeTimes: widget.codeTimes,
                            staffOnly: true)))))),
            child: const Text('薪資'),
          ),
        if (me.personId != null && !me.bindingPending)
          OutlinedButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => MyPayslipsScreen(membership: widget.membership))),
            child: const Text('我的薪資單'),
          ),
      ];

  Widget _notEnabled(AttendanceMe me) {
    final verified = me.personId != null && !me.bindingPending;
    if (!me.canManage && !me.bindingPending && !verified) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.badge_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(me.canManage || me.bindingPending ? '員工資料' : '薪資單',
                    style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading))),
          ]),
          const SizedBox(height: 6),
          if (me.canManage)
            Text('這家店還沒開放打卡；員工資料、薪資照常可以用',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small))
          else if (me.bindingPending)
            Text('你的帳號對應還沒生效，請店長或老闆在「班表人員」替你確認一次',
                style: TextStyle(color: AppColors.warn, fontSize: AppType.small))
          else
            Text('${me.personName ?? ''}・這家店還沒開放打卡，薪資單發布後在這裡看',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          if (me.canManage || verified) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (me.canManage)
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AttendanceManageScreen(
                          membership: widget.membership, data: widget.data, codeTimes: widget.codeTimes, staffOnly: true))),
                  child: const Text('員工資料'),
                ),
              ..._payrollButtons(me),
            ]),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AttendanceMe?>(
        future: _future,
        builder: (context, snap) {
          final me = snap.data;
          if (me == null) return const SizedBox.shrink();
          if (!me.enabled) return _notEnabled(me);
          final last = me.lastPunchedAt;
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(
                  onTap: _toggle,
                  child: Row(children: [
                    Icon(Icons.dialpad, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('打卡', style: TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading))),
                    if (me.personId != null)
                      Text(me.onShift ? '上班中' : '未上班',
                          style: TextStyle(color: me.onShift ? AppColors.good : AppColors.muted, fontSize: AppType.small)),
                    Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.muted),
                  ]),
                ),
                const SizedBox(height: 6),
                if (AppScope.of(context).kiosk?.storeId == widget.membership.storeId)
                  Text('這是店裡的打卡用帳號：打卡請用第一頁「打卡」，輸入自己的 4 位數密碼',
                      style: TextStyle(color: AppColors.muted, fontSize: AppType.small))
                else if (me.bindingPending)
                  Text('你的帳號對應還沒生效，請店長或老闆在「班表人員」替你確認一次，之後才能打卡、看自己的出勤',
                      style: TextStyle(color: AppColors.warn, fontSize: AppType.small))
                else if (me.personId == null)
                  // 老闆、店長自己沒排班就不用提示（老闆 2026-11-18）
                  if (!me.canManage)
                    Text('你的帳號還沒對應到員工資料：請店長或老闆在「班表人員」替你對應一次，之後就能打卡、看自己的出勤',
                        style: TextStyle(color: AppColors.warn, fontSize: AppType.small))
                  else
                    const SizedBox.shrink()
                else
                  Text(
                      last == null
                          ? '${me.personName ?? ''}・最近沒有打卡'
                          : '${me.personName ?? ''}・上次${punchTypeLabel(me.lastPunchType ?? 'in')} ${_taipeiMdHm(last)}',
                      style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                if (me.personId != null && _myPin != null && !_myPin!.hasPin)
                  if (_myPin!.canSet)
                    // 老闆 2026-11-16：員工自己設密碼。沒設的人一定要看到
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                          color: AppColors.warn.withValues(alpha: 0.12),
                          border: Border.all(color: AppColors.warn),
                          borderRadius: BorderRadius.circular(AppRadius.sm)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('請先設定打卡密碼',
                            style: TextStyle(color: AppColors.warn, fontSize: AppType.title, fontWeight: AppFont.heading)),
                        const SizedBox(height: 2),
                        Text('按下面「打卡密碼」自己設 4 位數；之後在店裡的打卡平板輸入密碼就能打卡',
                            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                      ]),
                    )
                  else
                    Text('你還沒有打卡密碼，請老闆設定', style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
                // ops 0125：設過之後本人不能自己改，忘記或想換由店長重設
                if (_open && me.personId != null && _myPin != null && _myPin!.hasPin && !_myPin!.canSet)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('打卡密碼已經設好；忘記或想換，請找店長重設',
                        style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                  ),
                if (_open) const SizedBox(height: 10),
                if (_open)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                  if (me.personId != null && _myPin != null && _myPin!.canSet)
                    FilledButton.tonalIcon(
                        onPressed: () => _editPin(_myPin!), icon: const Icon(Icons.dialpad), label: const Text('打卡密碼')),
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
                  ..._payrollButtons(me),
                ]),
              ]),
            ),
          );
        },
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
            final missing = myMissingOutIds(rows, DateTime.now()); // 漏打下班不能顯示「正常」（老闆 2026-11-18）
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              // ops 0127：加班要先申請；沒有事先申請的，事後申請寫原因
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(
                  child: MyOvertimeSection(
                      storeId: widget.membership.storeId, personId: widget.me.personId!, personName: widget.me.personName ?? ''),
                ),
              ),
              const InfoLine(
                  text: '最近 62 天・時間是伺服器時間（台北）',
                  icon: Icons.info_outline,
                  detail: '忘了打卡可以按「補登」，店長核准後才算。待確認的打卡（例如 QR 碼過期）由店長確認。原始打卡紀錄不能修改、刪除。'),
              if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('還沒有打卡紀錄'))),
              for (final r in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(r.isPunch ? Icons.qr_code_2 : Icons.edit_calendar,
                      color: missing.contains(r.id) ? AppColors.bad : r.status == 'pending' ? AppColors.warn : AppColors.muted),
                  title: Text('${punchTypeLabel(r.punchType)}・${_taipeiMdHm(r.at)}'),
                  subtitle: Text([
                    r.storeName,
                    missing.contains(r.id) ? '漏打下班（請按「補登」補下班）' : r.statusLabel,
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
  /// 送不出去的原因：顯示在表單裡（提示條會被表單蓋住，看起來像按了沒反應；老闆 2026-11-18）
  String? _error;
  bool _tried = false;

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
      setState(() {
        _tried = true;
        _error = _time == null && _reason.text.trim().isEmpty
            ? '請選時間、寫原因'
            : _time == null
                ? '請選時間'
                : '請寫原因';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).repo.requestAmendment(
          widget.storeId, widget.personId, _type, taipeiInstant(_date, _time!.hour, _time!.minute), _reason.text.trim(),
          fromSchedule: _fromSchedule);
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
  Widget build(BuildContext context) {
    final sched = _sched;
    final noTime = _tried && _time == null;
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
          leading: Icon(Icons.schedule, color: noTime ? AppColors.bad : null),
          title: Text(_time == null ? '選時間（必填）' : '${punchTypeLabel(_type)} ${_time!.format(context)}${_fromSchedule ? '（班表帶入）' : ''}',
              style: noTime ? TextStyle(color: AppColors.bad) : null),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 18, minute: 0));
            if (t != null) setState(() { _time = t; _fromSchedule = false; _error = null; });
          },
          trailing: sched == null ? null : TextButton(onPressed: _prefill, child: const Text('從班表帶入')),
        ),
        TextField(
          controller: _reason,
          maxLength: 200,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
              labelText: '原因（例如：忘了打卡、手機沒電）',
              errorText: _tried && _reason.text.trim().isEmpty ? '請寫原因' : null),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: AppColors.bad, fontWeight: AppFont.heading)),
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
