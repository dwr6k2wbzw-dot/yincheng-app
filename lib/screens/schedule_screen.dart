import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/schedule_health.dart';
import '../data/shift_marks.dart';
import '../services/pl_export.dart' deferred as pl;
import '../services/shift_export.dart' deferred as sx;
import '../services/slip_scan.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'attendance_screen.dart';
import 'shift_history_screen.dart';
import 'shift_plan_screen.dart';

/// 班表（隱城、小城外）：一週一張表；最下面是每天人力。
/// 隱城：記號 V／休／指休／O，正職看「本週休」、兼職看「本週上班」。
/// 小城外：班別代碼 B／BH／RBK、休、指休；兼職填時段；以時數統計。
/// 老闆／店長可點格子改班、點日期加備註、管理人員、填統計數字、上傳原始班表照片。
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

const _offColor = Color(0xFFE0A34A);
const _assignedColor = Color(0xFFE5735F);

Color? _markBg(String? m) => switch (m) {
      '休' => _offColor.withValues(alpha: 0.40), // 2026-10-29：降低飽和度，保留紙本班表的顏色辨識
      '指休' => _assignedColor.withValues(alpha: 0.40),
      '特休' => const Color(0xFFC0392B).withValues(alpha: 0.50), // 照老闆紙本班表的紅色（0072）
      'O' => AppColors.primary.withValues(alpha: 0.35),
      // 顏色照老闆班別表：R 白、R1 灰、RBK 粉紫、B 系藍、BHP 系黃
      'R' => const Color(0xFFE8E8E8).withValues(alpha: 0.30),
      'R1' => const Color(0xFFB0B0B0).withValues(alpha: 0.45),
      'RBK' => const Color(0xFFC77DB0).withValues(alpha: 0.55),
      'B' || 'BP' || 'BP+' || 'BH' || 'BH-' => const Color(0xFF6F9BE0).withValues(alpha: 0.50),
      'BHP' || 'BHP-' => const Color(0xFFF2C94C).withValues(alpha: 0.55),
      _ when m != null && ShiftMonth.isRange(m) => AppColors.primary.withValues(alpha: 0.22),
      // 自己新增的班別（0075）：跟 B 系同色
      _ when m != null && m != 'V' && RegExp(r'^[A-Z][A-Z0-9]{0,3}[+-]?$').hasMatch(m) => const Color(0xFF6F9BE0).withValues(alpha: 0.40),
      _ => null,
    };

const _markLabel = {'V': '上班', '休': '休假', '指休': '指定休', '特休': '特休', 'O': 'O'};
final _rangeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d-([01]\d|2[0-3]):[0-5]\d$');

