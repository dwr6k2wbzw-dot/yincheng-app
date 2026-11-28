import 'package:flutter/material.dart';
import '../data/store_features.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/schedule_health.dart';
import '../data/shift_off_rules.dart';
import '../data/shift_marks.dart';
import '../data/shift_templates.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shift_assistant_screen.dart';

import 'shift_template_picker.dart';

part 'shift_auto_plan_screen.dart';

/// 自動排班（老闆 2026-10-27，0073）
///   * 填想休／可以上：所有成員（含兼職），只能改自己的、下個月、截止日以前；老闆店長隨時可改任何人
///   * 排班條件：老闆、店長
///   * 自動排班：老闆、店長；App 端算 → 草稿預覽（可點格子改）→ 套用

typedef MarkBg = Color? Function(String?);

const _wdNames = ['一', '二', '三', '四', '五', '六', '日'];
String _wdName(int w) => '週${_wdNames[w - 1]}';
final _md = DateFormat('M/d', 'zh_TW');

List<String> _storeMarks(String storeName, ShiftOptions? o) =>
    storeMarks(storeName, o);
bool _isWork(String? m) => ShiftMonth.isOn(m);

/// 排班時算正職嗎（排班條件設「排班時當兼職」的正職，排班時跟兼職一樣；0074）
bool _planFull(ShiftPerson p, ShiftPlanSetup? s) =>
    p.isFull && !(s?.rules[p.id]?.planAsPart ?? false);

/// 這家店沒設排班條件時，上班用的記號
/// 班別清單讀得到、但班別（或時段）全部停用了 → 回空的，自動排班會先擋下來請店長處理，
/// 不會偷偷排回已經停用的 B／BH（Codex P2）
List<String> _defaultMarks(String storeName, bool full, ShiftOptions? o) {
  if (!StoreFeatures.of(storeName).shiftCodes) return const ['V'];
  if (o == null) return const [];
  if (full) return [for (final c in o.codes.take(2)) c.mark];
  return o.ranges.isNotEmpty ? [o.ranges.first] : const [];
}

// =====================================================================
// 班表頁上的「排班」卡片
// =====================================================================
class ShiftPlanCard extends StatelessWidget {
  const ShiftPlanCard(
      {super.key,
      required this.membership,
      required this.data,
      required this.viewMonth,
      required this.scheduled,
      required this.markBg,
      required this.onChanged});
  final Membership membership;
  final ShiftMonth data; // 目前看的月份（用它的人員名單）
  final DateTime viewMonth;
  /// 這個月排好了沒（班表頁用 isMonthScheduled 算：上班人次到當月需要的八成；2026-11-16 健檢）
  final bool scheduled;
  final MarkBg markBg;
  final VoidCallback onChanged;

