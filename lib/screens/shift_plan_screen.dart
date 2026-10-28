import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/shift_marks.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 自動排班（老闆 2026-10-27，0073）
///   * 填想休／可以上：所有成員（含兼職），只能改自己的、下個月、截止日以前；老闆店長隨時可改任何人
///   * 排班條件：老闆、店長
///   * 自動排班：老闆、店長；App 端算 → 草稿預覽（可點格子改）→ 套用

typedef MarkBg = Color? Function(String?);

const _wdNames = ['一', '二', '三', '四', '五', '六', '日'];
String _wdName(int w) => '週${_wdNames[w - 1]}';
final _md = DateFormat('M/d', 'zh_TW');

List<String> _storeMarks(String storeName, ShiftOptions? o) => storeMarks(storeName, o);
bool _isWork(String? m) => ShiftMonth.isOn(m);

/// 排班時算正職嗎（排班條件設「排班時當兼職」的正職，排班時跟兼職一樣；0074）
bool _planFull(ShiftPerson p, ShiftPlanSetup? s) => p.isFull && !(s?.rules[p.id]?.planAsPart ?? false);

/// 這家店沒設排班條件時，上班用的記號
List<String> _defaultMarks(String storeName, bool full, ShiftOptions? o) {
  if (storeName != '小城外') return const ['V'];
  if (full) {
    final codes = [for (final c in o?.codes ?? const <ShiftMarkOption>[]) c.mark];
    return codes.isNotEmpty ? codes.take(2).toList() : const ['B', 'BH'];
  }
  final rs = storeRanges(storeName, o);
  return rs.isNotEmpty ? [rs.first] : const ['18:00-00:30'];
}

// =====================================================================
// 班表頁上的「排班」卡片
// =====================================================================
class ShiftPlanCard extends StatelessWidget {
  const ShiftPlanCard({super.key, required this.membership, required this.data, required this.viewMonth, required this.markBg, required this.onChanged});
  final Membership membership;
  final ShiftMonth data; // 目前看的月份（用它的人員名單）
  final DateTime viewMonth;
  final MarkBg markBg;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1);
    final manager = membership.isManager;
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(sub, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        );
    Future<void> go(Widget w) async {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
      onChanged();
    }

    // 跟著目前看的月份（老闆 2026-10-27）：
    //   * 這個月已經排好班（有人有格子）→ 整張卡片不顯示（填指休、自動排班、排班條件都不出現）
    //   * 「填指休」只在下個月以後才有（員工只能填下個月以後）；「自動排班」不排已經過去的月份
    final thisMonth = DateTime(now.year, now.month);
    final scheduled = data.people.any((p) => p.active && (data.marks[p.id]?.isNotEmpty ?? false));
    final showRequest = !scheduled && !viewMonth.isBefore(next);
    final showAuto = manager && !scheduled && !viewMonth.isBefore(thisMonth);
    final tiles = <Widget>[
      if (showRequest)
        tile(Icons.event_busy_outlined, '填 ${viewMonth.month} 月指休／可以上的日子', '正職點指休、兼職點可以上，排班會照著排',
            () => go(ShiftRequestScreen(membership: membership, month: viewMonth))),
      if (showAuto)
        tile(Icons.auto_awesome_outlined, '自動排 ${viewMonth.month} 月班表', '先出草稿給你看，確認才套用',
            () => go(ShiftAutoPlanScreen(membership: membership, month: viewMonth, markBg: markBg))),
      if (manager && !scheduled)
        tile(Icons.tune, '排班條件', '每天要幾人、每個人的條件、填寫截止日',
            () => go(ShiftRulesScreen(membership: membership, month: viewMonth, people: data.people, options: data.options))),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Column(children: [
          for (final (i, t) in tiles.indexed) ...[
            if (i > 0) Divider(height: 8, color: AppColors.cardHigh),
            t,
          ],
        ]),
      ),
    );
  }
}

// =====================================================================
// 填想休／可以上
// =====================================================================
class ShiftRequestScreen extends StatefulWidget {
  const ShiftRequestScreen({super.key, required this.membership, required this.month});
  final Membership membership;
  final DateTime month;
  @override
  State<ShiftRequestScreen> createState() => _ShiftRequestScreenState();
}

