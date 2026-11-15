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
import 'attendance_screen.dart';
import 'kiosk_screen.dart' show kioskIdPref, kioskSecretPref;

/// 出勤管理（老闆、店長）：每天看異常清單、確認待確認的打卡、審補登、看出勤、匯出 CSV、設打卡機；
/// 員工資料：老闆全部可改（含薪率、身分證、帳號）；店長看得到遮罩的身分證、帳號，看不到薪率。
class AttendanceManageScreen extends StatelessWidget {
  const AttendanceManageScreen({super.key, required this.membership, required this.data, required this.codeTimes});
  final Membership membership;
  final ShiftMonth data;
  final Map<String, String> codeTimes;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: Text('出勤管理・${membership.storeName}'),
            bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: '異常'), Tab(text: '出勤'), Tab(text: '打卡機'), Tab(text: '員工資料')]),
          ),
          body: TabBarView(children: [
            _AnomalyTab(membership: membership, data: data, codeTimes: codeTimes),
            _SessionTab(membership: membership),
            _KioskTab(membership: membership),
            _StaffTab(membership: membership),
          ]),
        ),
      );
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
  c.dispose();
  return r;
}

// ---------------- 異常清單 ----------------

class _AnomalyTab extends StatefulWidget {
  const _AnomalyTab({required this.membership, required this.data, required this.codeTimes});
  final Membership membership;
  final ShiftMonth data;
  final Map<String, String> codeTimes;
  @override
  State<_AnomalyTab> createState() => _AnomalyTabState();
}

class _AnomalyTabState extends State<_AnomalyTab> {
  _Range _range = _Range.week;
  late Future<List<AttendanceAnomaly>> _future = _load();

  Repository get _repo => AppScope.of(context).repo;

  Future<List<AttendanceAnomaly>> _load() {
    final d = _rangeDates(_range);
    return _repo.attendanceAnomalies(widget.membership.storeId, d.from, d.to);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _run(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) {
        showMessage(context, done);
        _reload();
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
      _reload();
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
  Widget build(BuildContext context) => RefreshIndicator(
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
                  detail: '確認／不採用都要寫原因，會記在異動紀錄。店長不能審自己的打卡和補登（老闆可以）。原始打卡不會被改掉，「不採用」只是不算。'),
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

// ---------------- 出勤與匯出 ----------------

class _SessionTab extends StatefulWidget {
  const _SessionTab({required this.membership});
  final Membership membership;
  @override
  State<_SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends State<_SessionTab> {
  _Range _range = _Range.today;
  late Future<List<AttendanceSession>> _future = _load();
  bool _exporting = false;

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

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AttendanceSession>>(
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
              text: '上班配 14 小時內的下班・營業日早上 6 點換日',
              icon: Icons.info_outline,
              detail: '待確認或不採用的打卡不算進這裡；匯出 CSV 會列出每一筆原始打卡（含不算的、原因、補登）。這階段不算薪資。'),
          if (snap.hasError) ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load())),
          if (!snap.hasData && !snap.hasError) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (snap.hasData && snap.data!.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('這段期間沒有出勤'))),
          if (snap.hasData)
            for (final s in snap.data!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${s.personName}・${_md.format(s.businessDate)}'),
                subtitle: Text('${s.inAt == null ? '沒有上班' : _mdHm(s.inAt!)} → ${s.outAt == null ? '沒有下班' : _mdHm(s.outAt!)}'),
                trailing: Text(_dur(s.minutes), style: const TextStyle(fontFeatures: tabular)),
              ),
        ]),
      );
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

  Future<List<KioskInfo>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _thisDevice = prefs.getString(kioskIdPref);
    return _repo.kiosks(widget.membership.storeId);
  }

  Future<void> _register() async {
    final c = TextEditingController(text: '${widget.membership.storeName}吧台');
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('把這台設成打卡機'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('這台裝置會一直顯示 QR 碼，不用登入。請在店裡固定的平板或手機上按這個。'),
          TextField(controller: c, maxLength: 40, decoration: const InputDecoration(labelText: '名稱')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('設定')),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final k = await _repo.registerKiosk(widget.membership.storeId, name);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kioskIdPref, k.id);
      await prefs.setString(kioskSecretPref, k.secret);
      if (!mounted) return;
      await Navigator.of(context).pushNamed('/kiosk');
      if (mounted) setState(() => _future = _load());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _disable(KioskInfo k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('停用「${k.name}」？'),
        content: const Text('停用後這台的 QR 碼掃了會標「打卡機已停用」待確認。不能再開回來，要用就重新設定一台。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('停用')),
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
              text: '店裡固定一台平板或手機當打卡機',
              icon: Icons.info_outline,
              detail: '打卡機每 30 秒換一個 QR 碼，碼由伺服器產生、伺服器驗證。員工掃了用自己的帳號打卡。不檢查 Wi-Fi、定位（瀏覽器讀不到 Wi-Fi 名稱，手機常用 4G），只記 IP 當參考。'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _register, icon: const Icon(Icons.add), label: const Text('把這台設成打卡機')),
            if (_thisDevice != null)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/kiosk'),
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
                leading: Icon(Icons.tablet_mac, color: k.active ? AppColors.good : AppColors.muted),
                title: Text('${k.name}${k.id == _thisDevice ? '（這台）' : ''}'),
                subtitle: Text(k.active
                    ? (k.lastSeenAt == null ? '還沒開過打卡畫面' : '最後連線 ${_mdHm(k.lastSeenAt!)}')
                    : '已停用'),
                trailing: k.active ? TextButton(onPressed: () => _disable(k), child: const Text('停用')) : null,
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
  late Future<List<StaffEntry>> _future = _load();

  Future<List<StaffEntry>> _load() => AppScope.of(context).repo.staffDirectory(widget.membership.storeId);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<StaffEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load()));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final owner = widget.membership.role == Role.owner;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            InfoLine(
                text: owner ? '老闆看得到全部（含薪率、身分證、帳號）' : '身分證、帳號只顯示遮罩；看不到薪率',
                icon: Icons.lock_outline,
                detail: '員工本人只看得到自己的資料。薪率用生效日記歷史：調薪＝新增一筆較晚的生效日，已生效的不能改、不能刪。'),
            for (final s in snap.data!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${s.name}${s.active ? '' : '（停用）'}${s.leaveDate != null ? '・已離職' : ''}'),
                subtitle: Text([
                  s.kind == 'full' ? '正職' : '兼職',
                  if (s.phone != null) s.phone!,
                  if (s.canSeePay && s.rateAmount != null) '${payTypeLabel(s.ratePayType)} ${ntd(s.rateAmount!)}',
                ].join('・')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StaffEditScreen(membership: widget.membership, entry: s)));
                  if (mounted) setState(() => _future = _load());
                },
              ),
          ]);
        },
      );
}