/// 格子裡顯示的字：時段拆成兩行
String _cellText(String? m) => m == null ? '' : (ShiftMonth.isRange(m) ? m.replaceFirst('-', '\n') : m);

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _week = 0; // 第幾週（0 起算，以週日為一週開始）
  late Future<ShiftMonth> _future;
  ShiftMonth? _data;
  ShiftPlanSetup? _setup; // 每天要幾人、指休等（讀不到就是 null，不影響看班表）
  int _claimSeq = 0; // 選了「我是誰」之後讓打卡卡片重新讀
  bool _started = false;
  // 老闆不一定在這家店的班表上：可以把「你是班表上的哪一位？」收起來（記在這支手機、這家店；2026-11-17 老闆誤點選到別人）
  bool _claimHidden = false;
  bool get _isOwner => widget.membership.role == Role.owner;
  String get _claimHiddenKey => 'claim_hidden_$_store';

  bool get _canEdit => widget.membership.isManager;
  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  String get _storeName => widget.membership.storeName;
  ShiftOptions? get _opts => _data?.options;
  List<String> get _marks => storeMarks(_storeName, _opts);
  /// 兼職時段選項（0075：兩家店都有，可自己新增刪除）
  List<String> get _ranges => storeRanges(_storeName, _opts);
  /// 以時數統計（小城外）：null 表示看天數（隱城）
  Map<String, double>? get _codeHours => storeCodeHours(_storeName, _opts);
  Map<String, String> get _codeTimes => storeCodeTimes(_storeName, _opts);
  /// 班別說明：B → 17:00~00:30（沒有時段的記號用中文說明）
  String _markDesc(String m) => _codeTimes[m]?.replaceFirst('-', '~') ?? _markLabel[m] ?? m;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _week = _weekOf(bizToday());
      _future = _load();
      if (_isOwner) _loadClaimHidden();
    }
  }

  Future<void> _loadClaimHidden() async {
    try {
      final v = (await SharedPreferences.getInstance()).getBool(_claimHiddenKey) ?? false;
      if (mounted && v) setState(() => _claimHidden = true);
    } catch (_) {}
  }

  Future<void> _hideClaim() async {
    setState(() => _claimHidden = true);
    try {
      await (await SharedPreferences.getInstance()).setBool(_claimHiddenKey, true);
    } catch (_) {}
    if (mounted) showMessage(context, '已經收起來。之後要對應名字，到「班表人員」點人名指定帳號');
  }

  Future<ShiftMonth> _load() async {
    // 切月份時，上一個月份的資料比較晚回來也不能蓋掉現在看的月份（2026-11-13 健檢）
    final m = _month;
    final r = await Future.wait<Object?>([
      _repo.shiftMonth(_store, m),
      // 排班設定只拿來判斷「排好了沒」和標出缺人的日子；讀不到不擋班表（2026-11-16 健檢）
      _repo.shiftPlanSetup(_store, m).then<ShiftPlanSetup?>((v) => v, onError: (_) => null),
    ]);
    final d = r[0] as ShiftMonth;
    if (m == _month) {
      _data = d;
      _setup = r[1] as ShiftPlanSetup?;
    }
    return d;
  }

  void _reload() => setState(() => _future = _load());

  /// 本月各週的日期範圍（週日～週六）
  List<(int, int)> _weeks() {
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final out = <(int, int)>[];
    var start = 1;
    while (start <= days) {
      final wd = DateTime(_month.year, _month.month, start).weekday % 7; // 週日＝0
      final end = (start + (6 - wd)).clamp(1, days);
      out.add((start, end));
      start = end + 1;
    }
    return out;
  }

  int _weekOf(DateTime d) {
    if (d.year != _month.year || d.month != _month.month) return 0;
    final w = _weeks();
    return w.indexWhere((x) => d.day >= x.$1 && d.day <= x.$2).clamp(0, w.length - 1);
  }

  void _shiftMonth(int n) {
    _month = DateTime(_month.year, _month.month + n);
    _data = null; // 新月份的資料回來以前先轉圈，不拿舊月份的資料配新月份的日期
    _setup = null;
    _week = _weekOf(bizToday());
    _reload();
  }

  // ---------------- 編輯 ----------------
  Future<void> _editCell(ShiftPerson p, int day, String? current) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${p.name}・${DateFormat('M/d（E）', 'zh_TW').format(DateTime(_month.year, _month.month, day))}',
                style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final m in _marks)
                SelectChip(
                  label: Text(m == 'V'
                      ? 'V 上班'
                      : _codeTimes.containsKey(m)
                          ? '$m  ${_markDesc(m)}'
                          : m),
                  selected: m == current,
                  selectedColor: _markBg(m) ?? AppColors.cardHigh,
                  onSelected: (_) => Navigator.pop(c, m),
                ),
              ActionChip(label: const Text('清除'), onPressed: () => Navigator.pop(c, '')),
            ]),
            if (_ranges.isNotEmpty || p.kind == 'part') ...[
              const SizedBox(height: 16),
              Text('兼職時段', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in _ranges)
                  SelectChip(
                    label: Text(r),
                    selected: r == current,
                    onSelected: (_) => Navigator.pop(c, r),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('其他時段'),
                  onPressed: () async {
                    final v = await _askRange(c, current);
                    if (v != null && c.mounted) Navigator.pop(c, v);
                  },
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
    if (picked == null || picked == current || (picked.isEmpty && current == null)) return;
    final mark = picked.isEmpty ? null : picked;
    if (ShiftMonth.isOn(mark) && !await _checkEdit(p, day, mark!)) return;
    // 先改畫面，再存資料庫；失敗就重新載入
    setState(() {
      final m = _data!.marks.putIfAbsent(p.id, () => {});
      if (mark == null) {
        m.remove(day);
      } else {
        m[day] = mark;
      }
    });
    try {
      await _repo.setShift(_store, p.id, DateTime(_month.year, _month.month, day), mark);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      _reload();
    }
  }

  /// 排上班前先檢查（2026-11-16 健檢 B1）：指休的日子、另一家店那天有班＝不能存；
  /// 違反排班條件（固定不排的星期、連上太多、不能同一天…）＝提醒後還是可以存。
  /// 每次都重新讀指休和另一家店的班，才不會用到舊的。
  Future<bool> _checkEdit(ShiftPerson p, int day, String mark) async {
    final m = _month;
    ShiftPlanSetup? setup;
    try {
      setup = await _repo.shiftPlanSetup(_store, m);
    } catch (_) {
      setup = null;
    }
    if (!mounted || m != _month || _data == null) return false;
    if (setup == null) {
      return await _confirm('沒辦法檢查', '讀不到指休和另一家店的班（可能沒網路），這次沒辦法檢查。還是要存嗎？', '還是要存');
    }
    setState(() => _setup = setup);
    final issues = editIssues(data: _data!, setup: setup, personId: p.id, day: day, mark: mark);
    final hard = [for (final i in issues) if (i.level == 0) i.text];
    if (hard.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('這格不能排上班'),
          content: Text('${hard.map((t) => '・$t').join('\n')}\n\n'
              '${issues.any((i) => i.code == 'off') ? '如果他那天真的可以來，請先到「填指休」把那天拿掉。' : '請先跟另一家店確認，把那邊的班改掉。'}'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('知道了'))],
        ),
      );
      return false;
    }
    final soft = [for (final i in issues) if (i.level == 1) i.text];
    if (soft.isEmpty) return true;
    return await _confirm('這樣排會違反排班條件', '${soft.map((t) => '・$t').join('\n')}\n\n確定要這樣排嗎？', '還是要排');
  }

  Future<bool> _confirm(String title, String body, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
          ],
        ),
      ) ==
      true;

  /// 還沒對應班表名字的人：班表頁最上面常駐一行（2026-11-16 健檢 A1；原本只藏在「填指休」裡）
  bool _needClaim(ShiftMonth d) {
    final me = _repo.currentUserId;
    if (me == null || !d.people.any((p) => p.active)) return false;
    if (AppScope.of(context).kiosk?.storeId == _store) return false; // 店裡的打卡用帳號不能連到員工
    return !d.people.any((p) => p.active && p.userId == me);
  }

  Future<void> _claim(ShiftMonth d) async {
    final free = d.people.where((p) => p.active && p.userId == null).toList();
    final picked = await showModalBottomSheet<ShiftPerson>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
            const Text('你是班表上的哪一位？', style: TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('選一次就好。老闆確認後，就能打卡、看自己的出勤和薪資單、自己填指休。',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            const SizedBox(height: 12),
            if (free.isEmpty)
              Text('班表上的名字都有人選了，請找老闆或店長幫你加進班表人員。', style: TextStyle(color: AppColors.warn))
            else
              for (final p in free)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.name),
                  subtitle: Text(p.isFull ? '正職' : '兼職'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(c, p),
                ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final ok = await _confirm('你是「${picked.name}」？', '選了之後只能用這個名字。選錯了請找老闆或店長改。', '是我');
    if (!ok || !mounted) return;
    try {
      await _repo.claimShiftPerson(picked.id);
      if (!mounted) return;
      showMessage(context, '已經選好「${picked.name}」，等老闆確認後就能打卡、看自己的出勤');
      setState(() => _claimSeq++);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Widget _claimCard(ShiftMonth d) {
    if (!_needClaim(d) || (_isOwner && _claimHidden)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => _claim(d),
            child: Row(children: [
              Icon(Icons.person_search_outlined, color: AppColors.warn),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('你是班表上的哪一位？', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warn)),
                  const SizedBox(height: 2),
                  Text(_isOwner ? '有排班才需要選；選了馬上生效，選錯要到「班表人員」改' : '點這裡選你的名字，老闆確認後就能打卡、看自己的出勤',
                      style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
          // 老闆不一定在這家店的班表上：可以收起來，不然每次都在最上面、容易誤點
          if (_isOwner)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _hideClaim,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: AppColors.muted),
                child: const Text('我不在這家店的班表上，不用顯示'),
              ),
            ),
        ]),
      ),
    );
  }

  Future<String?> _askRange(BuildContext ctx, String? current) async {
    final t = TextEditingController(text: ShiftMonth.isRange(current) ? current! : '');
    String? err;
    return showDialog<String>(
      context: ctx,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('輸入時段'),
          content: TextField(
            controller: t,
            autofocus: true,
            decoration: InputDecoration(hintText: '例：18:00-00:30', errorText: err),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final v = t.text.trim().replaceAll('：', ':').replaceAll(RegExp(r'\s'), '').replaceAll(RegExp('[~～－—–]'), '-');
                if (!_rangeRe.hasMatch(v)) {
                  set(() => err = '格式：開始-結束，例 18:00-00:30');
                  return;
                }
                Navigator.pop(d, v);
              },
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(int day, String? current) async {
    final c = TextEditingController(text: current ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${_month.month}/$day 備註'),
        content: TextField(controller: c, autofocus: true, maxLength: 20, decoration: const InputDecoration(hintText: '例：月會日、國慶日')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
          if (current != null) TextButton(onPressed: () => Navigator.pop(d, ''), child: const Text('刪除')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('儲存')),
        ],
      ),
    );
    if (v == null) return;
    try {
      await _repo.setShiftNote(_store, DateTime(_month.year, _month.month, day), v.isEmpty ? null : v);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editStats(ShiftPerson p, ShiftMonth d) async {
    final st = d.stats[p.id] ?? const ShiftStats();
    final hoursMode = _codeHours != null;
    String f(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
    final s = TextEditingController(text: f(hoursMode ? st.compUnused : st.shouldOff));
    final u = TextEditingController(text: f(hoursMode ? st.specialTotal : st.prevUnused));
    DateTime? hire = p.hireDate;
    String? errS, errU;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${p.name}・${_month.month} 月'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: s, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: hoursMode ? '未休／補休（天）' : '本月應休（天）', errorText: errS)),
            TextField(controller: u, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: hoursMode ? '累計特休（天）' : '原未休特休（天）', errorText: errU)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('報到日'),
              trailing: Text(hire == null ? '未填' : DateFormat('yyyy/M/d').format(hire!)),
              onTap: () async {
                final x = await showDatePicker(
                    context: c, initialDate: hire ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2035));
                if (x != null) set(() => hire = x);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            // 打錯的字不能當成空白存檔，會把原本的數字清掉（2026-11-16 健檢 C1）
            FilledButton(
                onPressed: () => set(() {
                      errS = parseDayNumber(s.text).ok ? null : '請只填數字（例：8 或 8.5）';
                      errU = parseDayNumber(u.text).ok ? null : '請只填數字（例：8 或 8.5）';
                      if (errS == null && errU == null) Navigator.pop(c, true);
                    }),
                child: const Text('儲存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final a = parseDayNumber(s.text).value, b = parseDayNumber(u.text).value;
      await _repo.saveShiftStats(
          _store,
          p.id,
          _month,
          hoursMode
              ? ShiftStats(shouldOff: st.shouldOff, prevUnused: st.prevUnused, compUnused: a, specialTotal: b)
              : ShiftStats(shouldOff: a, prevUnused: b, compUnused: st.compUnused, specialTotal: st.specialTotal));
      if (hire != p.hireDate) {
        await _repo.saveShiftPerson(_store, ShiftPerson(id: p.id, name: p.name, kind: p.kind, sortOrder: p.sortOrder, hireDate: hire, active: p.active, roleCode: p.roleCode, userId: p.userId));
      }
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _managePeople(ShiftMonth d) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PeopleScreen(storeId: _store, people: d.people, isOwner: widget.membership.role == Role.owner)));
    _reload();
  }

  Future<void> _uploadPhoto() async {
    String? photo;
    try {
      photo = await pickSlipImage(fromLibrary: true); // 從相簿選已拍好的班表照片
    } catch (e) {
      if (mounted) showMessage(context, '照片讀取失敗：$e', error: true);
      return;
    }
    if (photo == null) return;
    try {
      await _repo.uploadShiftPhoto(_store, _month, dataUrlBytes(photo));
      if (mounted) showMessage(context, '已新增 ${_month.month} 月班表照片，會自動辨識成草稿（1 小時內）');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _showPhoto(String path) => showStoragePhoto(context, path);

  /// 匯出班表 Excel（小城外，老闆 2026-11-04）：手機跳分享選單可「儲存到檔案」或傳 LINE
  Future<void> _export(ShiftMonth d) async {
    try {
      await Future.wait([pl.loadLibrary(), sx.loadLibrary()]);
    } catch (e) {
      if (mounted) showMessage(context, '匯出工具下載失敗，請檢查網路後再試', error: true);
      return;
    }
    try {
      final name = sx.shiftFileName(_storeName, _month);
      final bytes = sx.buildShiftXlsx(
          storeName: _storeName, data: d, marks: _marks, codeHours: _codeHours ?? const {}, codeTimes: _codeTimes);
      final r = await pl.saveFile(bytes, name, pl.xlsxMime);
      if (!mounted) return;
      if (r == 'downloaded') showMessage(context, '已下載 $name');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deletePhoto(ShiftPhoto ph, int no) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('刪掉照片 $no？'),
        content: const Text('只刪這張照片，已經排好的班不會變。剩下的照片會重新辨識一次。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteShiftPhoto(ph.id);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _openDraft(ShiftMonth d, ShiftDraft dr) async {
    final applied = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _DraftScreen(storeId: _store, month: _month, current: d, draft: dr, repo: _repo, markBg: _markBg)));
    if (applied == true && mounted) showMessage(context, '已套用照片上的 ${_month.month} 月班表');
    _reload();
  }

  /// 照片辨識草稿卡片（只有老闆／店長看得到）
  Widget _draftCard(ShiftMonth d) {
    final dr = d.draft;
    if (dr == null || !_canEdit) return const SizedBox.shrink();
    final (IconData icon, Color color, String title, String sub) = dr.isReady
        ? (
            Icons.auto_awesome_outlined,
            AppColors.primary,
            '照片辨識好了，請確認',
            '讀到 ${dr.cellCount} 格${dr.warnings.isEmpty ? '' : '，${dr.warnings.length} 處要看'}・點這裡看草稿再決定要不要套用'
          )
        : dr.isFailed
            ? (Icons.error_outline, AppColors.warn, '照片辨識失敗', '${dr.message ?? ''}　可以刪掉照片重傳，或直接點格子排班')
            : (
                Icons.hourglass_top_outlined,
                AppColors.muted,
                '照片辨識中…',
                dr.message ?? '每小時處理一次，通常 1 小時內好，好了小鈴鐺會通知'
              );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SectionCard(
        child: InkWell(
          onTap: dr.isReady ? () => _openDraft(d, dr) : null,
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              ]),
            ),
            if (dr.isReady) const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }

  Widget _photoRow(ShiftMonth d) {
    if (d.photos.isEmpty && !_canEdit) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(d.photos.isEmpty ? '原始班表照片' : '原始班表照片（${d.photos.length} 張）',
          style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (i, ph) in d.photos.indexed)
          InputChip(
            avatar: const Icon(Icons.image_outlined, size: 18),
            label: Text('照片 ${i + 1}'),
            onPressed: () => _showPhoto(ph.path),
            onDeleted: _canEdit ? () => _deletePhoto(ph, i + 1) : null,
            deleteButtonTooltipMessage: '刪掉這張',
          ),
        // 跟照片同一種小標籤，高度一致（老闆 2026-11-17：下方按鈕大小不一）
        if (_canEdit && d.photos.length < 10)
          ActionChip(
            avatar: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(d.photos.isEmpty ? '從相簿上傳班表照片' : '再加一張'),
            onPressed: _uploadPhoto,
          ),
      ]),
    ]);
  }

  // ---------------- 畫面 ----------------
  @override
  Widget build(BuildContext context) => FutureBuilder<ShiftMonth>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
          // FutureBuilder 換新的 future 時還留著上一份資料，所以要看是不是載完了
          if (_data == null && (snap.connectionState != ConnectionState.done || !snap.hasData)) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = _data ?? snap.data!;
          final weeks = _weeks();
          final wk = weeks[_week.clamp(0, weeks.length - 1)];
          final full = d.people.where((p) => p.active && p.isFull).toList();
          final part = d.people.where((p) => p.active && !p.isFull).toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              Row(children: [
                IconButton(tooltip: '上個月', onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(DateFormat('yyyy 年 M 月', 'zh_TW').format(_month),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: AppType.title)),
                ),
                IconButton(tooltip: '下個月', onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
              ]),
              _claimCard(d),
              _todayCard(d),
              _myMonthCard(d),
              AttendanceCard(
                  key: ValueKey('attendance-$_claimSeq'), membership: widget.membership, data: d, codeTimes: _codeTimes),
              _draftCard(d),
              if (d.people.any((p) => p.active))
                ShiftPlanCard(
                    membership: widget.membership,
                    data: d,
                    viewMonth: _month,
                    scheduled: isMonthScheduled(d, _setup),
                    markBg: _markBg,
                    onChanged: _reload),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (i, w) in weeks.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SelectChip(
                        label: Text(w.$1 == w.$2 ? '${_month.month}/${w.$1}' : '${_month.month}/${w.$1}–${w.$2}'),
                        selected: i == _week,
                        onSelected: (_) => setState(() => _week = i),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              if (d.people.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('這個月還沒有班表', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                )
              else
                SectionCard(padding: const EdgeInsets.fromLTRB(8, 10, 8, 10), child: _weekGrid(d, wk, full, part)),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 4, children: [
                for (final m in _marks) _legend(m, _markBg(m), _markDesc(m)),
                if (_ranges.isNotEmpty) _legend('時段', _markBg('18:00-00:30'), '兼職時段'),
                if (_setup != null) _legend('人力', AppColors.bad.withValues(alpha: 0.25), '紅色＝比需要的人少'),
              ]),
              if (_codeHours != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      '時數：${_codeHours!.entries.where((e) => _marks.contains(e.key)).map((e) => '${e.key} ${_num(e.value)}').join('、')}（小時）；兼職時段照實際時間算',
                      style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
                ),
              const SizedBox(height: 16),
              if (_codeHours != null)
                _hoursSummary(d, [...full, ...part])
              else if (full.isNotEmpty)
                _monthSummary(d, full),
              const SizedBox(height: 12),
              _photoRow(d),
              const SizedBox(height: 16),
              // 下方按鈕排成同寬同高的格子（老闆 2026-11-17：原本大小不一、換行亂掉）：
              // 先是四個班表設定，再來匯出、重新自動排（字比較長，各佔兩格）
              _buttonGrid([
                if (_canEdit) ...[
                  (
                    OutlinedButton.icon(
                      style: _gridButtonStyle,
                      onPressed: () => _managePeople(d),
                      icon: const Icon(Icons.people_outline),
                      label: const Text('班表人員'),
                    ),
                    false
                  ),
                  (
                    OutlinedButton.icon(
                      style: _gridButtonStyle,
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ShiftMarkOptionsScreen(membership: widget.membership, markBg: _markBg)));
                        _reload();
                      },
                      icon: const Icon(Icons.schedule_outlined),
                      label: const Text('班別／時段'),
                    ),
                    false
                  ),
                  // 排班條件常駐（2026-11-16 健檢 A3：原本這個月排好後就進不去）
                  (
                    OutlinedButton.icon(
                      style: _gridButtonStyle,
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ShiftRulesScreen(
                                membership: widget.membership, month: _month, people: d.people, options: d.options)));
                        _reload();
                      },
                      icon: const Icon(Icons.tune),
                      label: const Text('排班條件'),
                    ),
                    false
                  ),
                  // 修改紀錄、整批還原（0113）
                  (
                    OutlinedButton.icon(
                      style: _gridButtonStyle,
                      onPressed: () async {
                        final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                            builder: (_) => ShiftHistoryScreen(membership: widget.membership, month: _month, people: d.people)));
                        if (changed == true) _reload();
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('修改紀錄'),
                    ),
                    false
                  ),
                ],
                if (_codeHours != null && d.people.any((p) => p.active))
                  (
                    OutlinedButton.icon(
                      style: _gridButtonStyle,
                      onPressed: () => _export(d),
                      icon: const Icon(Icons.file_download_outlined),
                      label: Text('匯出 ${_month.month} 月班表（Excel）'),
                    ),
                    true
                  ),
                // 排好的月份也留一個不顯眼的「重新自動排」（老闆 2026-11-16 同意；會保留已經排好的格子）
                if (_canEdit &&
                    isMonthScheduled(d, _setup) &&
                    !_month.isBefore(DateTime(DateTime.now().year, DateTime.now().month)))
                  (
                    // 跟其他格子同大小，但用灰字灰框，不比其他按鈕顯眼
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          foregroundColor: AppColors.muted,
                          side: BorderSide(color: AppColors.line)),
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                ShiftAutoPlanScreen(membership: widget.membership, month: _month, markBg: _markBg)));
                        _reload();
                      },
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: Text('重新自動排 ${_month.month} 月'),
                    ),
                    true
                  ),
              ]),
              if (_canEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: InfoLine(
                    icon: Icons.touch_app_outlined,
                    padding: EdgeInsets.zero,
                    text: '點格子改班、點日期加備註',
                    detail: _codeHours != null
                        ? '點格子改班（兼職可選時段）、點日期加備註、點下方統計填未休／補休與特休。'
                        : '點格子改班（兼職可選時段）、點日期加備註、點下方統計填應休與特休。',
                  ),
                ),
            ]),
          );
        },
      );

  static final _gridButtonStyle = OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8));

  /// 按鈕排成格子：手機 2 欄、寬一點 4 欄，每格同寬、高 48；(按鈕, true) 的佔兩格。沒有按鈕就不佔位置。
  /// 系統字放大時：4 欄要更寬才用（不然字擠成兩行），字真的放不下時整列跟著變高，不會切掉字。
  Widget _buttonGrid(List<(Widget, bool)> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final cols = box.maxWidth >= 520 * scale ? 4 : 2;
      // 取整數，四格加起來才不會因為小數點多出一點點而被擠到下一行
      final cell = ((box.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
      // 一列一列排，同一列的按鈕一樣高（字放大換行時整列一起變高）
      final rows = <List<(Widget, bool)>>[];
      var used = cols;
      for (final item in items) {
        final span = item.$2 ? 2 : 1;
        if (used + span > cols) {
          rows.add([]);
          used = 0;
        }
        rows.last.add(item);
        used += span;
      }
      return Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (i, row) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (j, (button, wide)) in row.indexed) ...[
                  if (j > 0) const SizedBox(width: gap),
                  ConstrainedBox(
                      constraints: BoxConstraints.tightFor(width: wide ? cell * 2 + gap : cell).copyWith(minHeight: 48),
                      child: button),
                ],
              ]),
            ),
          ),
      ]);
    });
  }

  Widget _legend(String m, Color? bg, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          constraints: const BoxConstraints(minWidth: 30),
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: bg ?? Colors.transparent,
              border: bg == null ? Border.all(color: AppColors.cardHigh) : null,
              borderRadius: BorderRadius.circular(AppRadius.xs)),
          child: Text(m, style: const TextStyle(fontSize: AppType.caption)),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      ]);

  /// 我的班（第二批：員工最想看的是自己的班）：已經對應班表名字的人，一個月一張小月曆
  Widget _myMonthCard(ShiftMonth d) {
    final me = _repo.currentUserId;
    final p = me == null ? null : d.people.where((x) => x.active && x.userId == me).firstOrNull;
    if (p == null) return const SizedBox.shrink();
    final days = d.days;
    final firstWd = DateTime(_month.year, _month.month, 1).weekday % 7; // 週日＝0
    final today = bizToday();
    final work = (d.marks[p.id] ?? const <int, String>{}).values.where(ShiftMonth.isOn).length;
    final off = d.offDays(p.id);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('我的 ${_month.month} 月班', style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('上班 $work 天${p.isFull ? '・休 $off 天' : ''}',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (final w in ['日', '一', '二', '三', '四', '五', '六'])
              Expanded(
                  child: Text(w,
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: AppType.micro))),
          ]),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.25,
            children: [
              for (var i = 0; i < firstWd; i++) const SizedBox.shrink(),
              for (var day = 1; day <= days; day++)
                () {
                  final m = d.mark(p.id, day);
                  final isToday = today.year == _month.year && today.month == _month.month && today.day == day;
                  return Container(
                    margin: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: _markBg(m),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      border: isToday
                          ? Border.all(color: AppColors.primary, width: 2)
                          : (_markBg(m) == null ? Border.all(color: AppColors.cardHigh) : null),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('$day', style: TextStyle(fontSize: AppType.micro, color: AppColors.muted)),
                      Text(m == null ? '' : (ShiftMonth.isRange(m) ? m.split('-').first : m),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(fontSize: AppType.small, fontWeight: FontWeight.w700, height: 1.1)),
                    ]),
                  );
                }(),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _todayCard(ShiftMonth d) {
    // 「今天」跟交接、提醒一樣以早上 6 點換日（凌晨還在營業時不會跳到隔天；2026-11-13）
    final now = bizToday();
    if (now.year != _month.year || now.month != _month.month) return const SizedBox.shrink();
    // 有班別／時段的店，名字後面帶班別（V、O 不用寫）
    final on = d.people.where((p) => p.active && ShiftMonth.isOn(d.mark(p.id, now.day))).map((p) {
      final m = d.mark(p.id, now.day)!;
      return (m == 'V' || m == 'O') ? p.name : '${p.name}（${_codeTimes[m] == null ? m : '$m ${_codeTimes[m]}'}）';
    }).toList();
    final off = d.people.where((p) => p.active && p.isFull && ShiftMonth.isAway(d.mark(p.id, now.day))).map((p) => p.name).toList();
    final note = d.notes[now.day];
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('今天 ${DateFormat('M/d（E）', 'zh_TW').format(now)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('人力 ${on.length}', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
        ]),
        if (note != null) Text(note, style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
        const SizedBox(height: 6),
        Text('上班：${on.isEmpty ? '—' : on.join('、')}', style: const TextStyle(fontSize: AppType.small)),
        if (off.isNotEmpty) Text('休：${off.join('、')}', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      ]),
    );
  }

  Widget _weekGrid(ShiftMonth d, (int, int) wk, List<ShiftPerson> full, List<ShiftPerson> part) {
    final scheduled = isMonthScheduled(d, _setup);
    // 一週固定 7 欄（月初、月底不足的日子留空），寬度依螢幕平分
    final firstWd = DateTime(_month.year, _month.month, wk.$1).weekday % 7;
    final cols = List<int?>.generate(7, (i) {
      final day = wk.$1 + (i - firstWd);
      return (day >= wk.$1 && day <= wk.$2) ? day : null;
    });
    const wd = ['日', '一', '二', '三', '四', '五', '六'];
    final today = bizToday();
    return LayoutBuilder(builder: (context, box) {
      // 每格左右各有 1px 間距，要先扣掉，不然最右邊一欄會被裁掉（2026-10-29）
      const nameW = 52.0, sumW = 28.0;
      final cellW = ((box.maxWidth - nameW - sumW) / 7 - 2).clamp(30.0, 60.0);
      Widget cell(Widget child, {Color? bg, VoidCallback? onTap, double h = 30, Border? border}) => GestureDetector(
            onTap: onTap,
            child: Container(
              width: cellW,
              height: h,
              margin: const EdgeInsets.all(1),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.xs), border: border),
              child: child,
            ),
          );
      // 名字不斷行：太長就整個等比例縮小（老闆 2026-10-29）
      Widget name(String t, {bool bold = false, Color? color}) => SizedBox(
            width: nameW,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(t,
                  maxLines: 2,
                  style: TextStyle(fontSize: AppType.small, height: 1.2, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
            ),
          );
      Widget sum(String t, {Color? color}) => SizedBox(
            width: sumW,
            child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.small, color: color ?? AppColors.muted)),
          );
      Widget personRow(ShiftPerson p) {
        final ch = _codeHours;
        final String total;
        if (ch != null && !p.isFull) {
          total = _num(cols.whereType<int>().fold(0.0, (a, day) => a + ShiftMonth.hoursOf(d.mark(p.id, day), ch)));
        } else {
          total = '${cols.whereType<int>().where((day) {
            final m = d.mark(p.id, day);
            return p.isFull ? ShiftMonth.isOff(m) : ShiftMonth.isOn(m);
          }).length}';
        }
        return Row(children: [
          name(p.roleCode == null ? p.name : '${p.name}\n${p.roleCode}'),
          for (final day in cols)
            if (day == null)
              cell(const SizedBox.shrink())
            else
              cell(
                Text(_cellText(d.mark(p.id, day)),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: ShiftMonth.isRange(d.mark(p.id, day)) ? 9 : 12,
                        height: 1.1,
                        fontWeight: FontWeight.w600)),
                h: _codeHours != null || _ranges.isNotEmpty ? 34 : 30,
                bg: _markBg(d.mark(p.id, day)),
                border: _markBg(d.mark(p.id, day)) == null ? Border.all(color: AppColors.cardHigh) : null,
                onTap: _canEdit ? () => _editCell(p, day, d.mark(p.id, day)) : null,
              ),
          sum(total),
        ]);
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 標題：星期、日期、備註
          Row(children: [
            name(''),
            for (final (i, day) in cols.indexed)
              cell(
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(wd[i], style: TextStyle(fontSize: AppType.micro, color: AppColors.muted)),
                  Text(day == null ? '' : '$day',
                      style: TextStyle(
                          fontSize: AppType.small,
                          fontWeight: FontWeight.w700,
                          color: day != null && today.year == _month.year && today.month == _month.month && today.day == day
                              ? AppColors.primary
                              : null)),
                ]),
                h: 36,
                onTap: day != null && _canEdit ? () => _editNote(day, d.notes[day]) : null,
              ),
            sum(''),
          ]),
          if (cols.any((day) => day != null && d.notes[day] != null))
            Row(children: [
              name(''),
              for (final day in cols)
                cell(
                  Text(day == null ? '' : (d.notes[day] ?? ''),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AppType.micro, color: Colors.black)),
                  bg: day != null && d.notes[day] != null ? const Color(0xFF7CC6F2) : null,
                  h: 34, // 字放大到 12，兩行才放得下（2026-11-12）
                  onTap: day != null && _canEdit ? () => _editNote(day, d.notes[day]) : null,
                ),
              sum(''),
            ]),
          const SizedBox(height: 4),
          // 外面是橫向捲動（寬度不限），要給固定寬度 Spacer 才推得開；原本「休」會擠在「正職」旁邊（2026-11-10）
          SizedBox(
            width: nameW + sumW + (cellW + 2) * 7,
            child: Row(children: [name('正職', color: AppColors.muted), const Spacer(), sum('休', color: AppColors.muted)]),
          ),
          for (final p in full) personRow(p),
          if (part.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: nameW + sumW + (cellW + 2) * 7,
              child: Row(children: [name('兼職', color: AppColors.muted), const Spacer(), sum(_codeHours != null ? '時' : '班', color: AppColors.muted)]),
            ),
            for (final p in part) personRow(p),
          ],
          const SizedBox(height: 4),
          Row(children: [
            name('人力', bold: true, color: AppColors.primary),
            for (final day in cols)
              () {
                // 比需要的人少就標紅（2026-11-16 健檢 B2；讀不到排班設定就不標；還沒開始排的日子不標，整片紅只會干擾）
                final short = day != null &&
                    _setup != null &&
                    (scheduled || d.people.any((p) => d.mark(p.id, day) != null)) &&
                    d.staffing(day) < dayNeed(_month, day, _setup);
                return cell(
                  Text(day == null ? '' : '${d.staffing(day)}',
                      style: TextStyle(
                          fontSize: AppType.small,
                          fontWeight: FontWeight.w800,
                          color: short ? AppColors.bad : AppColors.primary)),
                  bg: short ? AppColors.bad.withValues(alpha: 0.18) : null,
                );
              }(),
            sum(''),
          ]),
        ]),
      );
    });
  }

  Widget _monthSummary(ShiftMonth d, List<ShiftPerson> full) {
    String n(double? v) => v == null ? '—' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));
    TableRow row(List<String> cells, {bool head = false, VoidCallback? onTap}) => TableRow(children: [
          for (final (i, c) in cells.indexed)
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Text(c,
                    textAlign: i == 0 ? TextAlign.left : TextAlign.center,
                    style: TextStyle(
                        fontSize: head ? 11 : 13,
                        color: head ? AppColors.muted : null,
                        fontWeight: i == 0 && !head ? FontWeight.w600 : null)),
              ),
            ),
        ]);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_month.month} 月休假統計（正職）', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 6),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3)},
          children: [
            row(['', '應休', '已休', '原未休\n特休', '剩餘未休\n特休', '報到日'], head: true),
            for (final p in full)
              () {
                final st = d.stats[p.id] ?? const ShiftStats();
                final should = st.shouldOff, prev = st.prevUnused;
                final taken = d.offDays(p.id).toDouble();
                // 排「特休」的天數直接用掉特休（0072，老闆 2026-10-27 隱城也加特休）
                final leave = d.leaveDays(p.id).toDouble();
                final remain = (should != null && prev != null) ? prev - (taken - should) - leave : null;
                return row([
                  p.name,
                  n(should),
                  n(taken),
                  n(prev),
                  n(remain),
                  p.hireDate == null ? '—' : DateFormat('yy/M/d').format(p.hireDate!),
                ], onTap: _canEdit ? () => _editStats(p, d) : null);
              }(),
          ],
        ),
        const SizedBox(height: 4),
        const InfoLine(
          icon: null,
          padding: EdgeInsets.zero,
          text: '怎麼算的',
          detail: '已休＝休＋指休；剩餘未休特休＝原未休特休 −（已休 − 應休）− 排特休的天數',
        ),
      ]),
    );
  }

  /// 小城外：總時數（自動算）、月休（自動算）、未休／補休、累計特休（手動）
  Widget _hoursSummary(ShiftMonth d, List<ShiftPerson> people) {
    final ch = _codeHours!;
    String n(double? v) => v == null ? '—' : _num(v);
    TableRow row(List<String> cells, {bool head = false, VoidCallback? onTap}) => TableRow(children: [
          for (final (i, c) in cells.indexed)
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Text(c,
                    textAlign: i == 0 ? TextAlign.left : TextAlign.center,
                    style: TextStyle(
                        fontSize: head ? 11 : 13,
                        color: head ? AppColors.muted : null,
                        fontWeight: i == 0 && !head ? FontWeight.w600 : null)),
              ),
            ),
        ]);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_month.month} 月統計', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 6),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3)},
          children: [
            row(['', '總時數', '上班\n天數', '月休', '未休\n補休', '累計\n特休'], head: true),
            for (final p in people)
              () {
                final st = d.stats[p.id] ?? const ShiftStats();
                return row([
                  p.isFull ? p.name : '${p.name}（兼）',
                  _num(d.hours(p.id, ch)),
                  '${d.workDays(p.id)}',
                  p.isFull ? '${d.offDays(p.id)}' : '—',
                  p.isFull ? n(st.compUnused) : '—',
                  p.isFull ? n(st.specialTotal) : '—',
                ], onTap: _canEdit && p.isFull ? () => _editStats(p, d) : null);
              }(),
          ],
        ),
        const SizedBox(height: 4),
        const InfoLine(
          icon: null,
          padding: EdgeInsets.zero,
          text: '怎麼算的',
          detail: '總時數＝整個月（含月底最後一天）；月休＝休＋指休（特休另計、不算月休）；未休／補休、累計特休由老闆或店長填。',
        ),
      ]),
    );
  }
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// 班表人員：新增、改名、正職／兼職、排序、隱藏
class _PeopleScreen extends StatefulWidget {
  const _PeopleScreen({required this.storeId, required this.people, this.isOwner = false});
  final String storeId;
  final List<ShiftPerson> people;
  final bool isOwner; // 老闆可以直接指定 App 帳號（0113）
  @override
  State<_PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<_PeopleScreen> {
  late List<ShiftPerson> _people = [...widget.people];
  List<ShiftAccountCandidate> _accounts = const [];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _loadAccounts();
    }
  }

  Future<void> _loadAccounts() async {
    if (!widget.isOwner) return;
    try {
      final a = await AppScope.of(context).repo.shiftAccountCandidates(widget.storeId);
      if (mounted) setState(() => _accounts = a);
    } catch (_) {
      // 資料庫還沒更新：不顯示指定帳號
    }
  }

  String? _accountName(ShiftPerson p) => p.userId == null
      ? null
      : (_accounts.where((a) => a.userId == p.userId).firstOrNull?.name ?? '已綁定的帳號');

  Future<void> _reloadPeople() async {
    final d = await AppScope.of(context).repo.shiftMonth(widget.storeId, DateTime.now());
    if (mounted) setState(() => _people = d.people);
    await _loadAccounts();
  }

  /// 老闆直接替這個人指定 App 帳號（＝確認，不用等員工自己選；0113）
  Future<void> _assign(ShiftPerson p) async {
    const none = '\u0000';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
            Text('「${p.name}」是哪一個 App 帳號？', style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('老闆指定的就算確認好了，那個人可以直接打卡、看自己的出勤和薪資單。',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            const SizedBox(height: 8),
            for (final a in _accounts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                selected: a.userId == p.userId,
                title: Text(a.name.isEmpty ? '（沒有名字）' : a.name),
                subtitle: Text([
                  roleLabel(roleFrom(a.role)),
                  if (a.personName != null && a.personId != p.id) '目前是「${a.personName}」，改指定會解除那邊',
                  if (a.personId == p.id) a.verified ? '目前就是這個帳號' : '目前就是這個帳號（還沒確認）',
                ].join('・'), style: const TextStyle(fontSize: AppType.small)),
                onTap: () => Navigator.pop(c, a.userId),
              ),
            if (p.userId != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_off),
                title: const Text('不指定（解除）'),
                onTap: () => Navigator.pop(c, none),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await AppScope.of(context).repo.assignShiftAccount(p.id, picked == none ? null : picked);
      if (!mounted) return;
      showMessage(context, picked == none ? '已解除「${p.name}」的帳號' : '已指定，「${p.name}」可以直接用了');
      await _reloadPeople();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _edit(ShiftPerson? p) async {
    final name = TextEditingController(text: p?.name ?? '');
    final order = TextEditingController(text: '${p?.sortOrder ?? (_people.length + 1) * 10}');
    var kind = p?.kind ?? 'full';
    final role = TextEditingController(text: p?.roleCode ?? '');
    var active = p?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(p == null ? '新增人員' : '修改 ${p.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, maxLength: 20, decoration: const InputDecoration(labelText: '名字')),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'full', label: Text('正職')), ButtonSegment(value: 'part', label: Text('兼職'))],
              selected: {kind},
              onSelectionChanged: (v) => set(() => kind = v.first),
            ),
            TextField(controller: role, maxLength: 10, decoration: const InputDecoration(labelText: '職務／班別（選填，例 B/R）')),
            TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '排序（數字小的在上面）')),
            if (p != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('顯示在班表'),
                value: active,
                onChanged: (v) => set(() => active = v),
              ),
            if (p != null && widget.isOwner && _accounts.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                  label: Text(p.userId == null ? '指定 App 帳號' : 'App 帳號：${_accountName(p)}（改指定）'),
                  onPressed: () {
                    Navigator.pop(c, false);
                    _assign(p);
                  },
                ),
              ),
            if (p != null && p.userId != null && !(widget.isOwner && _accounts.isNotEmpty))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('解除對應的 App 帳號（選錯人時用）'),
                  onPressed: () async {
                    try {
                      await AppScope.of(context).repo.clearShiftPersonUser(p.id);
                      if (c.mounted) Navigator.pop(c, false);
                      final d = await AppScope.of(context).repo.shiftMonth(widget.storeId, DateTime.now());
                      if (mounted) setState(() => _people = d.people);
                    } catch (e) {
                      if (mounted) showMessage(context, friendlyError(e), error: true);
                    }
                  },
                ),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('儲存')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    final repo = AppScope.of(context).repo;
    final np = ShiftPerson(
        id: p?.id ?? '',
        name: name.text.trim(),
        kind: kind,
        sortOrder: int.tryParse(order.text) ?? 0,
        hireDate: p?.hireDate,
        active: active,
        roleCode: role.text.trim().isEmpty ? null : role.text.trim(),
        userId: p?.userId);
    try {
      await repo.saveShiftPerson(widget.storeId, np, isNew: p == null);
      final d = await repo.shiftMonth(widget.storeId, DateTime.now());
      if (mounted) setState(() => _people = d.people);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('班表人員')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('新增人員'),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          for (final p in _people)
            ListTile(
              title: Text(p.name, style: TextStyle(color: p.active ? null : AppColors.muted)),
              subtitle: Text('${p.isFull ? '正職' : '兼職'}${p.roleCode == null ? '' : '・${p.roleCode}'}・排序 ${p.sortOrder}${p.active ? '' : '・已隱藏'}${p.userId == null ? '・還沒對應 App 帳號' : '・已對應 App 帳號'}',
                  style: const TextStyle(fontSize: AppType.small)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _edit(p),
            ),
          const SizedBox(height: 8),
          Text('人員不會被刪除（避免舊班表對不上）；不用了就關掉「顯示在班表」。'
              '員工可以在班表頁最上面自己選名字（老闆確認後才算）${widget.isOwner ? '；老闆也可以點人名直接指定 App 帳號' : '，選錯了在這裡解除'}。',
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        ]),
      );
}