class _ShiftRequestScreenState extends State<ShiftRequestScreen> {
  late DateTime _month = widget.month;
  ShiftMonth? _sm;
  ShiftPlanSetup? _setup;
  String? _personId; // 正在填誰的
  Object? _error;
  bool _loading = true;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  bool get _manager => widget.membership.isManager;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load(first: true);
    }
  }

  Future<void> _load({bool first = false}) async {
    if (!first) setState(() => _loading = true);
    try {
      final r = await Future.wait<dynamic>([_repo.shiftMonth(_store, _month), _repo.shiftPlanSetup(_store, _month)]);
      final sm = r[0] as ShiftMonth;
      final me = sm.people.where((p) => p.active && p.userId != null && p.userId == _repo.currentUserId).firstOrNull;
      setState(() {
        _sm = sm;
        _setup = r[1] as ShiftPlanSetup;
        _personId ??= me?.id ?? (_manager ? sm.people.where((p) => p.active).firstOrNull?.id : null);
        if (!_manager) _personId = me?.id;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  ShiftPerson? get _me => _sm?.people.where((p) => p.active && p.userId != null && p.userId == _repo.currentUserId).firstOrNull;
  ShiftPerson? get _person => _sm?.people.where((p) => p.id == _personId).firstOrNull;

  DateTime get _deadline => ShiftPlanSetup.deadlineFor(_month, _setup?.deadline ?? 20);
  bool get _open {
    if (_manager) return true;
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    return !d.isAfter(_deadline) && !DateTime(_month.year, _month.month).isBefore(DateTime(today.year, today.month + 1));
  }

  Future<void> _claim(ShiftPerson p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('你是「${p.name}」？'),
        content: const Text('選了之後只能填這個人的日子。選錯了請找老闆或店長改。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('是我')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.claimShiftPerson(p.id);
      _personId = p.id;
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _tap(int day) async {
    final p = _person;
    if (p == null) return;
    if (!_open) {
      showMessage(context, '已經過了填寫截止日，要改請找老闆或店長', error: true);
      return;
    }
    final cur = _setup!.requests[p.id]?[day];
    // 正職：想休 → 想上班 → 取消；兼職：可以上 → 不能上 → 取消
    final order = _planFull(p, _setup) ? [null, 'off', 'on'] : [null, 'on', 'off'];
    final next = order[(order.indexOf(cur) + 1) % order.length];
    setState(() {
      final m = _setup!.requests.putIfAbsent(p.id, () => {});
      if (next == null) {
        m.remove(day);
      } else {
        m[day] = next;
      }
    });
    try {
      await _repo.setShiftRequest(_store, p.id, DateTime(_month.year, _month.month, day), next);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${_month.month} 月指休／可以上')),
      body: _loading && _sm == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: friendlyError(_error!), onRetry: _load)
              : _body(),
    );
  }

  Widget _body() {
    final sm = _sm!;
    final active = sm.people.where((p) => p.active).toList();
    if (!_manager && _me == null) {
      final free = active.where((p) => p.userId == null).toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('你是班表上的哪一位？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('第一次使用要先選一次，之後就不用再選。', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 12),
        if (free.isEmpty)
          Text('班表上的名字都有人選了，請找老闆或店長幫你加進班表人員。', style: TextStyle(color: AppColors.warn))
        else
          for (final p in free)
            Card(
              color: AppColors.card,
              child: ListTile(
                title: Text(p.name),
                subtitle: Text(p.isFull ? '正職' : '兼職'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _claim(p),
              ),
            ),
      ]);
    }
    final p = _person;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWd = DateTime(_month.year, _month.month, 1).weekday % 7; // 週日＝0
    final req = _setup!.requests;
    final mine = p == null ? const <int, String>{} : (req[p.id] ?? const {});
    int othersOff(int d) => req.entries.where((e) => e.key != p?.id && e.value[d] == 'off').length;
    final offCount = mine.values.where((v) => v == 'off').length;
    final onCount = mine.values.where((v) => v == 'on').length;

    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
      Row(children: [
        IconButton(
            onPressed: () {
              _month = DateTime(_month.year, _month.month - 1);
              _load();
            },
            icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text(DateFormat('yyyy 年 M 月', 'zh_TW').format(_month),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        ),
        IconButton(
            onPressed: () {
              _month = DateTime(_month.year, _month.month + 1);
              _load();
            },
            icon: const Icon(Icons.chevron_right)),
      ]),
      if (_manager)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DropdownButtonFormField<String>(
            value: _personId,
            decoration: const InputDecoration(labelText: '填誰的（老闆、店長可以替大家填）'),
            items: [
              for (final x in active)
                DropdownMenuItem(value: x.id, child: Text('${x.name}（${x.isFull ? '正職' : '兼職'}）${x.id == _me?.id ? '・我' : ''}')),
            ],
            onChanged: (v) => setState(() => _personId = v),
          ),
        ),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p == null ? '' : '${p.name}・${p.isFull ? '正職' : '兼職'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            _open
                ? '${_md.format(_deadline)} 前可以改${_manager ? '（老闆、店長隨時可改）' : ''}'
                : '已經過了填寫截止日（${_md.format(_deadline)}），要改請找老闆或店長',
            style: TextStyle(color: _open ? AppColors.muted : AppColors.warn, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            p == null
                ? ''
                : _planFull(p, _setup)
                    ? '點一下＝指休，再點＝想上班，再點＝取消。目前指休 $offCount 天${onCount > 0 ? '、想上班 $onCount 天' : ''}。'
                    : '點一下＝可以上，再點＝不能上，再點＝取消。有填可以上，排班就只排那些天。目前可以上 $onCount 天${offCount > 0 ? '、不能上 $offCount 天' : ''}。',
            style: const TextStyle(fontSize: 13),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        for (final w in ['日', '一', '二', '三', '四', '五', '六'])
          Expanded(child: Text(w, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12))),
      ]),
      const SizedBox(height: 4),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.82,
        children: [
          for (var i = 0; i < firstWd; i++) const SizedBox.shrink(),
          for (var d = 1; d <= days; d++) _dayCell(d, mine[d], othersOff(d), sm.notes[d]),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 4, children: [
        _legend(const Color(0xFFE0A34A), '指休／不能上'),
        _legend(AppColors.good, '可以上／想上班'),
        Text('右上小數字＝其他人指休', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
    ]);
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ]);

  Widget _dayCell(int d, String? kind, int others, String? note) {
    final bg = kind == 'off'
        ? const Color(0xFFE0A34A).withValues(alpha: 0.85)
        : kind == 'on'
            ? AppColors.good.withValues(alpha: 0.75)
            : null;
    return GestureDetector(
      onTap: () => _tap(d),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: bg == null ? Border.all(color: AppColors.cardHigh) : null,
        ),
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$d', style: TextStyle(fontWeight: FontWeight.w700, color: _open ? null : AppColors.muted)),
              Text(kind == 'off' ? (_person == null || _planFull(_person!, _setup) ? '指休' : '不能上') : kind == 'on' ? (_person == null || _planFull(_person!, _setup) ? '想上' : '可以上') : (note ?? ''),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
            ]),
          ),
          if (others > 0)
            Positioned(
              right: 4,
              top: 2,
              child: Text('$others', style: TextStyle(fontSize: 10, color: AppColors.warn, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }
}

// =====================================================================
// 排班條件
// =====================================================================
class ShiftRulesScreen extends StatefulWidget {
  const ShiftRulesScreen({super.key, required this.membership, required this.month, required this.people, this.options});
  final Membership membership;
  final DateTime month;
  final List<ShiftPerson> people;
  final ShiftOptions? options;
  @override
  State<ShiftRulesScreen> createState() => _ShiftRulesScreenState();
}

class _ShiftRulesScreenState extends State<ShiftRulesScreen> {
  ShiftPlanSetup? _setup;
  Map<int, StaffingNeed> _staff = {};
  bool _staffDirty = false;
  Object? _error;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  String get _storeName => widget.membership.storeName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_setup == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.shiftPlanSetup(_store, widget.month);
      setState(() {
        _setup = s;
        _staff = {for (var w = 1; w <= 7; w++) w: s.staffing[w] ?? const StaffingNeed(3, 1)};
        _staffDirty = false;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _saveStaff() async {
    try {
      await _repo.saveShiftStaffing(_store, _staff);
      if (mounted) showMessage(context, '已儲存每天需要的人數');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _addSpecial() async {
    final m = widget.month;
    final d = await showDatePicker(
        context: context, initialDate: DateTime(m.year, m.month, 1), firstDate: DateTime(m.year, m.month, 1), lastDate: DateTime(m.year, m.month + 1, 0));
    if (d == null || !mounted) return;
    final n = await _askNumber('${_md.format(d)} 要幾個人', (_setup!.specialDays[d.day] ?? _staff[d.weekday]?.need ?? 3) + 1);
    if (n == null) return;
    try {
      await _repo.setShiftStaffingDay(_store, d, n);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<int?> _askNumber(String title, int initial) {
    var v = initial;
    return showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(title),
          content: _Stepper(value: v, min: 0, max: 50, onChanged: (x) => set(() => v = x), suffix: '人'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, v), child: const Text('確定')),
          ],
        ),
      ),
    );
  }

  Future<void> _editDeadline() async {
    var v = _setup!.deadline;
    final n = await showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('每月幾號前填好下個月'),
          content: _Stepper(value: v, min: 1, max: 28, onChanged: (x) => set(() => v = x), suffix: '號'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, v), child: const Text('儲存')),
          ],
        ),
      ),
    );
    if (n == null) return;
    try {
      await _repo.saveShiftDeadline(_store, n);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editRule(ShiftPerson p) async {
    final r0 = _setup!.rules[p.id] ?? ShiftRule(personId: p.id);
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _RuleEditor(person: p, rule: r0, storeName: _storeName, storeId: _store, repo: _repo, options: widget.options)));
    if (saved == true) _load();
  }

  String _pname(String id) => widget.people.where((p) => p.id == id).firstOrNull?.name ?? '（已移除）';
  String _pairText(PairRule r) =>
      r.isApart ? '${_pname(r.a)} 跟 ${_pname(r.b)} 不能同一天上班' : '${_pname(r.a)} 上班的日子，${_pname(r.b)} 也要上班';

  Widget _pairRulesCard() => SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('自訂規則', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('例如：誰跟誰不能同一天上班、新人要跟誰一起上。自動排班一定照著排；只有老闆、店長看得到。',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          if (_setup!.pairRules.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('還沒有', style: TextStyle(color: AppColors.muted))),
          for (final r in _setup!.pairRules)
            Row(children: [
              Icon(r.isApart ? Icons.do_not_disturb_alt : Icons.group_outlined, size: 18, color: r.isApart ? AppColors.warn : AppColors.good),
              const SizedBox(width: 8),
              Expanded(child: Text(_pairText(r))),
              IconButton(
                tooltip: '刪掉這條',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  try {
                    await _repo.deleteShiftPairRule(r.id);
                    _load();
                  } catch (e) {
                    if (mounted) showMessage(context, friendlyError(e), error: true);
                  }
                },
              ),
            ]),
          TextButton.icon(onPressed: _addPairRule, icon: const Icon(Icons.add), label: const Text('新增規則')),
        ]),
      );

  Future<void> _addPairRule() async {
    final ps = widget.people.where((p) => p.active).toList();
    if (ps.length < 2) return;
    String? a, b;
    var kind = 'apart';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('新增規則'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'apart', label: Text('不能同一天')),
                ButtonSegment(value: 'with', label: Text('要一起上')),
              ],
              selected: {kind},
              onSelectionChanged: (v) => set(() => kind = v.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: a,
              decoration: InputDecoration(labelText: kind == 'apart' ? '這個人' : '這個人上班的日子'),
              items: [for (final p in ps) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => set(() {
                a = v;
                if (b == a) b = null;
              }),
            ),
            DropdownButtonFormField<String>(
              value: b,
              decoration: InputDecoration(labelText: kind == 'apart' ? '跟這個人不能同一天上班' : '這個人也要上班'),
              items: [for (final p in ps) if (p.id != a) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => set(() => b = v),
            ),
            const SizedBox(height: 8),
            Text(kind == 'apart' ? '例：Perry 跟 Eason 不能同一天上班' : '例：新人上班的日子，老手也要上班（反過來不一定）',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('新增')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (a == null || b == null || a == b) {
      if (mounted) showMessage(context, '請選兩個不同的人', error: true);
      return;
    }
    try {
      await _repo.addShiftPairRule(_store, a!, b!, kind);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e).contains('duplicate') || friendlyError(e).contains('重複') ? '這條規則已經有了' : friendlyError(e), error: true);
    }
  }

  String _ruleSummary(ShiftPerson p) {
    final r = _setup!.rules[p.id];
    if (r == null || r.isEmpty) return '沒設（照預設排）';
    return [
      if (p.isFull && r.planAsPart) '排班時當兼職',
      if (p.isFull && !r.planAsPart && r.monthOff != null) '每月休 ${_n(r.monthOff!)} 天',
      if (r.minShifts != null || r.maxShifts != null) '上 ${r.minShifts ?? 0}～${r.maxShifts ?? '不限'} 天',
      if (r.maxConsecutive != null) '最多連上 ${r.maxConsecutive} 天',
      if (r.noWeekdays.isNotEmpty) '不排${(r.noWeekdays.toList()..sort()).map(_wdName).join('、')}',
      if (r.marks.isNotEmpty) '排 ${r.marks.join('、')}',
      if (r.note != null && r.note!.isNotEmpty) r.note!,
    ].join('・');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('排班條件')),
      body: _error != null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : _setup == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
                  SectionCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('每天需要幾個人', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('「正職至少」＝這天至少要有幾個正職', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 6),
                      for (var w = 1; w <= 7; w++)
                        Row(children: [
                          SizedBox(width: 44, child: Text(_wdName(w))),
                          Expanded(
                            child: _Stepper(
                                value: _staff[w]!.need,
                                min: 0,
                                max: 50,
                                suffix: '人',
                                onChanged: (x) => setState(() {
                                      _staff[w] = StaffingNeed(x, _staff[w]!.minFull.clamp(0, x));
                                      _staffDirty = true;
                                    })),
                          ),
                          Expanded(
                            child: _Stepper(
                                value: _staff[w]!.minFull,
                                min: 0,
                                max: _staff[w]!.need,
                                prefix: '正職至少 ',
                                onChanged: (x) => setState(() {
                                      _staff[w] = StaffingNeed(_staff[w]!.need, x);
                                      _staffDirty = true;
                                    })),
                          ),
                        ]),
                      if (_staffDirty)
                        Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _saveStaff, child: const Text('儲存'))),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  SectionCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${widget.month.month} 月特別日子（要多一點或少一點人）', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      if (_setup!.specialDays.isEmpty) Text('沒有', style: TextStyle(color: AppColors.muted)),
                      for (final e in (_setup!.specialDays.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                        Row(children: [
                          Expanded(
                            child: Text(
                                '${widget.month.month}/${e.key}（${_wdNames[DateTime(widget.month.year, widget.month.month, e.key).weekday - 1]}）要 ${e.value} 人'),
                          ),
                          IconButton(
                            tooltip: '取消',
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              try {
                                await _repo.setShiftStaffingDay(_store, DateTime(widget.month.year, widget.month.month, e.key), null);
                                _load();
                              } catch (err) {
                                if (mounted) showMessage(context, friendlyError(err), error: true);
                              }
                            },
                          ),
                        ]),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(onPressed: _addSpecial, icon: const Icon(Icons.add), label: const Text('加一天')),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  SectionCard(
                    child: InkWell(
                      onTap: _editDeadline,
                      child: Row(children: [
                        const Expanded(child: Text('員工填寫截止日', style: TextStyle(fontWeight: FontWeight.w700))),
                        Text('每月 ${_setup!.deadline} 號前填好下個月'),
                        const Icon(Icons.chevron_right),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _pairRulesCard(),
                  const SizedBox(height: 10),
                  SectionCard(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('每個人的條件', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('沒設的照預設：正職照該月「應休」天數排休，最多連上 6 天',
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      for (final p in widget.people.where((x) => x.active))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${p.name}（${p.isFull ? '正職' : '兼職'}）'),
                          subtitle: Text(_ruleSummary(p), style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _editRule(p),
                        ),
                    ]),
                  ),
                ]),
    );
  }
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged, this.prefix = '', this.suffix = ''});
  final int value, min, max;
  final ValueChanged<int> onChanged;
  final String prefix, suffix;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline)),
        Text('$prefix$value$suffix', style: const TextStyle(fontSize: 13)),
        IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline)),
      ]);
}