  /// LINE 群組提醒填指休（0098）：LINE 發到群組照群組人數算則數，所以按了才發
  Future<void> _remind(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('提醒大家填 ${viewMonth.month} 月指休？'),
        content: const Text(
            '會發一則訊息到這家店的 LINE 工作群組，請大家跟店長說想休哪幾天、哪幾天可以上。\n\nLINE 是照群組人數算則數（群組 14 人＝一則算 14 則，每月免費 200 則），同一個月份最多發 2 次。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('發送')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await AppScope.of(context)
          .repo
          .remindShiftRequests(membership.storeId, viewMonth);
      if (context.mounted) showMessage(context, '已經發到 LINE 群組');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1);
    final manager = membership.isManager;
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap) =>
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(sub,
                          style: TextStyle(
                              color: AppColors.muted, fontSize: AppType.small)),
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
    //   * 這個月已經排好班 → 整張卡片不顯示，老闆店長也一樣（老闆 2026-11-13：排好了就不要再出現）。
    //     「排好了」＝上班人次到需要的八成（老闆 2026-11-16；原本「有任何一格」，先點一天特休卡片就不見）。
    //     排好後：排班條件、重新自動排改放在班表頁下方的按鈕
    //   * 「填指休」只在下個月以後才有（員工只能填下個月以後）；「自動排班」不排已經過去的月份
    final thisMonth = DateTime(now.year, now.month);
    final showRequest = !scheduled && !viewMonth.isBefore(next);
    final showAuto = manager && !scheduled && !viewMonth.isBefore(thisMonth);
    final tiles = <Widget>[
      if (showRequest)
        tile(
            Icons.event_busy_outlined,
            '填 ${viewMonth.month} 月指休／可以上的日子',
            '正職點指休、兼職點可以上，排班會照著排',
            () => go(
                ShiftRequestScreen(membership: membership, month: viewMonth))),
      if (showAuto)
        tile(
            Icons.auto_awesome_outlined,
            '自動排 ${viewMonth.month} 月班表',
            '先出草稿，可以存起來慢慢調；公布後員工才看得到',
            () => go(ShiftAutoPlanScreen(
                membership: membership, month: viewMonth, markBg: markBg))),
      if (manager && showRequest)
        tile(Icons.campaign_outlined, '在 LINE 群組提醒大家填指休',
            '發一則到工作群組（一個月份最多 2 次）', () => _remind(context)),
      if (showAuto)
        tile(
            Icons.tune,
            '排班條件',
            '每天要幾人、每個人的條件、填寫截止日',
            () => go(ShiftRulesScreen(
                membership: membership,
                month: viewMonth,
                people: data.people,
                options: data.options))),
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
  const ShiftRequestScreen(
      {super.key, required this.membership, required this.month});
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
  Map<int, Set<String>>? _takenDb; // ops 0137：哪幾天已經有正職指休（null＝資料庫還沒更新）
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
      final r = await Future.wait<dynamic>([
        _repo.shiftMonth(_store, _month),
        _repo.shiftPlanSetup(_store, _month),
        _repo.shiftOffTaken(_store, _month),
      ]);
      final sm = r[0] as ShiftMonth;
      final me = sm.people
          .where((p) =>
              p.active && p.userId != null && p.userId == _repo.currentUserId)
          .firstOrNull;
      setState(() {
        _sm = sm;
        _setup = r[1] as ShiftPlanSetup;
        _takenDb = r[2] as Map<int, Set<String>>?;
        _personId ??= me?.id ??
            (_manager
                // 預選照班表排序的第一位（名單顯示改成正職在前，預選不跟著變；2026-11-28）
                ? (sm.people.where((p) => p.active).toList()
                      ..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.name.compareTo(b.name)))
                    .firstOrNull
                    ?.id
                : null);
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

  ShiftPerson? get _me => _sm?.people
      .where((p) =>
          p.active && p.userId != null && p.userId == _repo.currentUserId)
      .firstOrNull;
  ShiftPerson? get _person =>
      _sm?.people.where((p) => p.id == _personId).firstOrNull;

  DateTime get _deadline =>
      ShiftPlanSetup.deadlineFor(_month, _setup?.deadline ?? 20);
  bool get _open {
    if (_manager) return true;
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    return !d.isAfter(_deadline) &&
        !DateTime(_month.year, _month.month)
            .isBefore(DateTime(today.year, today.month + 1));
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
    // 老闆、店長替正職填時多一個「特休」（ops 0138；員工不能自己劃特休）
    final order = _planFull(p, _setup)
        ? (_manager ? [null, 'off', 'special', 'on'] : [null, 'off', 'on'])
        : p.isFull && _manager
            ? [null, 'on', 'off', 'special']
            : [null, 'on', 'off'];
    final next = order[(order.indexOf(cur) + 1) % order.length];
    // ops 0137／0150：同一天最多幾位正職指休、每月最多幾天（每家店自己設）；員工直接擋，老闆店長提醒後可以超過
    if (next == 'off' && _planFull(p, _setup)) {
      final perDay = _setup!.offPerDay, monthMax = _setup!.offMonthMax;
      final c = offCheck(
          takenDays: _taken,
          mine: _setup!.requests[p.id] ?? const {},
          personId: p.id,
          day: day,
          perDay: perDay,
          monthMax: monthMax);
      if (c.dayFull || c.overLimit) {
        if (!_manager) {
          showMessage(context, offBlockedText(dayFull: c.dayFull, perDay: perDay, monthMax: monthMax), error: true);
          return;
        }
        final names = c.taken.map((id) => _sm?.people.where((x) => x.id == id).firstOrNull?.label ?? '').where((n) => n.isNotEmpty).join('、');
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('還是要替${p.label}填 ${_month.month}/$day 指休？'),
            content: Text([
              if (c.dayFull) '這天${names.isEmpty ? '已經有正職' : names}指休了${perDay != null && perDay > 1 ? '（最多 $perDay 位）' : ''}。',
              if (c.overLimit) '${p.label}這個月已經指休 $monthMax 天。',
              '員工自己填會被擋下來，老闆、店長協調好可以超過。',
            ].join('\n')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('還是要填')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
    }
    setState(() {
      final m = _setup!.requests.putIfAbsent(p.id, () => {});
      if (next == null) {
        m.remove(day);
      } else {
        m[day] = next;
      }
      if (_takenDb != null && _planFull(p, _setup)) {
        final t = _takenDb!.putIfAbsent(day, () => {});
        next == 'off' ? t.add(p.id) : t.remove(p.id);
      }
    });
    try {
      await _repo.setShiftRequest(
          _store, p.id, DateTime(_month.year, _month.month, day), next);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      _load();
    }
  }

  Map<int, Set<String>> get _taken =>
      offTakenDays(fromDb: _takenDb, people: _sm?.people ?? const [], setup: _setup ?? const ShiftPlanSetup());

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
      // 0125：不用自己選名字了，帳號由老闆或店長對應
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('你的帳號還沒對應到員工資料',
            style: TextStyle(
                fontSize: AppType.title, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('請店長或老闆在「班表人員」替你對應一次，之後登入就能直接填想休、可以上班的日子。',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      ]);
    }
    final p = _person;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWd = DateTime(_month.year, _month.month, 1).weekday % 7; // 週日＝0
    final req = _setup!.requests;
    final mine = p == null ? const <int, String>{} : (req[p.id] ?? const {});
    int othersOff(int d) =>
        req.entries.where((e) => e.key != p?.id && e.value[d] == 'off').length;
    final offCount = mine.values.where((v) => v == 'off').length;
    final onCount = mine.values.where((v) => v == 'on').length;
    final specialCount = mine.values.where((v) => v == 'special').length;

    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(children: [
            IconButton(
                tooltip: '上個月',
                onPressed: () {
                  _month = DateTime(_month.year, _month.month - 1);
                  _load();
                },
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(DateFormat('yyyy 年 M 月', 'zh_TW').format(_month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: AppType.title)),
            ),
            IconButton(
                tooltip: '下個月',
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
                decoration:
                    const InputDecoration(labelText: '填誰的（老闆、店長可以替大家填）'),
                items: [
                  for (final x in active)
                    DropdownMenuItem(
                        value: x.id,
                        child: Text(
                            '${x.label}（${x.isFull ? '正職' : '兼職'}）${x.id == _me?.id ? '・我' : ''}')),
                ],
                onChanged: (v) => setState(() => _personId = v),
              ),
            ),
          SectionCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p == null ? '' : '${p.label}・${p.isFull ? '正職' : '兼職'}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                _open
                    ? '${_md.format(_deadline)} 前可以改${_manager ? '（老闆、店長隨時可改）' : ''}'
                    : '已經過了填寫截止日（${_md.format(_deadline)}），要改請找老闆或店長',
                style: TextStyle(
                    color: _open ? AppColors.muted : AppColors.warn,
                    fontSize: AppType.small),
              ),
              const SizedBox(height: 4),
              Text(
                p == null
                    ? ''
                    : _planFull(p, _setup)
                        ? '${_manager ? '點一下＝指休，再點＝特休，再點＝想上班，再點＝取消' : '點一下＝指休，再點＝想上班，再點＝取消'}。目前指休 $offCount 天${onCount > 0 ? '、想上班 $onCount 天' : ''}${specialCount > 0 ? '、特休 $specialCount 天' : ''}。特休由店長劃，不算在應休裡。\n${offRuleText(_setup!.offPerDay, _setup!.offMonthMax)}'
                        : '點一下＝可以上，再點＝不能上，再點＝取消。有填可以上，排班就只排那些天。目前可以上 $onCount 天${offCount > 0 ? '、不能上 $offCount 天' : ''}。',
                style: const TextStyle(fontSize: AppType.small),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (final w in ['日', '一', '二', '三', '四', '五', '六'])
              Expanded(
                  child: Text(w,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.muted, fontSize: AppType.small))),
          ]),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.82,
            children: [
              for (var i = 0; i < firstWd; i++) const SizedBox.shrink(),
              for (var d = 1; d <= days; d++)
                _dayCell(d, mine[d], othersOff(d), sm.notes[d],
                    taken: p != null && _planFull(p, _setup) && mine[d] != 'off' && ({...?_taken[d]}..remove(p.id)).isNotEmpty),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            _legend(const Color(0xFFE0A34A), '指休／不能上'),
            _legend(AppColors.good, '可以上／想上班'),
            if (_manager) _legend(const Color(0xFFC0392B), '特休（店長劃）'),
            Text('右上小數字＝其他人指休',
                style:
                    TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          ]),
        ]);
  }

  Widget _legend(Color c, String t) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(AppRadius.xs))),
        const SizedBox(width: 4),
        Text(t,
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      ]);

  Widget _dayCell(int d, String? kind, int others, String? note, {bool taken = false}) {
    final bg = kind == 'off'
        ? const Color(0xFFE0A34A).withValues(alpha: 0.85)
        : kind == 'special'
            ? const Color(0xFFC0392B).withValues(alpha: 0.75) // 跟班表的特休同一個紅色
        : kind == 'on'
            ? AppColors.good.withValues(alpha: 0.75)
            : null;
    return GestureDetector(
      onTap: () => _tap(d),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: bg == null ? Border.all(color: AppColors.cardHigh) : null,
        ),
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$d',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _open ? null : AppColors.muted)),
              Text(
                  kind == 'special'
                      ? '特休'
                      : kind == 'off'
                      ? (_person == null || _planFull(_person!, _setup)
                          ? '指休'
                          : '不能上')
                      : kind == 'on'
                          ? (_person == null || _planFull(_person!, _setup)
                              ? '想上'
                              : '可以上')
                          : taken
                              ? '已有人'
                              : (note ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppType.micro)),
            ]),
          ),
          if (others > 0)
            Positioned(
              right: 4,
              top: 2,
              child: Text('$others',
                  style: TextStyle(
                      fontSize: AppType.micro,
                      color: AppColors.warn,
                      fontWeight: FontWeight.w700)),
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
  const ShiftRulesScreen(
      {super.key,
      required this.membership,
      required this.month,
      required this.people,
      this.options});
  final Membership membership;
  final DateTime month;
  final List<ShiftPerson> people;
  final ShiftOptions? options;
  @override
  State<ShiftRulesScreen> createState() => _ShiftRulesScreenState();
}