/// 照片辨識草稿：整月預覽（跟目前班表不同的格子框起來）→ 套用或捨棄（0070）
class _DraftScreen extends StatefulWidget {
  const _DraftScreen(
      {required this.storeId,
      required this.month,
      required this.current,
      required this.draft,
      required this.repo,
      required this.markBg});
  final String storeId;
  final DateTime month;
  final ShiftMonth current;
  final ShiftDraft draft;
  final Repository repo;
  final Color? Function(String?) markBg;
  @override
  State<_DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends State<_DraftScreen> {
  bool _busy = false;

  ShiftDraft get _d => widget.draft;
  int get _days => DateTime(widget.month.year, widget.month.month + 1, 0).day;

  String? _now(String name, int day) {
    final p = widget.current.people.where((x) => x.name == name).firstOrNull;
    return p == null ? null : widget.current.mark(p.id, day);
  }

  /// 跟目前班表不同的格子數（含目前有、照片上沒有的）
  int get _changed {
    var n = 0;
    final names = {..._d.entries.keys, ...widget.current.people.map((p) => p.name)};
    for (final name in names) {
      for (var day = 1; day <= _days; day++) {
        if ((_d.entries[name]?[day]) != _now(name, day)) n++;
      }
    }
    return n;
  }

  List<String> get _newPeople =>
      [for (final p in _d.people) if (!widget.current.people.any((x) => x.name == p.name)) p.name];

  /// 目前有排班、但照片上沒有的人（套用後這個月會變空白）
  List<String> get _dropped => [
        for (final p in widget.current.people)
          if ((widget.current.marks[p.id] ?? const {}).isNotEmpty && !_d.entries.containsKey(p.name)) p.name
      ];

  Future<void> _apply() async {
    // 資料庫會擋「指休那天排上班」「另一家店那天有班」，一格被擋整月都不會套用（0113）：先列出來
    setState(() => _busy = true);
    List<String>? conflicts;
    try {
      final setup = await widget.repo.shiftPlanSetup(widget.storeId, widget.month);
      conflicts = draftConflicts(month: widget.month, entries: _d.entries, people: widget.current.people, setup: setup);
    } catch (_) {
      conflicts = null; // 讀不到就交給資料庫擋
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (conflicts != null && conflicts.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('有 ${conflicts!.length} 格不能排上班'),
          content: SingleChildScrollView(
            child: Text('${conflicts.take(20).map((t) => '・$t').join('\n')}'
                '${conflicts.length > 20 ? '\n…還有 ${conflicts.length - 20} 格' : ''}\n\n'
                '照片上這幾天排了上班。請先到「填指休」把那天拿掉，或跟另一家店確認改班，再回來套用。'),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('知道了'))],
        ),
      );
      return;
    }
    final hasData = widget.current.marks.values.any((m) => m.isNotEmpty);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('套用到 ${widget.month.month} 月班表？'),
        content: Text([
          if (hasData) '${widget.month.month} 月目前的班會整個換成照片上的內容（$_changed 格不同）。'
          else '會把照片上的 ${_d.cellCount} 格排進 ${widget.month.month} 月班表。',
          if (_newPeople.isNotEmpty) '會新增班表人員：${_newPeople.join('、')}。',
          if (_dropped.isNotEmpty) '${_dropped.join('、')} 不在照片上，這個月的班會清空。',
          '套用後還是可以點格子修改。',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('套用')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.repo.applyShiftDraft(_d);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _dismiss() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('捨棄這份草稿？'),
        content: const Text('班表不會變動，照片會留著。之後再加照片或刪照片，會重新辨識一次。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('捨棄')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.repo.dismissShiftDraft(_d.id);
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  Widget _cell(String? text, {Color? bg, bool changed = false, bool header = false, double w = 44}) => Container(
        width: w,
        height: header ? 36 : 34,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: changed ? Border.all(color: AppColors.primary, width: 2) : null,
        ),
        child: Text(text ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: header ? 11 : (text != null && text.length > 4 ? 9 : 12), height: 1.1)),
      );

  @override
  Widget build(BuildContext context) {
    final wd = DateFormat('E', 'zh_TW');
    final full = _d.people.where((p) => p.kind == 'full').toList();
    final part = _d.people.where((p) => p.kind != 'full').toList();
    Widget row(ShiftDraftPerson p) => Row(children: [
          _cell(p.name, w: 64),
          for (var day = 1; day <= _days; day++)
            _cell(
              (_d.entries[p.name]?[day])?.replaceFirst('-', '\n'),
              bg: widget.markBg(_d.entries[p.name]?[day]),
              changed: (_d.entries[p.name]?[day]) != _now(p.name, day),
            ),
        ]);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.month.month} 月班表草稿')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text(
            '依 ${_d.photoCount ?? widget.current.photos.length} 張照片讀出 ${_d.cellCount} 格。'
            '${widget.current.marks.values.any((m) => m.isNotEmpty) ? '框起來的是跟目前班表不同的格子（$_changed 格）。' : ''}'
            '文字辨識可能讀錯，請對照照片看過再套用。',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        if (_d.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('要特別看的地方', style: TextStyle(color: AppColors.warn, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final w in _d.warnings)
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('・$w', style: const TextStyle(fontSize: AppType.small))),
            ]),
          ),
        ],
        if (_newPeople.isNotEmpty || _dropped.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (_newPeople.isNotEmpty) Text('新的人（套用時自動加進班表人員）：${_newPeople.join('、')}', style: const TextStyle(fontSize: AppType.small)),
          if (_dropped.isNotEmpty)
            Text('照片上沒有、這個月會清空：${_dropped.join('、')}', style: TextStyle(fontSize: AppType.small, color: AppColors.warn)),
        ],
        const SizedBox(height: 12),
        SectionCard(
          padding: const EdgeInsets.all(6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _cell('', w: 64, header: true),
                for (var day = 1; day <= _days; day++)
                  _cell('$day\n${wd.format(DateTime(widget.month.year, widget.month.month, day))}', header: true),
              ]),
              if (_d.notes.isNotEmpty)
                Row(children: [
                  _cell('備註', w: 64),
                  for (var day = 1; day <= _days; day++)
                    _cell(_d.notes[day], bg: _d.notes[day] == null ? null : AppColors.primary.withValues(alpha: 0.15)),
                ]),
              for (final p in full) row(p),
              if (part.isNotEmpty) const SizedBox(height: 6),
              for (final p in part) row(p),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, ph) in widget.current.photos.indexed)
            ActionChip(
              avatar: const Icon(Icons.image_outlined, size: 18),
              label: Text('看照片 ${i + 1}'),
              onPressed: () => showStoragePhoto(context, ph.path),
            ),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton(onPressed: _busy ? null : _dismiss, child: const Text('捨棄')),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _busy ? null : _apply,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('套用到 ${widget.month.month} 月班表'),
            ),
          ),
        ]),
      ]),
    );
  }
}