/// 一個人的排班條件
class _RuleEditor extends StatefulWidget {
  const _RuleEditor(
      {required this.person, required this.rule, required this.storeName, required this.storeId, required this.repo, this.options});
  final ShiftOptions? options;
  final ShiftPerson person;
  final ShiftRule rule;
  final String storeName;
  final String storeId;
  final Repository repo;
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final _off = TextEditingController(text: widget.rule.monthOff == null ? '' : _n(widget.rule.monthOff!));
  late final _min = TextEditingController(text: widget.rule.minShifts?.toString() ?? '');
  late final _max = TextEditingController(text: widget.rule.maxShifts?.toString() ?? '');
  late final _consec = TextEditingController(text: widget.rule.maxConsecutive?.toString() ?? '');
  late final _note = TextEditingController(text: widget.rule.note ?? '');
  late final Set<int> _noWd = {...widget.rule.noWeekdays};
  late final List<String> _marks = [...widget.rule.marks];
  late bool _asPart = widget.rule.planAsPart;
  bool _busy = false;

  List<String> get _choices {
    final work = _storeMarks(widget.storeName, widget.options).where((m) => !ShiftMonth.isAway(m)).toList();
    final ranges = storeRanges(widget.storeName, widget.options);
    return [
      ...work,
      ...ranges,
      for (final m in _marks) if (!work.contains(m) && !ranges.contains(m)) m,
    ];
  }