class _ShiftRulesScreenState extends State<ShiftRulesScreen> {
  ShiftPlanSetup? _setup;
  // 班別／時段清單：一開始用班表頁傳進來的，套用業態範本之後重讀（Codex P2）
  late ShiftOptions? _options = widget.options;
  Map<int, StaffingNeed> _staff = {};
  final Set<int> _staffEdited = {}; // 還沒存的每日人力修改是哪幾天（星期）
  bool get _staffDirty => _staffEdited.isNotEmpty;
  Object? _error;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  String get _storeName => widget.membership.storeName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_setup == null && _error == null) _load();
  }

  /// keepEdits：保留這幾天還沒存的人力修改，其他天換成剛讀到的（從 AI 助理回來時用，Codex P2）
  Future<void> _load({bool keepEdits = false}) async {
    try {
      final s = await _repo.shiftPlanSetup(_store, widget.month);
      setState(() {
        _setup = s;
        if (!keepEdits) _staffEdited.clear();
        _staff = mergeStaffing(s.staffing, _staff, _staffEdited);
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _applyTemplate() async {
    var kind = defaultShiftTemplate;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('套用業態範本', style: TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading)),
              const SizedBox(height: 4),
              Text('帶入這類店常見的每天人數、班別和時段，套完可以再改。只能套一次。',
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              const SizedBox(height: 12),
              ShiftTemplatePicker(selected: kind, onChanged: (k) => set(() => kind = k)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('套用'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.applyShiftTemplate(_store, kind);
      await _refreshAfterTemplate();
      if (mounted) {
        showMessage(context, '已套用「${shiftTemplates.firstWhere((t) => t.kind == kind).label}」範本，班別／時段也一起帶入了');
      }
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  /// 套用範本會新增班別、打開班別代碼的開關：重讀班別清單和成員資格（成員資格會一起記下功能開關），
  /// 不然點人設排班條件時還是空的班別、預設記號也還是 V（Codex P2）。讀不到就留原本的，畫面照常。
  Future<void> _refreshAfterTemplate() async {
    try {
      await _repo.myMemberships();
    } catch (_) {}
    try {
      final m = await _repo.shiftMonth(_store, widget.month);
      if (mounted) setState(() => _options = m.options);
    } catch (_) {}
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
        context: context,
        initialDate: DateTime(m.year, m.month, 1),
        firstDate: DateTime(m.year, m.month, 1),
        lastDate: DateTime(m.year, m.month + 1, 0));
    if (d == null || !mounted) return;
    final n = await _askNumber('${_md.format(d)} 要幾個人',
        (_setup!.specialDays[d.day] ?? _staff[d.weekday]?.need ?? 3) + 1);
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
          content: _Stepper(
              value: v,
              min: 0,
              max: 50,
              onChanged: (x) => set(() => v = x),
              suffix: '人'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(c, v), child: const Text('確定')),
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
          content: _Stepper(
              value: v,
              min: 1,
              max: 28,
              onChanged: (x) => set(() => v = x),
              suffix: '號'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(c, v), child: const Text('儲存')),
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
        builder: (_) => _RuleEditor(
            person: p,
            rule: r0,
            storeName: _storeName,
            storeId: _store,
            repo: _repo,
            options: _options)));
    if (saved == true) _load();
  }

  String _pname(String id) =>
      widget.people.where((p) => p.id == id).firstOrNull?.name ?? '（已移除）';
  String _pairText(PairRule r) => r.isApart
      ? '${_pname(r.a)} 跟 ${_pname(r.b)} 不能同一天上班'
      : '${_pname(r.a)} 上班的日子，${_pname(r.b)} 也要上班';

  Widget _pairRulesCard() => SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('自訂規則', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('例如：誰跟誰不能同一天上班、新人要跟誰一起上。自動排班一定照著排；只有老闆、店長看得到。',
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          const SizedBox(height: 4),
          if (_setup!.pairRules.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('還沒有', style: TextStyle(color: AppColors.muted))),
          for (final r in _setup!.pairRules)
            Row(children: [
              Icon(r.isApart ? Icons.do_not_disturb_alt : Icons.group_outlined,
                  size: 18, color: r.isApart ? AppColors.warn : AppColors.good),
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
                    if (mounted)
                      showMessage(context, friendlyError(e), error: true);
                  }
                },
              ),
            ]),
          TextButton.icon(
              onPressed: _addPairRule,
              icon: const Icon(Icons.add),
              label: const Text('新增規則')),
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
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  decoration: InputDecoration(
                      labelText: kind == 'apart' ? '這個人' : '這個人上班的日子'),
                  items: [
                    for (final p in ps)
                      DropdownMenuItem(value: p.id, child: Text(p.label))
                  ],
                  onChanged: (v) => set(() {
                    a = v;
                    if (b == a) b = null;
                  }),
                ),
                DropdownButtonFormField<String>(
                  value: b,
                  decoration: InputDecoration(
                      labelText: kind == 'apart' ? '跟這個人不能同一天上班' : '這個人也要上班'),
                  items: [
                    for (final p in ps)
                      if (p.id != a)
                        DropdownMenuItem(value: p.id, child: Text(p.label))
                  ],
                  onChanged: (v) => set(() => b = v),
                ),
                const SizedBox(height: 8),
                Text(
                    kind == 'apart'
                        ? '例：Perry 跟 Eason 不能同一天上班'
                        : '例：新人上班的日子，老手也要上班（反過來不一定）',
                    style: TextStyle(
                        color: AppColors.muted, fontSize: AppType.small)),
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('新增')),
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
      if (mounted)
        showMessage(
            context,
            friendlyError(e).contains('duplicate') ||
                    friendlyError(e).contains('重複')
                ? '這條規則已經有了'
                : friendlyError(e),
            error: true);
    }
  }

  Future<void> _editPreferRun() async {
    var v = _setup!.preferRun ?? 5;
    final n = await showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('盡量不要連上超過幾天'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _Stepper(
                value: v,
                min: 1,
                max: 10,
                onChanged: (x) => set(() => v = x),
                suffix: '天'),
            const SizedBox(height: 8),
            Text('自動排班會盡量照這個排；真的排不開時，還是可以排到每個人的「最多連上幾天」（沒設＝6 天）。',
                style:
                    TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, 0), child: const Text('不設')),
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(c, v), child: const Text('儲存')),
          ],
        ),
      ),
    );
    if (n == null) return;
    try {
      await _repo.saveShiftPreferRun(_store, n == 0 ? null : n);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  /// 0150 員工指休規則：同一天最多幾位正職、每人每月最多幾天（每家店自己設；不限＝空白）
  Future<void> _editOffLimits() async {
    int? perDay = _setup!.offPerDay, monthMax = _setup!.offMonthMax;
    var dayVal = perDay ?? shiftOffPerDayDefault, monthVal = monthMax ?? shiftOffMonthMaxDefault;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          Widget row(String label, bool limited, ValueChanged<bool> onLimit, Widget stepper) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(limited ? '有上限' : '不限'),
                    value: limited,
                    onChanged: onLimit,
                  ),
                  if (limited) stepper,
                ],
              );
          return AlertDialog(
            title: const Text('員工指休規則'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                row('同一天最多幾位正職指休', perDay != null, (v) => set(() => perDay = v ? dayVal : null),
                    _Stepper(value: dayVal, min: 1, max: 20, onChanged: (x) => set(() => perDay = dayVal = x), suffix: ' 位')),
                const SizedBox(height: 4),
                row('每人每月最多指休幾天', monthMax != null, (v) => set(() => monthMax = v ? monthVal : null),
                    _Stepper(value: monthVal, min: 1, max: 31, onChanged: (x) => set(() => monthMax = monthVal = x), suffix: ' 天')),
                const SizedBox(height: 8),
                Text('先填先贏；員工超過會被擋，老闆、店長替人填可以超過。',
                    style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('儲存')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await _repo.saveShiftOffLimits(_store, perDay, monthMax);
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  /// 照過去兩個月的班表整理每個人的習慣（哪幾天不上、一個月幾天、各星期的班別），店長勾選確認後才存成排班條件
  Future<void> _importHabits() async {
    final m = widget.month;
    List<ShiftMonth> past;
    try {
      past = await Future.wait([
        for (final k in [2, 1])
          _repo.shiftMonth(_store, DateTime(m.year, m.month - k))
      ]);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    final rows = <(ShiftPerson, RuleSuggestion)>[];
    for (final p in widget.people.where((x) => x.active)) {
      final full = _planFull(p, _setup);
      final s = suggestRule([
        for (final sm in past)
          (sm.month, sm.marks[p.id] ?? const <int, String>{})
      ], full: full);
      if (s.worked == 0) continue;
      if (full ? s.weekdayMarks.isEmpty : (s.worked < 3)) continue;
      rows.add((p, s));
    }
    if (rows.isEmpty) {
      showMessage(context, '過去兩個月的班表資料不夠，整理不出習慣');
      return;
    }
    String desc(ShiftPerson p, RuleSuggestion s) => [
          if (s.noWeekdays.isNotEmpty)
            '只上${[
              for (var w = 1; w <= 7; w++)
                if (!s.noWeekdays.contains(w)) _wdNames[w - 1]
            ].join('、')}',
          if (s.minShifts != null)
            '一個月 ${s.minShifts == s.maxShifts ? s.minShifts : '${s.minShifts}～${s.maxShifts}'} 天',
          if (s.weekdayMarks.isNotEmpty)
            '班別：${(s.weekdayMarks.keys.toList()..sort()).map((w) => '${_wdNames[w - 1]} ${s.weekdayMarks[w]}').join('、')}',
        ].join('\n');
    final picked = {for (final r in rows) r.$1.id};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('照過去兩個月的班表帶入',
                        style: TextStyle(
                            fontSize: AppType.title,
                            fontWeight: FontWeight.w700)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                        '這只是過去的習慣，不代表那個人下個月真的可以。請看過、把不對的取消勾選；存了以後還可以一個一個改。'
                        '兼職沒上過的星期會設成「固定不排」，天數範圍會設成最少～最多。',
                        style: TextStyle(
                            color: AppColors.muted, fontSize: AppType.small)),
                  ),
                  Flexible(
                    child: ListView(shrinkWrap: true, children: [
                      for (final (p, s) in rows)
                        CheckboxListTile(
                          value: picked.contains(p.id),
                          onChanged: (v) => set(() => v == true
                              ? picked.add(p.id)
                              : picked.remove(p.id)),
                          title: Text(
                              '${p.label}（${p.isFull ? '正職' : '兼職'}・過去兩個月上 ${s.worked} 天）'),
                          subtitle: Text(desc(p, s),
                              style: const TextStyle(fontSize: AppType.small)),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                        onPressed: picked.isEmpty
                            ? null
                            : () => Navigator.pop(c, true),
                        child: Text('存成排班條件（${picked.length} 人）')),
                  ),
                ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      for (final (p, s) in rows) {
        if (!picked.contains(p.id)) continue;
        final old = _setup!.rules[p.id] ?? ShiftRule(personId: p.id);
        final full = _planFull(p, _setup);
        await _repo.saveShiftRule(
            _store,
            ShiftRule(
              personId: p.id,
              planAsPart: old.planAsPart,
              monthOff: old.monthOff,
              minShifts: full ? old.minShifts : s.minShifts,
              maxShifts: full ? old.maxShifts : s.maxShifts,
              maxConsecutive: old.maxConsecutive,
              noWeekdays: full ? old.noWeekdays : s.noWeekdays,
              marks: old.marks,
              weekdayMarks:
                  s.weekdayMarks.isEmpty ? old.weekdayMarks : s.weekdayMarks,
              note: old.note,
            ));
      }
      if (mounted) showMessage(context, '已經存成排班條件，可以再一個一個調整');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      _load();
    }
  }

  String _ruleSummary(ShiftPerson p) {
    final r = _setup!.rules[p.id];
    if (r == null || r.isEmpty) return '沒設（照預設排）';
    return [
      if (p.isFull && r.planAsPart) '排班時當兼職',
      if (p.isFull && !r.planAsPart && r.monthOff != null)
        '每月休 ${_n(r.monthOff!)} 天',
      if (r.minShifts != null || r.maxShifts != null)
        '上 ${r.minShifts ?? 0}～${r.maxShifts ?? '不限'} 天',
      if (r.maxConsecutive != null) '最多連上 ${r.maxConsecutive} 天',
      if (r.noWeekdays.isNotEmpty)
        '不排${(r.noWeekdays.toList()..sort()).map(_wdName).join('、')}',
      if (r.marks.isNotEmpty) '排 ${r.marks.join('、')}',
      if (r.weekdayMarks.isNotEmpty)
        '依星期：${(r.weekdayMarks.keys.toList()..sort()).map((w) => '${_wdNames[w - 1]} ${r.weekdayMarks[w]}').join('、')}',
      if (r.note != null && r.note!.isNotEmpty) r.note!,
    ].join('・');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('排班條件'), actions: [
        // ops 0154：用講的改排班設定，只在公版出現（隱城／小城外這一份畫面不變）
        if (shiftAssistantVisible && widget.membership.isManager)
          IconButton(
            tooltip: '用講的改排班設定（AI）',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ShiftAssistantScreen(membership: widget.membership)));
              // 回來後重新讀已存的設定；還沒存的每日人力只保留改過的那幾天（不然按儲存會把 AI 改的蓋回去）
              if (mounted) _load(keepEdits: true);
            },
          ),
      ]),
      body: _error != null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : _setup == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                      // ops 0152：全新的店（還沒有人力、也沒有班別）可以一鍵帶入業態範本；只有公版、只有老闆
                      if (showApplyTemplate(
                          isOwner: widget.membership.role == Role.owner,
                          staffingEmpty: _setup!.staffing.isEmpty,
                          optionsEmpty: _options?.items.isEmpty ?? true)) ...[
                        _ApplyTemplateCard(onTap: _applyTemplate),
                        const SizedBox(height: 10),
                      ],
                      SectionCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('每天需要幾個人',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              Text('「正職至少」＝這天至少要有幾個正職',
                                  style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: AppType.small)),
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
                                              _staff[w] = StaffingNeed(
                                                  x,
                                                  _staff[w]!
                                                      .minFull
                                                      .clamp(0, x));
                                              _staffEdited.add(w);
                                            })),
                                  ),
                                  Expanded(
                                    child: _Stepper(
                                        value: _staff[w]!.minFull,
                                        min: 0,
                                        max: _staff[w]!.need,
                                        prefix: '正職至少 ',
                                        onChanged: (x) => setState(() {
                                              _staff[w] = StaffingNeed(
                                                  _staff[w]!.need, x);
                                              _staffEdited.add(w);
                                            })),
                                  ),
                                ]),
                              if (_staffDirty)
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton(
                                        onPressed: _saveStaff,
                                        child: const Text('儲存'))),
                            ]),
                      ),
                      const SizedBox(height: 10),
                      SectionCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${widget.month.month} 月特別日子（要多一點或少一點人）',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              if (_setup!.specialDays.isEmpty)
                                Text('沒有',
                                    style: TextStyle(color: AppColors.muted)),
                              for (final e
                                  in (_setup!.specialDays.entries.toList()
                                    ..sort((a, b) => a.key.compareTo(b.key))))
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
                                        await _repo.setShiftStaffingDay(
                                            _store,
                                            DateTime(widget.month.year,
                                                widget.month.month, e.key),
                                            null);
                                        _load();
                                      } catch (err) {
                                        if (mounted)
                                          showMessage(
                                              context, friendlyError(err),
                                              error: true);
                                      }
                                    },
                                  ),
                                ]),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                    onPressed: _addSpecial,
                                    icon: const Icon(Icons.add),
                                    label: const Text('加一天')),
                              ),
                            ]),
                      ),
                      const SizedBox(height: 10),
                      SectionCard(
                        child: InkWell(
                          onTap: _editDeadline,
                          child: Row(children: [
                            const Expanded(
                                child: Text('員工填寫截止日',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700))),
                            Text('每月 ${_setup!.deadline} 號前填好下個月'),
                            const Icon(Icons.chevron_right),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SectionCard(
                        child: InkWell(
                          onTap: _editPreferRun,
                          child: Row(children: [
                            const Expanded(
                                child: Text('盡量不要連上超過',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700))),
                            Text(_setup!.preferRun == null
                                ? '沒設（只看每個人的最多連上）'
                                : '${_setup!.preferRun} 天'),
                            const Icon(Icons.chevron_right),
                          ]),
                        ),
                      ),
                      // ops 0150：指休規則的設定入口只在公版出現（隱城／小城外這一份畫面不變）
                      if (offLimitsSettingVisible) ...[
                        const SizedBox(height: 10),
                        SectionCard(
                          child: InkWell(
                            onTap: _editOffLimits,
                          child: Row(children: [
                            const Expanded(
                                child: Text('員工指休規則',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700))),
                            Flexible(
                              child: Text(
                                  '${_setup!.offPerDay == null ? '每天不限' : '同一天 ${_setup!.offPerDay} 位'}・${_setup!.offMonthMax == null ? '每月不限' : '每月 ${_setup!.offMonthMax} 天'}',
                                  textAlign: TextAlign.end),
                            ),
                            const Icon(Icons.chevron_right),
                          ]),
                        ),
                      ),
                      ],
                      const SizedBox(height: 10),
                      _pairRulesCard(),
                      const SizedBox(height: 10),
                      SectionCard(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('每個人的條件',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                  '沒設的照預設：正職照該月「應休」天數排休，最多連上 6 天；兼職當作每天都可以、大家平均分',
                                  style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: AppType.small)),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                    onPressed: _importHabits,
                                    icon: const Icon(Icons.history),
                                    label: const Text('照過去兩個月的班表帶入')),
                              ),
                              for (final p
                                  in widget.people.where((x) => x.active))
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                      '${p.label}（${p.isFull ? '正職' : '兼職'}）'),
                                  subtitle: Text(_ruleSummary(p),
                                      style: const TextStyle(
                                          fontSize: AppType.small)),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _editRule(p),
                                ),
                            ]),
                      ),
                    ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