class StaffEditScreen extends StatefulWidget {
  const StaffEditScreen({super.key, required this.membership, required this.entry});
  final Membership membership;
  final StaffEntry entry;
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
  late DateTime? _leave = widget.entry.leaveDate;
  late String? _payType = widget.entry.payType;
  Future<List<PayRate>>? _rates;
  bool _saving = false;

  bool get _owner => widget.membership.role == Role.owner;
  Repository get _repo => AppScope.of(context).repo;
  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_owner) _rates ??= _repo.payRates(widget.entry.personId);
  }

  @override
  void dispose() {
    for (final c in [_phone, _ec, _ep, _nid, _bank, _acct]) {
      c.dispose();
    }
    super.dispose();
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
          payType: _owner ? _payType : null);
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

  Future<void> _addRate() async {
    final amount = TextEditingController(), insured = TextEditingController(), pension = TextEditingController(text: '0');
    var type = _payType ?? 'hourly';
    var from = bizToday();
    final r = await showDialog<PayRate>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('新增薪率'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                SelectChip(label: const Text('時薪'), selected: type == 'hourly', onSelected: (_) => set(() => type = 'hourly')),
                const SizedBox(width: 8),
                SelectChip(label: const Text('月薪'), selected: type == 'monthly', onSelected: (_) => set(() => type = 'monthly')),
              ]),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('生效日 ${DateFormat('yyyy/M/d').format(from)}'),
                onTap: () async {
                  final x = await showDatePicker(
                      context: d, initialDate: from, firstDate: DateTime(2020), lastDate: DateTime(from.year + 2));
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
                        id: '',
                        effectiveFrom: from,
                        payType: type,
                        amount: a,
                        insuredSalary: double.tryParse(insured.text.trim()),
                        pensionSelfRate: pr));
              },
              child: const Text('新增'),
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
      await _repo.addPayRate(widget.membership.storeId, widget.entry.personId, r);
      if (mounted) setState(() => _rates = _repo.payRates(widget.entry.personId));
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteRate(PayRate r) async {
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
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '電話')),
        TextField(controller: _ec, decoration: const InputDecoration(labelText: '緊急聯絡人')),
        TextField(controller: _ep, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '緊急聯絡電話')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_leave == null ? '離職日：未離職' : '離職日：${DateFormat('yyyy/M/d').format(_leave!)}'),
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
          const Divider(),
          Row(children: [
            Text('計薪方式', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            const SizedBox(width: 12),
            SelectChip(label: const Text('時薪'), selected: _payType == 'hourly', onSelected: (_) => setState(() => _payType = 'hourly')),
            const SizedBox(width: 8),
            SelectChip(label: const Text('月薪'), selected: _payType == 'monthly', onSelected: (_) => setState(() => _payType = 'monthly')),
          ]),
          FutureBuilder<List<PayRate>>(
            future: _rates,
            builder: (context, snap) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('薪率（生效日歷史）', style: TextStyle(color: AppColors.muted, fontSize: AppType.small))),
                TextButton.icon(onPressed: _addRate, icon: const Icon(Icons.add, size: 18), label: const Text('新增')),
              ]),
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
                  trailing: r.effectiveFrom.isAfter(bizToday())
                      ? IconButton(tooltip: '刪除（還沒生效）', onPressed: () => _deleteRate(r), icon: const Icon(Icons.delete_outline))
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