  Future<void> _save() async {
    int? i(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    final r = ShiftRule(
      personId: widget.person.id,
      monthOff: widget.person.isFull && _off.text.trim().isNotEmpty ? double.tryParse(_off.text.trim()) : null,
      planAsPart: widget.person.isFull && _asPart,
      minShifts: i(_min),
      maxShifts: i(_max),
      maxConsecutive: i(_consec),
      noWeekdays: _noWd,
      marks: _marks,
      note: _note.text.trim(),
    );
    if (r.minShifts != null && r.maxShifts != null && r.minShifts! > r.maxShifts!) {
      showMessage(context, '最少天數不能比最多天數多', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repo.saveShiftRule(widget.storeId, r);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    const numKb = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(title: Text('${p.name} 的排班條件')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        if (p.isFull)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('排班時當兼職'),
            subtitle: const Text('班表上還是正職；自動排班不照應休，照最少／最多天數和填的「可以上」排，沒上班的日子留空白',
                style: TextStyle(fontSize: 12)),
            value: _asPart,
            onChanged: (v) => setState(() => _asPart = v),
          ),
        if (p.isFull && !_asPart)
          TextField(
              controller: _off,
              keyboardType: numKb,
              decoration: const InputDecoration(labelText: '每月休幾天', helperText: '那個月班表下方有填「應休」就用應休')),
        Row(children: [
          Expanded(child: TextField(controller: _min, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '每月最少上幾天'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '每月最多上幾天'))),
        ]),
        TextField(
            controller: _consec,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '最多連上幾天', helperText: '沒填＝6 天')),
        const SizedBox(height: 16),
        const Text('固定不排', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var w = 1; w <= 7; w++)
            FilterChip(
              label: Text(_wdName(w)),
              selected: _noWd.contains(w),
              onSelected: (v) => setState(() => v ? _noWd.add(w) : _noWd.remove(w)),
            ),
        ]),
        const SizedBox(height: 16),
        Text('上班排哪些班別／時段（照點的順序，第一個優先）',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('沒選＝${_defaultMarks(widget.storeName, p.isFull && !_asPart, widget.options).join('、')}（有上個月的班就照上個月最常排的）',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in _choices)
            FilterChip(
              label: Text(_marks.contains(m) ? '${_marks.indexOf(m) + 1}. $m' : m),
              selected: _marks.contains(m),
              onSelected: (v) => setState(() {
                if (v) {
                  if (_marks.length < 6) _marks.add(m);
                } else {
                  _marks.remove(m);
                }
              }),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLength: 200, decoration: const InputDecoration(labelText: '備註（自己看的，例如：只能上晚班）')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('儲存'),
        ),
      ]),
    );
  }
}