String _n(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _Stepper extends StatelessWidget {
  const _Stepper(
      {required this.value,
      required this.min,
      required this.max,
      required this.onChanged,
      this.prefix = '',
      this.suffix = ''});
  final int value, min, max;
  final ValueChanged<int> onChanged;
  final String prefix, suffix;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            tooltip: '減少', // 不縮小：按鈕至少 48 點才好按（2026-11-12）
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline)),
        Text('$prefix$value$suffix',
            style: const TextStyle(fontSize: AppType.small)),
        IconButton(
            tooltip: '增加',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline)),
      ]);
}

/// 一個人的排班條件
class _RuleEditor extends StatefulWidget {
  const _RuleEditor(
      {required this.person,
      required this.rule,
      required this.storeName,
      required this.storeId,
      required this.repo,
      this.options});
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
  late final _off = TextEditingController(
      text: widget.rule.monthOff == null ? '' : _n(widget.rule.monthOff!));
  late final _min =
      TextEditingController(text: widget.rule.minShifts?.toString() ?? '');
  late final _max =
      TextEditingController(text: widget.rule.maxShifts?.toString() ?? '');
  late final _consec =
      TextEditingController(text: widget.rule.maxConsecutive?.toString() ?? '');
  late final _note = TextEditingController(text: widget.rule.note ?? '');
  late final Set<int> _noWd = {...widget.rule.noWeekdays};
  late final List<String> _marks = [...widget.rule.marks];
  late bool _asPart = widget.rule.planAsPart;
  late final Map<int, String> _wdMarks = {...widget.rule.weekdayMarks};
  bool _busy = false;