// =====================================================================
// 自動排班草稿
// =====================================================================
class ShiftAutoPlanScreen extends StatefulWidget {
  const ShiftAutoPlanScreen({super.key, required this.membership, required this.month, required this.markBg});
  final Membership membership;
  final DateTime month;
  final MarkBg markBg;
  @override
  State<ShiftAutoPlanScreen> createState() => _ShiftAutoPlanScreenState();
}

class _ShiftAutoPlanScreenState extends State<ShiftAutoPlanScreen> {
  ShiftMonth? _cur;
  ShiftMonth? _prev;
  ShiftPlanSetup? _setup;
  Object? _error;
  bool _keep = false;
  int _seed = 0;
  PlanResult? _plan;
  Map<String, Map<int, String>> _entries = {};
  final List<String> _notes = []; // 預設值說明
  bool _busy = false;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  String get _storeName => widget.membership.storeName;
  DateTime get _m => widget.month;
  int get _days => DateTime(_m.year, _m.month + 1, 0).day;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cur == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([
        _repo.shiftMonth(_store, _m),
        _repo.shiftMonth(_store, DateTime(_m.year, _m.month - 1)),
        _repo.shiftPlanSetup(_store, _m),
      ]);
      _cur = r[0] as ShiftMonth;
      _prev = r[1] as ShiftMonth;
      _setup = r[2] as ShiftPlanSetup;
      _keep = _cur!.marks.values.any((m) => m.isNotEmpty);
      _run();
    } catch (e) {
      setState(() => _error = e);
    }
  }

  List<ShiftPerson> get _people {
    final ps = _cur!.people.where((p) => p.active).toList();
    return [...ps.where((p) => p.isFull), ...ps.where((p) => !p.isFull)];
  }

  /// 上個月（與這個月已排的）最常排的上班記號
  List<String> _usualMarks(ShiftPerson p) {
    final c = <String, int>{};
    for (final sm in [_prev, _cur]) {
      for (final m in (sm?.marks[p.id] ?? const <int, String>{}).values) {
        if (_isWork(m)) c[m] = (c[m] ?? 0) + 1;
      }
    }
    final ms = c.keys.toList()..sort((a, b) => c[b]!.compareTo(c[a]!));
    return ms.take(3).toList();
  }

  void _run() {
    final s = _setup!;
    _notes.clear();
    final defaultOff = (_days * 9 / 31).roundToDouble();
    final noOff = <String>[];
    final people = [
      for (final p in _people)
        () {
          final r = s.rules[p.id];
          final should = _cur!.stats[p.id]?.shouldOff;
          final off = should ?? r?.monthOff;
          final full = _planFull(p, s);
          if (full && off == null) noOff.add(p.name);
          final usual = _usualMarks(p);
          return PlanPerson(
            id: p.id,
            name: p.name,
            full: full,
            offTarget: off ?? defaultOff,
            minShifts: r?.minShifts,
            maxShifts: r?.maxShifts,
            maxConsecutive: r?.maxConsecutive ?? 6,
            noWeekdays: r?.noWeekdays ?? const {},
            marks: (r?.marks.isNotEmpty ?? false) ? r!.marks : (usual.isNotEmpty ? usual : _defaultMarks(_storeName, full, _cur!.options)),
          );
        }(),
    ];
    if (noOff.isNotEmpty) _notes.add('${noOff.join('、')} 沒填應休，先用 ${_n(defaultOff)} 天（可在班表下方統計或排班條件填）');
    if (s.staffing.isEmpty) _notes.add('還沒設每天要幾人，先用 3 人（可在排班條件改）');
    final need = <int, int>{}, minFull = <int, int>{};
    for (var d = 1; d <= _days; d++) {
      final st = s.staffing[DateTime(_m.year, _m.month, d).weekday];
      need[d] = s.specialDays[d] ?? st?.need ?? 3;
      minFull[d] = (st?.minFull ?? 0).clamp(0, need[d]!);
    }
    final fixed = _keep
        ? {for (final p in _people) p.id: Map<int, String>.from(_cur!.marks[p.id] ?? const {})}
        : <String, Map<int, String>>{};
    final res = planShifts(
        year: _m.year,
        month: _m.month,
        people: people,
        needByDay: need,
        minFullByDay: minFull,
        fixed: fixed,
        requests: s.requests,
        pairRules: s.pairRules,
        seed: _seed);
    setState(() {
      _plan = res;
      _entries = {for (final e in res.entries.entries) e.key: Map<int, String>.from(e.value)};
    });
  }

  int _staffed(int d) => _people.where((p) => _isWork(_entries[p.id]?[d])).length;

  int get _changed {
    var n = 0;
    for (final p in _people) {
      for (var d = 1; d <= _days; d++) {
        if (_entries[p.id]?[d] != _cur!.mark(p.id, d)) n++;
      }
    }
    return n;
  }

  Future<void> _editCell(ShiftPerson p, int d) async {
    final cur = _entries[p.id]?[d];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${p.name}・${DateFormat('M/d（E）', 'zh_TW').format(DateTime(_m.year, _m.month, d))}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (_setup!.requests[p.id]?[d] != null)
              Text(_setup!.requests[p.id]![d] == 'off' ? '這天${_planFull(p, _setup) ? '指休' : '不能上'}' : '這天${_planFull(p, _setup) ? '想上班' : '可以上'}',
                  style: TextStyle(color: AppColors.warn, fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final m in {
                ..._storeMarks(_storeName, _cur!.options),
                ...storeRanges(_storeName, _cur!.options),
                ..._usualMarks(p)
              })
                ChoiceChip(
                  label: Text(m),
                  selected: m == cur,
                  selectedColor: widget.markBg(m) ?? AppColors.cardHigh,
                  onSelected: (_) => Navigator.pop(c, m),
                ),
              ActionChip(label: const Text('清除'), onPressed: () => Navigator.pop(c, '')),
            ]),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      final m = _entries.putIfAbsent(p.id, () => {});
      if (picked.isEmpty) {
        m.remove(d);
      } else {
        m[d] = picked;
      }
    });
  }

  Future<void> _apply() async {
    final hasData = _cur!.marks.values.any((m) => m.isNotEmpty);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('套用到 ${_m.month} 月班表？'),
        content: Text([
          if (hasData) '${_m.month} 月目前的班會換成這份草稿（$_changed 格不同）。' else '會把這份草稿排進 ${_m.month} 月班表。',
          '只會改班表上顯示中的人；備註、統計數字不動。',
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
      final n = await _repo.applyShiftPlan(_store, _m, {for (final p in _people) p.id: _entries[p.id] ?? {}});
      if (mounted) {
        showMessage(context, '已排好 ${_m.month} 月班表（$n 格）');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  Widget _cell(String? text,
          {Color? bg, bool changed = false, bool header = false, double w = 40, Color? dot, VoidCallback? onTap, Color? color}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: w,
          height: header ? 36 : 34,
          margin: const EdgeInsets.all(1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: changed ? Border.all(color: AppColors.primary, width: 2) : (bg == null && !header ? Border.all(color: AppColors.cardHigh) : null),
          ),
          child: Stack(children: [
            Center(
              child: Text(text ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: header ? 11 : (text != null && text.length > 4 ? 9 : 12), height: 1.1, color: color)),
            ),
            if (dot != null)
              Positioned(
                  right: 2, top: 2, child: Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('自動排 ${_m.month} 月班表')),
      body: _error != null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : _plan == null
              ? const Center(child: CircularProgressIndicator())
              : _body(),
    );
  }

  Widget _body() {
    final wd = DateFormat('E', 'zh_TW');
    final people = _people;
    final req = _setup!.requests;
    final short = [for (var d = 1; d <= _days; d++) if (_staffed(d) < (_plan!.need[d] ?? 0)) d];
    final warnings = _plan!.warnings;
    Widget row(ShiftPerson p) => Row(children: [
          _cell(_planFull(p, _setup) ? p.name : '${p.name}\n${p.isFull ? '當兼職' : '兼職'}', w: 64),
          for (var d = 1; d <= _days; d++)
            _cell(
              (_entries[p.id]?[d])?.replaceFirst('-', '\n'),
              bg: widget.markBg(_entries[p.id]?[d]),
              changed: _keep && _entries[p.id]?[d] != _cur!.mark(p.id, d),
              dot: req[p.id]?[d] == 'off' ? const Color(0xFFE0A34A) : (req[p.id]?[d] == 'on' ? AppColors.good : null),
              onTap: () => _editCell(p, d),
            ),
          _cell('${(_entries[p.id] ?? const <int, String>{}).values.where(_isWork).length}', w: 34),
        ]);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
      Text(
          '照每天要幾人、每個人的條件、大家填的指休／可以上排出來的草稿，還沒寫進班表。'
          '點格子可以改；小圓點＝有填（橘：指休／不能上，綠：可以上／想上班）。',
          style: TextStyle(color: AppColors.muted, fontSize: 12)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('保留已經排好的格子'),
        subtitle: Text(_keep ? '只補空白的格子（框起來＝跟目前班表不同）' : '整個月重新排', style: const TextStyle(fontSize: 12)),
        value: _keep,
        onChanged: (v) {
          _keep = v;
          _run();
        },
      ),
      if (_notes.isNotEmpty || warnings.isNotEmpty || short.isNotEmpty)
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(short.isEmpty && warnings.isEmpty ? '說明' : '要注意的地方', style: TextStyle(color: AppColors.warn, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final w in [..._notes, ...warnings])
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('・$w', style: const TextStyle(fontSize: 13))),
          ]),
        ),
      const SizedBox(height: 10),
      SectionCard(
        padding: const EdgeInsets.all(6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _cell('', w: 64, header: true),
              for (var d = 1; d <= _days; d++)
                _cell('$d\n${wd.format(DateTime(_m.year, _m.month, d))}',
                    header: true, bg: _setup!.specialDays.containsKey(d) ? AppColors.primary.withValues(alpha: 0.15) : null),
              _cell('天數', w: 34, header: true),
            ]),
            for (final p in people.where((p) => p.isFull)) row(p),
            if (people.any((p) => !p.isFull)) const SizedBox(height: 6),
            for (final p in people.where((p) => !p.isFull)) row(p),
            const SizedBox(height: 4),
            Row(children: [
              _cell('人力／要', w: 64),
              for (var d = 1; d <= _days; d++)
                _cell('${_staffed(d)}/${_plan!.need[d]}',
                    color: _staffed(d) < (_plan!.need[d] ?? 0) ? AppColors.bad : AppColors.primary,
                    bg: _staffed(d) < (_plan!.need[d] ?? 0) ? AppColors.bad.withValues(alpha: 0.15) : null),
              _cell('', w: 34),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () {
                    _seed++;
                    _run();
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('再排一次'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _busy ? null : _apply,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('套用到 ${_m.month} 月班表'),
          ),
        ),
      ]),
    ]);
  }
}

// =====================================================================
// 班別／時段清單（0075，老闆 2026-10-28：兩家店都可以新增、刪除）
// =====================================================================
class ShiftMarkOptionsScreen extends StatefulWidget {
  const ShiftMarkOptionsScreen({super.key, required this.membership, required this.markBg});
  final Membership membership;
  final MarkBg markBg;
  @override
  State<ShiftMarkOptionsScreen> createState() => _ShiftMarkOptionsScreenState();
}

class _ShiftMarkOptionsScreenState extends State<ShiftMarkOptionsScreen> {
  ShiftOptions? _o;
  Object? _error;
  bool _started = false;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  String get _storeName => widget.membership.storeName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final sm = await _repo.shiftMonth(_store, DateTime.now());
      setState(() {
        _o = sm.options;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  static final _rangeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d-([01]\d|2[0-3]):[0-5]\d$');
  static final _codeRe = RegExp(r'^[A-Z][A-Z0-9]{0,3}[+-]?$');
  String _norm(String v) =>
      v.trim().replaceAll('：', ':').replaceAll(RegExp(r'\s'), '').replaceAll(RegExp('[~～－—–]'), '-');

  Future<void> _edit({required bool code, ShiftMarkOption? cur}) async {
    final m = TextEditingController(text: cur?.mark ?? '');
    final t = TextEditingController(text: cur?.timeRange ?? '');
    String? errM, errT;
    final saved = await showDialog<ShiftMarkOption>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(cur == null ? (code ? '新增班別' : '新增時段') : (code ? '修改班別' : '修改時段')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (code)
              TextField(
                controller: m,
                autofocus: cur == null,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: '班別代碼', hintText: '例：B、BH、RBK', errorText: errM),
              ),
            TextField(
              controller: code ? t : m,
              autofocus: !code && cur == null,
              decoration: InputDecoration(labelText: '時段', hintText: '例：18:00-00:30（過午夜照寫）', errorText: errT),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final mk = code ? m.text.trim().toUpperCase() : _norm(m.text);
                final tr = code ? _norm(t.text) : null;
                errM = null;
                errT = null;
                if (code && (!_codeRe.hasMatch(mk) || mk == 'V' || mk == 'O')) errM = '大寫英文開頭、最多 4 碼（可加 + 或 -），不能用 V、O';
                if (code ? !_rangeRe.hasMatch(tr!) : !_rangeRe.hasMatch(mk)) errT = '格式：開始-結束，例 18:00-00:30';
                if (errM != null || errT != null) {
                  set(() {});
                  return;
                }
                Navigator.pop(
                    c,
                    ShiftMarkOption(
                        id: cur?.id ?? '',
                        kind: code ? 'code' : 'range',
                        mark: mk,
                        timeRange: tr,
                        sortOrder: cur?.sortOrder ?? ((_o?.items.length ?? 0) + 1) * 10));
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    try {
      await _repo.saveShiftMarkOption(_store, saved);
      _load();
    } catch (e) {
      if (mounted) {
        final msg = friendlyError(e);
        showMessage(context, msg.contains('duplicate') || msg.contains('23505') ? '已經有一樣的了' : msg, error: true);
      }
    }
  }

  Future<void> _delete(ShiftMarkOption x) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('刪掉「${x.mark}」？'),
        content: const Text('只是選單不再出現；已經排進班表的格子不會變。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteShiftMarkOption(x.id);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Widget _section(String title, String hint, List<ShiftMarkOption> items, {required bool code}) => SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(hint, style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          if (items.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('還沒有', style: TextStyle(color: AppColors.muted))),
          for (final x in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                constraints: const BoxConstraints(minWidth: 48),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(color: widget.markBg(x.mark), borderRadius: BorderRadius.circular(6)),
                child: Text(code ? x.mark : '時段', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              title: Text(code ? (x.timeRange ?? '').replaceFirst('-', '～') : x.mark.replaceFirst('-', '～')),
              subtitle: Text('${_num(ShiftMonth.hoursOf(code ? x.timeRange : x.mark, const {}))} 小時', style: const TextStyle(fontSize: 12)),
              onTap: () => _edit(code: code, cur: x),
              trailing: IconButton(tooltip: '刪除', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(x)),
            ),
          TextButton.icon(onPressed: () => _edit(code: code), icon: const Icon(Icons.add), label: Text(code ? '新增班別' : '新增時段')),
        ]),
      );

  String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return Scaffold(
      appBar: AppBar(title: const Text('班別／時段')),
      body: _error != null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : o == null
              ? const Center(child: CircularProgressIndicator())
              : !o.loaded
                  ? ErrorView(message: '讀不到班別／時段清單，請稍後再試', onRetry: _load)
                  : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
                      Text('$_storeName 的清單，只影響這家店。點一項可以修改，刪掉不會改到已經排好的班。',
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 10),
                      _section('班別', '點格子排班時可以選的班別代碼（例 B＝17:00-00:30）${_storeName == '小城外' ? '；時數照時段算' : ''}', o.codes,
                          code: true),
                      const SizedBox(height: 10),
                      _section('兼職時段', '兼職排班時可以選的時段', [for (final x in o.items) if (!x.isCode) x], code: false),
                    ]),
    );
  }
}