  List<String> get _choices {
    final work = _storeMarks(widget.storeName, widget.options)
        .where((m) => !ShiftMonth.isAway(m))
        .toList();
    final ranges = storeRanges(widget.storeName, widget.options);
    // 用集合去掉重複（好幾個星期用同一個、已經不在清單上的班別時，下拉選單不能有兩個一樣的選項；Codex P2）
    return <String>{...work, ...ranges, ..._marks, ..._wdMarks.values}.toList();
  }

  Future<void> _save() async {
    // 打錯的字不能當成「沒填」存檔（2026-11-16 健檢 C1）
    final bad = [
      if (widget.person.isFull && !_asPart && !parseDayNumber(_off.text).ok)
        '每月休幾天',
      if (!parseDayNumber(_min.text, integer: true).ok) '每月最少上幾天',
      if (!parseDayNumber(_max.text, integer: true).ok) '每月最多上幾天',
      if (!parseDayNumber(_consec.text, integer: true).ok) '最多連上幾天',
    ];
    if (bad.isNotEmpty) {
      showMessage(context, '「${bad.join('、')}」請只填數字（整數）', error: true);
      return;
    }
    int? i(TextEditingController c) =>
        parseDayNumber(c.text, integer: true).value?.toInt();
    final r = ShiftRule(
      personId: widget.person.id,
      monthOff: widget.person.isFull
          ? parseDayNumber(_off.text).value
          : null,
      planAsPart: widget.person.isFull && _asPart,
      minShifts: i(_min),
      maxShifts: i(_max),
      maxConsecutive: i(_consec),
      noWeekdays: _noWd,
      marks: _marks,
      weekdayMarks: {
        for (final e in _wdMarks.entries)
          if (!_noWd.contains(e.key)) e.key: e.value
      },
      note: _note.text.trim(),
    );
    if (r.minShifts != null &&
        r.maxShifts != null &&
        r.minShifts! > r.maxShifts!) {
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
      appBar: AppBar(title: Text('${p.label} 的排班條件')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            if (p.isFull)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('排班時當兼職'),
                subtitle: const Text(
                    '班表上還是正職；自動排班不照應休，照最少／最多天數和填的「可以上」排，沒上班的日子留空白',
                    style: TextStyle(fontSize: AppType.small)),
                value: _asPart,
                onChanged: (v) => setState(() => _asPart = v),
              ),
            if (p.isFull && !_asPart)
              TextField(
                  controller: _off,
                  keyboardType: numKb,
                  decoration: const InputDecoration(
                      labelText: '每月休幾天', helperText: '那個月班表下方有填「應休」就用應休')),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '每月最少上幾天'))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: _max,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '每月最多上幾天'))),
            ]),
            TextField(
                controller: _consec,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '最多連上幾天', helperText: '沒填＝6 天')),
            const SizedBox(height: 16),
            const Text('固定不排', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var w = 1; w <= 7; w++)
                SelectChip(
                  label: Text(_wdName(w)),
                  selected: _noWd.contains(w),
                  onSelected: (v) =>
                      setState(() => v ? _noWd.add(w) : _noWd.remove(w)),
                ),
            ]),
            const SizedBox(height: 16),
            Text('上班排哪些班別／時段（照點的順序，第一個優先）',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
                '沒選＝${_defaultMarks(widget.storeName, p.isFull && !_asPart, widget.options).join('、').ifEmpty('（沒有可用的班別，請到「班別／時段」恢復或新增）')}（有上個月的班就照上個月最常排的）',
                style:
                    TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in _choices)
                SelectChip(
                  label: Text(
                      _marks.contains(m) ? '${_marks.indexOf(m) + 1}. $m' : m),
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
            if (_choices.length > 1) ...[
              const SizedBox(height: 16),
              const Text('依星期排不同的班別／時段',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text('例如週五六排 BH、其他天排 B。沒設的星期用上面的第一個。',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: AppType.small)),
              const SizedBox(height: 6),
              for (var w = 1; w <= 7; w++)
                if (!_noWd.contains(w))
                  Row(children: [
                    SizedBox(width: 48, child: Text(_wdName(w))),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _wdMarks[w] ?? '',
                        items: [
                          const DropdownMenuItem(
                              value: '', child: Text('照上面的第一個')),
                          for (final m in _choices)
                            DropdownMenuItem(value: m, child: Text(m)),
                        ],
                        onChanged: (v) => setState(() =>
                            (v == null || v.isEmpty)
                                ? _wdMarks.remove(w)
                                : _wdMarks[w] = v),
                      ),
                    ),
                  ]),
            ],
            const SizedBox(height: 12),
            TextField(
                controller: _note,
                maxLength: 200,
                decoration:
                    const InputDecoration(labelText: '備註（自己看的，例如：只能上晚班）')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('儲存'),
            ),
          ]),
    );
  }
}

// =====================================================================
// 班別／時段清單（0075，老闆 2026-10-28：兩家店都可以新增、刪除）
// =====================================================================
class ShiftMarkOptionsScreen extends StatefulWidget {
  const ShiftMarkOptionsScreen(
      {super.key, required this.membership, required this.markBg});
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

  static final _rangeRe =
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d-([01]\d|2[0-3]):[0-5]\d$');
  static final _codeRe = RegExp(r'^[A-Z][A-Z0-9]{0,3}[+-]?$');
  String _norm(String v) => v
      .trim()
      .replaceAll('：', ':')
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll(RegExp('[~～－—–]'), '-');

  Future<void> _edit({required bool code, ShiftMarkOption? cur}) async {
    final m = TextEditingController(text: cur?.mark ?? '');
    final t = TextEditingController(text: cur?.timeRange ?? '');
    String? errM, errT;
    final saved = await showDialog<ShiftMarkOption>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(cur == null
              ? (code ? '新增班別' : '新增時段')
              : (code ? '修改班別' : '修改時段')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (code)
              TextField(
                controller: m,
                autofocus: cur == null,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                    labelText: '班別代碼', hintText: '例：B、BH、RBK', errorText: errM),
              ),
            TextField(
              controller: code ? t : m,
              autofocus: !code && cur == null,
              decoration: InputDecoration(
                  labelText: '時段',
                  hintText: '例：18:00-00:30（過午夜照寫）',
                  errorText: errT),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final mk = code ? m.text.trim().toUpperCase() : _norm(m.text);
                final tr = code ? _norm(t.text) : null;
                errM = null;
                errT = null;
                if (code && (!_codeRe.hasMatch(mk) || mk == 'V' || mk == 'O'))
                  errM = '大寫英文開頭、最多 4 碼（可加 + 或 -），不能用 V、O';
                if (code ? !_rangeRe.hasMatch(tr!) : !_rangeRe.hasMatch(mk))
                  errT = '格式：開始-結束，例 18:00-00:30';
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
                        sortOrder: cur?.sortOrder ??
                            ((_o?.items.length ?? 0) + 1) * 10));
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
        showMessage(
            context,
            msg.contains('duplicate') || msg.contains('23505')
                ? '已經有一樣的了'
                : msg,
            error: true);
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
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteShiftMarkOption(x.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      // 排過的班別不能刪（0113：過去的時數會跟著變）→ 改成停用
      if (x.isCode && '$e'.contains('SHIFT_CODE_USED')) {
        final hide = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('「${x.mark}」已經排進班表'),
            content: const Text('排過的班別不能刪，不然過去的時數會跟著變。\n\n改成「停用」：點格子時不會再出現，已經排好的格子跟時數照舊，之後也可以恢復。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('停用')),
            ],
          ),
        );
        if (hide == true) await _setHidden(x, true);
        return;
      }
      showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _setHidden(ShiftMarkOption x, bool hidden) async {
    try {
      await _repo.setShiftMarkOptionHidden(x.id, hidden);
      if (mounted) showMessage(context, hidden ? '「${x.mark}」停用了' : '「${x.mark}」恢復了');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Widget _section(String title, String hint, List<ShiftMarkOption> items,
          {required bool code}) =>
      SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(hint,
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('還沒有', style: TextStyle(color: AppColors.muted))),
          for (final x in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                constraints: const BoxConstraints(minWidth: 48),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                    color: widget.markBg(x.mark),
                    borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Text(code ? x.mark : '時段',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              title: Text(
                  code
                      ? (x.timeRange ?? '').replaceFirst('-', '～')
                      : x.mark.replaceFirst('-', '～'),
                  style: TextStyle(color: x.hidden ? AppColors.muted : null)),
              subtitle: Text(
                  '${x.hidden ? '已停用・' : ''}${_num(ShiftMonth.hoursOf(code ? x.timeRange : x.mark, const {}))} 小時',
                  style: const TextStyle(fontSize: AppType.small)),
              onTap: x.hidden ? null : () => _edit(code: code, cur: x),
              trailing: x.hidden
                  ? TextButton(
                      onPressed: () => _setHidden(x, false),
                      child: const Text('恢復'))
                  : IconButton(
                      tooltip: '刪除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(x)),
            ),
          TextButton.icon(
              onPressed: () => _edit(code: code),
              icon: const Icon(Icons.add),
              label: Text(code ? '新增班別' : '新增時段')),
        ]),
      );

  String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return Scaffold(
      appBar: AppBar(title: const Text('班別／時段')),
      body: _error != null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : o == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      children: [
                          Text('$_storeName 的清單，只影響這家店。點一項可以修改；已經排進班表的班別不能改時段、不能刪（過去的時數會跟著變），可以停用。',
                              style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: AppType.small)),
                          const SizedBox(height: 10),
                          _section(
                              '班別',
                              '點格子排班時可以選的班別代碼（例 B＝17:00-00:30）${StoreFeatures.of(_storeName).shiftCodes ? '；時數照時段算' : ''}',
                              o.allCodes,
                              code: true),
                          const SizedBox(height: 10),
                          _section(
                              '兼職時段',
                              '兼職排班時可以選的時段',
                              [
                                for (final x in o.items)
                                  if (!x.isCode) x
                              ],
                              code: false),
                        ]),
    );
  }
}

/// 排班條件頁最上面：全新的店一鍵帶入業態範本（ops 0152，只有公版）
class _ApplyTemplateCard extends StatelessWidget {
  const _ApplyTemplateCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(children: [
            Icon(Icons.auto_awesome_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('還沒設排班？先套用業態範本', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('酒吧、咖啡廳、餐廳的常見人數和班別，一次帶入',
                    style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
