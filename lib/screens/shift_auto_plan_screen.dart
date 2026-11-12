part of 'shift_plan_screen.dart';

// =====================================================================
// 自動排班草稿（第二版，老闆 2026-11-12 核定；資料庫 0098）
//   * 應休沒填 → 先確認（帶上個月的數字）才排
//   * 設定互相衝突 → 先講，不硬排
//   * 草稿可以改格子（改過的會鎖住，再排一次不動）、可以先存起來；公布後員工才看得到
//   * 每次改格子都用同一套檢查器重算；有「一定不行」的問題不能公布，缺人可以公布但要確認
//   * 公布時檢查班表有沒有被別人改過
// =====================================================================
class ShiftAutoPlanScreen extends StatefulWidget {
  const ShiftAutoPlanScreen({
    super.key,
    required this.membership,
    required this.month,
    required this.markBg,
  });
  final Membership membership;
  final DateTime month;
  final MarkBg markBg;
  @override
  State<ShiftAutoPlanScreen> createState() => _ShiftAutoPlanScreenState();
}

class _ShiftAutoPlanScreenState extends State<ShiftAutoPlanScreen> {
  ShiftMonth? _cur;
  ShiftMonth? _prev;
  ShiftMonth? _next;
  ShiftPlanSetup? _setup;
  String _version = '';
  ShiftPlanDraft? _saved; // 資料庫裡存的草稿
  Object? _error;
  bool _keep = false;
  int _seed = 0;
  int _tries = 0;
  Map<String, Map<int, String>>? _entries; // null＝還沒排出草稿
  final Map<String, Set<int>> _locked = {}; // 手動改過的格子
  PlanCheck? _check;
  List<PlanIssue> _pre = const [];
  final Map<String, double> _off = {}; // 等確認的應休
  bool _offAsk = false;
  bool _dirty = false;
  bool _busy = false;
  final _hScroll = ScrollController();

  static const double _cellW = 40, _nameW = 68;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  String get _storeName => widget.membership.storeName;
  DateTime get _m => widget.month;
  int get _days => DateTime(_m.year, _m.month + 1, 0).day;
  int _wd(int d) => DateTime(_m.year, _m.month, d).weekday;
  Map<String, double>? get _codeHours =>
      storeCodeHours(_storeName, _cur?.options);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cur == null && _error == null) _load();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([
        _repo.shiftMonth(_store, _m),
        _repo.shiftMonth(_store, DateTime(_m.year, _m.month - 1)),
        _repo.shiftMonth(_store, DateTime(_m.year, _m.month + 1)),
        _repo.shiftPlanSetup(_store, _m),
        _repo.shiftMonthVersion(_store, _m),
        _repo.shiftPlanDraft(_store, _m),
      ]);
      if (!mounted) return;
      _cur = r[0] as ShiftMonth;
      _prev = r[1] as ShiftMonth;
      _next = r[2] as ShiftMonth;
      _setup = r[3] as ShiftPlanSetup;
      _version = r[4] as String;
      _saved = r[5] as ShiftPlanDraft?;
      _error = null;
      _keep = _cur!.marks.values.any((m) => m.isNotEmpty);
      _locked.clear();
      _off.clear();
      _dirty = false;
      if (_saved != null) {
        final ids = {for (final p in _people) p.id};
        _entries = {
          for (final id in ids)
            id: Map<int, String>.from(_saved!.plan[id] ?? const {}),
        };
        for (final e in _saved!.locked.entries) {
          if (ids.contains(e.key)) _locked[e.key] = {...e.value};
        }
        _pre = _precheck();
        _validate();
        setState(() {});
        return;
      }
      _entries = null;
      _check = null;
      _begin();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<ShiftPerson> get _people {
    final ps = _cur!.people.where((p) => p.active).toList();
    return [...ps.where((p) => p.isFull), ...ps.where((p) => !p.isFull)];
  }

  double get _defaultOff => (_days * 9 / 31).roundToDouble();

  /// 還沒排：先看正職的應休有沒有填（老闆 2026-11-12：沒填不讓排，帶上個月的數字給店長確認）
  void _begin() {
    final missing = [
      for (final p in _people)
        if (_planFull(p, _setup) && _cur!.stats[p.id]?.shouldOff == null) p,
    ];
    if (missing.isNotEmpty) {
      for (final p in missing) {
        _off[p.id] = _prev?.stats[p.id]?.shouldOff ??
            _setup!.rules[p.id]?.monthOff ??
            _defaultOff;
      }
      setState(() => _offAsk = true);
      return;
    }
    _start();
  }

  Future<void> _confirmOff() async {
    setState(() => _busy = true);
    try {
      for (final e in _off.entries) {
        final old = _cur!.stats[e.key];
        await _repo.saveShiftStats(
          _store,
          e.key,
          _m,
          ShiftStats(
            shouldOff: e.value,
            prevUnused: old?.prevUnused,
            compUnused: old?.compUnused,
            specialTotal: old?.specialTotal,
          ),
        );
      }
      _cur = await _repo.shiftMonth(_store, _m);
      if (!mounted) return;
      _off.clear();
      _offAsk = false;
      _busy = false;
      _start();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  /// 把所有正職的應休叫出來改（設定衝突時用）
  void _editOff() {
    for (final p in _people) {
      if (_planFull(p, _setup))
        _off[p.id] = _cur!.stats[p.id]?.shouldOff ??
            _prev?.stats[p.id]?.shouldOff ??
            _defaultOff;
    }
    setState(() => _offAsk = true);
  }

  /// 上個月最常排的上班記號（沒設排班條件時用）
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

  int _tailRun(ShiftMonth? sm, String id) {
    if (sm == null) return 0;
    var n = 0;
    for (var d = sm.days; d >= 1 && _isWork(sm.mark(id, d)); d--) {
      n++;
    }
    return n;
  }

  int _headRun(ShiftMonth? sm, String id) {
    if (sm == null) return 0;
    var n = 0;
    for (var d = 1; d <= sm.days && _isWork(sm.mark(id, d)); d++) {
      n++;
    }
    return n;
  }

  List<PlanPerson> _planPeople() {
    final s = _setup!;
    return [
      for (final p in _people)
        () {
          final r = s.rules[p.id];
          final full = _planFull(p, s);
          final usual = _usualMarks(p);
          return PlanPerson(
            id: p.id,
            name: p.name,
            full: full,
            offTarget: _cur!.stats[p.id]?.shouldOff ??
                _off[p.id] ??
                r?.monthOff ??
                _defaultOff,
            minShifts: r?.minShifts,
            maxShifts: r?.maxShifts,
            maxConsecutive: r?.maxConsecutive ?? 6,
            noWeekdays: r?.noWeekdays ?? const {},
            marks: (r?.marks.isNotEmpty ?? false)
                ? r!.marks
                : (usual.isNotEmpty
                    ? usual
                    : _defaultMarks(_storeName, full, _cur!.options)),
            weekdayMarks: r?.weekdayMarks ?? const {},
            preferRun: s.preferRun,
            prevRun: _tailRun(_prev, p.id),
            nextRun: _headRun(_next, p.id),
            busy: s.otherStoreDays[p.id] ?? const {},
          );
        }(),
    ];
  }

  Map<int, int> get _need => {
        for (var d = 1; d <= _days; d++)
          d: _setup!.specialDays[d] ?? _setup!.staffing[_wd(d)]?.need ?? 3,
      };
  Map<int, int> get _minFull {
    final need = _need;
    return {
      for (var d = 1; d <= _days; d++)
        d: (_setup!.staffing[_wd(d)]?.minFull ?? 0).clamp(0, need[d]!),
    };
  }

  /// 排的時候不動的格子：已經排好的（有開「保留」）＋草稿裡手動改過的
  Map<String, Map<int, String>> _fixed() {
    final f = <String, Map<int, String>>{};
    for (final p in _people) {
      final row = <int, String>{};
      if (_keep) row.addAll(_cur!.marks[p.id] ?? const {});
      for (final d in _locked[p.id] ?? const <int>{}) {
        final m = _entries?[p.id]?[d];
        // 手動清成空白的格子也要鎖住（空字串＝這格留空白、不能排；Codex P2）
        row[d] = m ?? '';
      }
      f[p.id] = row;
    }
    return f;
  }

  List<PlanIssue> _precheck() => precheckPlan(
        year: _m.year,
        month: _m.month,
        people: _planPeople(),
        needByDay: _need,
        minFullByDay: _minFull,
        fixed: _fixed(),
        requests: _setup!.requests,
        pairRules: _setup!.pairRules,
      );

  void _start() {
    _pre = _precheck();
    if (_pre.any((i) => i.level == 0)) {
      // 設定互相衝突：不排。已經有草稿的話要留著（連同手動鎖住的格子），只跳出說明（Codex P2）；
      // 還沒有草稿時，畫面會顯示「先改好才能排」。
      setState(() {});
      if (_entries != null) _showBlocked();
      return;
    }
    _run();
  }

  Future<void> _showBlocked() async {
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('有設定互相衝突，這次沒有重排'),
        content: SingleChildScrollView(
          child: Text(
            '${_pre.where((i) => i.level == 0).map((i) => '・${i.text}').join('\n')}\n\n目前的草稿（包含你改過的格子）都還在。改好設定後再按「再排一次」。',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('先不改')),
          TextButton(
              onPressed: () => Navigator.pop(c, 'off'),
              child: const Text('改應休天數')),
          FilledButton(
              onPressed: () => Navigator.pop(c, 'rules'),
              child: const Text('改排班條件')),
        ],
      ),
    );
    if (!mounted) return;
    if (r == 'off') _editOff();
    if (r == 'rules') _openRules();
  }

  void _run() {
    final res = planShifts(
      year: _m.year,
      month: _m.month,
      people: _planPeople(),
      needByDay: _need,
      minFullByDay: _minFull,
      fixed: _fixed(),
      requests: _setup!.requests,
      pairRules: _setup!.pairRules,
      seed: _seed,
    );
    setState(() {
      _entries = {
        for (final e in res.entries.entries)
          e.key: Map<int, String>.from(e.value),
      };
      _check = res.check;
      _tries = res.tries;
      _dirty = true;
    });
  }

  void _validate() {
    _check = validateSchedule(
      year: _m.year,
      month: _m.month,
      people: _planPeople(),
      needByDay: _need,
      minFullByDay: _minFull,
      entries: _entries ?? const {},
      requests: _setup!.requests,
      pairRules: _setup!.pairRules,
    );
  }

  int get _changed {
    var n = 0;
    for (final p in _people) {
      for (var d = 1; d <= _days; d++) {
        if (_entries?[p.id]?[d] != _cur!.mark(p.id, d)) n++;
      }
    }
    return n;
  }

  // ---------------- 改格子 ----------------
  Future<void> _editCell(ShiftPerson p, int d) async {
    final cur = _entries?[p.id]?[d];
    final locked = _locked[p.id]?.contains(d) ?? false;
    final req = _setup!.requests[p.id]?[d];
    final busy = _setup!.otherStoreDays[p.id]?.contains(d) ?? false;
    final probs = [
      for (final i in _check?.issues ?? const <PlanIssue>[])
        if (i.personId == p.id && i.days.contains(d) && i.level <= 1) i.text,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${p.name}・${DateFormat('M/d（E）', 'zh_TW').format(DateTime(_m.year, _m.month, d))}',
                style: const TextStyle(
                  fontSize: AppType.title,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (req != null)
                Text(
                  req == 'off'
                      ? '這天${_planFull(p, _setup) ? '指休' : '不能上'}'
                      : '這天${_planFull(p, _setup) ? '想上班' : '可以上'}',
                  style: TextStyle(
                    color: AppColors.warn,
                    fontSize: AppType.small,
                  ),
                ),
              if (busy)
                Text(
                  '這天在另一家店已經有班',
                  style: TextStyle(
                    color: AppColors.bad,
                    fontSize: AppType.small,
                  ),
                ),
              for (final t in probs)
                Text(
                  t,
                  style: TextStyle(
                    color: AppColors.bad,
                    fontSize: AppType.small,
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in {
                    ..._storeMarks(_storeName, _cur!.options),
                    ...storeRanges(_storeName, _cur!.options),
                    ..._usualMarks(p),
                    ...?_setup!.rules[p.id]?.weekdayMarks.values,
                  })
                    SelectChip(
                      label: Text(m),
                      selected: m == cur,
                      selectedColor: widget.markBg(m) ?? AppColors.cardHigh,
                      onSelected: (_) => Navigator.pop(c, m),
                    ),
                  ActionChip(
                    label: const Text('清除'),
                    onPressed: () => Navigator.pop(c, ''),
                  ),
                  if (locked)
                    ActionChip(
                      avatar: const Icon(Icons.lock_open, size: 16),
                      label: const Text('解除鎖定'),
                      onPressed: () => Navigator.pop(c, '\u0000'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '改過的格子會鎖住（左上角有鎖），按「再排一次」不會動到。',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (picked == '\u0000') {
        _locked[p.id]?.remove(d);
      } else {
        final m = _entries!.putIfAbsent(p.id, () => {});
        if (picked.isEmpty) {
          m.remove(d);
        } else {
          m[d] = picked;
        }
        _locked.putIfAbsent(p.id, () => {}).add(d);
      }
      _dirty = true;
      _validate();
    });
  }

  // ---------------- 存草稿／公布 ----------------
  Map<String, Map<int, String>> _planOut() => {
        for (final p in _people)
          p.id: Map<int, String>.from(_entries?[p.id] ?? const {}),
      };

  Future<bool> _saveDraft({bool quiet = false}) async {
    setState(() => _busy = true);
    try {
      await _repo.saveShiftPlanDraft(_store, _m, _planOut(), _locked);
      if (!mounted) return true;
      setState(() {
        _busy = false;
        _dirty = false;
        _saved = ShiftPlanDraft(
          _planOut(),
          {
            for (final e in _locked.entries) e.key: {...e.value},
          },
          '你',
          DateTime.now(),
        );
      });
      if (!quiet) showMessage(context, '草稿存好了，還沒公布（員工看不到）');
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e), error: true);
      }
      return false;
    }
  }

  Future<void> _discardDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('丟掉這份草稿，重新排？'),
        content: const Text('草稿裡手動改過的格子都會不見。已經公布的班表不受影響。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('丟掉重排'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _repo.deleteShiftPlanDraft(_store, _m);
      if (!mounted) return;
      _saved = null;
      _locked.clear();
      _entries = null;
      _check = null;
      _dirty = false;
      _busy = false;
      _begin();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _publish() async {
    final c = _check!;
    final blocks = [
      for (final i in c.issues)
        if (i.level == 0) i.text,
    ];
    if (blocks.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (x) => AlertDialog(
          title: const Text('還不能公布'),
          content: SingleChildScrollView(
            child: Text(
              '${blocks.map((t) => '・$t').join('\n')}\n\n這幾格要先改掉（紅框的格子）。如果那個人真的可以來，請先到「填指休」把那天拿掉。',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(x),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final probs = [
      for (final i in c.issues)
        if (i.level == 1 || i.level == 2) i.text,
    ];
    final hasData = _cur!.marks.values.any((m) => m.isNotEmpty);
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: Text('公布 ${_m.month} 月班表？'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (probs.isNotEmpty) ...[
                Text(
                  '還有 ${probs.length} 個問題沒處理：',
                  style: TextStyle(
                    color: AppColors.bad,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final t in probs.take(6))
                  Text('・$t', style: const TextStyle(fontSize: AppType.small)),
                if (probs.length > 6)
                  Text(
                    '…還有 ${probs.length - 6} 個',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: AppType.small,
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              Text(
                [
                  if (hasData)
                    '${_m.month} 月目前的班會換成這份草稿（$_changed 格不同）。'
                  else
                    '會把這份草稿排進 ${_m.month} 月班表。',
                  '公布後員工就看得到，小鈴鐺會通知。',
                  '只會改班表上顯示中的人；備註、統計數字不動。公布後還是可以點格子修改。',
                ].join('\n\n'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            child: Text(probs.isEmpty ? '公布' : '還是要公布'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final n = await _repo.applyShiftPlan(
        _store,
        _m,
        _planOut(),
        expected: _version,
      );
      if (mounted) {
        _dirty = false;
        showMessage(context, '${_m.month} 月班表公布了（$n 格）');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      if ('$e'.contains('SHIFT_CHANGED')) {
        // 班表在調整的時候被別人改過：先把草稿存起來，重新載入後讓使用者對照再公布
        await _saveDraft(quiet: true);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (x) => AlertDialog(
            title: const Text('班表剛剛被別人改過'),
            content: const Text(
              '為了不蓋掉對方改的，這次沒有公布。\n\n你的草稿已經先存起來了。按「重新載入」後，框起來的格子＝跟現在班表不一樣的地方，確認後再公布一次。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(x),
                child: const Text('重新載入'),
              ),
            ],
          ),
        );
        if (mounted) {
          setState(() {
            _busy = false;
            _cur = null;
          });
          _load();
        }
        return;
      }
      setState(() => _busy = false);
      showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _leave() async {
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('草稿還沒存'),
        content: const Text('現在離開的話，這份草稿（包含手動改的格子）會不見。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('繼續調整'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'drop'),
            child: const Text('不存，離開'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            child: const Text('存草稿再離開'),
          ),
        ],
      ),
    );
    if (r == null || !mounted) return;
    if (r == 'save' && !await _saveDraft(quiet: true)) return;
    if (mounted) {
      setState(() => _dirty = false);
      Navigator.pop(context, false);
    }
  }

  Future<void> _openRules() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShiftRulesScreen(
          membership: widget.membership,
          month: _m,
          people: _cur!.people,
          options: _cur!.options,
        ),
      ),
    );
    if (!mounted) return;
    // 條件改了：重新讀設定。已經有草稿就只重新檢查（不動格子），還沒排出來就重排
    try {
      _setup = await _repo.shiftPlanSetup(_store, _m);
      if (!mounted) return;
      if (_entries == null ||
          (_saved == null && _locked.values.every((x) => x.isEmpty))) {
        // 還沒排出來，或草稿還沒手動改過、也沒存過 → 直接照新的條件重排
        _start();
      } else {
        // 草稿已經動過：不動格子，只照新的條件重新檢查
        setState(() {
          _pre = _precheck();
          _validate();
        });
        if (!(_check?.clean ?? true)) {
          showMessage(context, '排班條件改了。按「再排一次」會照新的條件重排（鎖住的格子不動）');
        }
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  void _jumpTo(int d) {
    if (!_hScroll.hasClients) return;
    _hScroll.animateTo(
      ((d - 2) * (_cellW + 2)).clamp(0.0, _hScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // ---------------- 畫面 ----------------
  Widget _cell(
    String? text, {
    Color? bg,
    Color? frame,
    bool header = false,
    double w = _cellW,
    Color? dot,
    bool lock = false,
    VoidCallback? onTap,
    Color? color,
    double gap = 0,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: w,
          height: header ? 36 : 34,
          margin: EdgeInsets.fromLTRB(1 + gap, 1, 1, 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: frame != null
                ? Border.all(color: frame, width: 2)
                : (bg == null && !header
                    ? Border.all(color: AppColors.cardHigh)
                    : null),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  text ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: header
                        ? 11
                        : (text != null && text.length > 4 ? 10 : 12),
                    height: 1.1,
                    color: color,
                  ),
                ),
              ),
              if (dot != null)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                ),
              if (lock)
                Positioned(
                  left: 1,
                  top: 1,
                  child: Icon(Icons.lock, size: 9, color: AppColors.muted),
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ready = _cur != null && _setup != null;
    return PopScope(
      canPop: !(_dirty && _entries != null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('自動排 ${_m.month} 月班表'),
          actions: [
            if (ready)
              IconButton(
                tooltip: '排班條件',
                icon: const Icon(Icons.tune),
                onPressed: _busy ? null : _openRules,
              ),
          ],
        ),
        body: _error != null
            ? ErrorView(message: friendlyError(_error!), onRetry: _load)
            : !ready
                ? const Center(child: CircularProgressIndicator())
                : _offAsk
                    ? _offBody()
                    : _entries == null
                        ? _blockedBody()
                        : _body(),
      ),
    );
  }

  /// 第一步：確認正職這個月休幾天
  Widget _offBody() {
    final fulls = [
      for (final p in _people)
        if (_off.containsKey(p.id)) p,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          '先確認 ${_m.month} 月正職休幾天',
          style: const TextStyle(
            fontSize: AppType.title,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '自動排班會照這個天數排休（特休另外算）。先帶上個月的數字，不對請改。確認後會存到班表下方的「應休」。',
          style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
        ),
        const SizedBox(height: 12),
        SectionCard(
          child: Column(
            children: [
              for (final p in fulls)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '休 ${_n(_off[p.id]!)} 天＝上 ${_days - _off[p.id]!.round()} 天'
                              '${_prev?.stats[p.id]?.shouldOff != null ? '（上個月休 ${_n(_prev!.stats[p.id]!.shouldOff!)} 天）' : ''}',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: AppType.small,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _Stepper(
                        value: _off[p.id]!.round(),
                        min: 0,
                        max: _days,
                        onChanged: (x) =>
                            setState(() => _off[p.id] = x.toDouble()),
                        suffix: '天',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _confirmOff,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('確認，開始排班'),
        ),
      ],
    );
  }

  /// 設定互相衝突：先講清楚，不硬排
  Widget _blockedBody() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '有設定互相衝突，先改好才能排',
            style: TextStyle(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.bad,
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in _pre.where((i) => i.level == 0))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('・${i.text}'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _editOff,
                  child: const Text('改應休天數'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _openRules,
                  child: const Text('改排班條件'),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _issueLine(PlanIssue i) => InkWell(
        onTap: i.days.isEmpty ? null : () => _jumpTo(i.days.first),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '・${i.text}',
                  style: const TextStyle(fontSize: AppType.small),
                ),
              ),
              if (i.days.isNotEmpty)
                Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
            ],
          ),
        ),
      );

  Widget _body() {
    final wdf = DateFormat('E', 'zh_TW');
    final people = _people;
    final req = _setup!.requests;
    final c = _check!;
    final need = _need, minFull = _minFull;
    final bad = c.badCells;
    final hasData = _cur!.marks.values.any((m) => m.isNotEmpty);
    final ch = _codeHours;
    final hard = [
      for (final i in c.issues)
        if (i.level == 0) i,
    ];
    final rule = [
      for (final i in c.issues)
        if (i.level == 1) i,
    ];
    final short = [
      for (final i in c.issues)
        if (i.level == 2) i,
    ];
    final info = [
      for (final i in c.issues)
        if (i.level == 3 && i.code != 'pref') i,
      for (final i in _pre)
        if (i.level == 3) i,
    ];
    // 沒設條件、也沒填可以上的兼職：現在是「當作每天都可以、平均分」
    final loose = [
      for (final p in people)
        if (!_planFull(p, _setup) &&
            (_setup!.rules[p.id]?.minShifts == null &&
                _setup!.rules[p.id]?.maxShifts == null &&
                (_setup!.rules[p.id]?.noWeekdays.isEmpty ?? true)) &&
            !(req[p.id]?.values.any((v) => v == 'on') ?? false))
          p.name,
    ];
    double gapOf(int d) => (d > 1 && _wd(d) == 1) ? 5 : 0; // 週一前面留一點空，一週一週看得出來

    Widget nameCell(ShiftPerson p) => _cell(
          _planFull(p, _setup)
              ? p.name
              : '${p.name}\n${p.isFull ? '當兼職' : '兼職'}',
          w: _nameW,
        );
    Widget dayRow(ShiftPerson p) {
      final row = _entries![p.id] ?? const <int, String>{};
      final full = _planFull(p, _setup);
      final work = row.values.where(_isWork).length;
      final rest = c.restDays[p.id] ?? 0;
      final target = c.targets[p.id];
      final offWant = target == null
          ? null
          : _days - target - row.values.where((m) => m == '特休').length;
      return Row(
        children: [
          for (var d = 1; d <= _days; d++)
            _cell(
              row[d]?.replaceFirst('-', '\n'),
              gap: gapOf(d),
              bg: widget.markBg(row[d]),
              frame: bad.containsKey('${p.id}|$d')
                  ? AppColors.bad
                  : (hasData && row[d] != _cur!.mark(p.id, d)
                      ? AppColors.primary
                      : null),
              lock: _locked[p.id]?.contains(d) ?? false,
              dot: (_setup!.otherStoreDays[p.id]?.contains(d) ?? false)
                  ? AppColors.bad
                  : (req[p.id]?[d] == 'off'
                      ? const Color(0xFFE0A34A)
                      : (req[p.id]?[d] == 'on' ? AppColors.good : null)),
              onTap: _busy ? null : () => _editCell(p, d),
            ),
          _cell('$work', w: 34),
          _cell(
            full ? '$rest/${offWant ?? '-'}' : '',
            w: 44,
            color: full && offWant != null && rest != offWant
                ? AppColors.bad
                : null,
          ),
          if (ch != null)
            _cell(
              _n(
                row.values.fold<double>(
                  0,
                  (a, m) => a + ShiftMonth.hoursOf(m, ch),
                ),
              ),
              w: 44,
            ),
        ],
      );
    }

    final fulls = people.where((p) => p.isFull).toList(),
        parts = people.where((p) => !p.isFull).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (_saved != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.save_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '存起來的草稿${_saved!.updatedName == null ? '' : '（${_saved!.updatedName}'
                        '${_saved!.updatedAt == null ? '' : '・${DateFormat('M/d HH:mm').format(_saved!.updatedAt!)}'}）'}'
                    '${_dirty ? '，有新的修改還沒存' : ''}・還沒公布',
                    style: const TextStyle(fontSize: AppType.small),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _discardDraft,
                  child: const Text('丟掉重排'),
                ),
              ],
            ),
          ),
        // 結論：有沒有排好，照實講
        SectionCard(
          child: Row(
            children: [
              Icon(
                c.clean ? Icons.check_circle_outline : Icons.error_outline,
                color: c.clean
                    ? AppColors.good
                    : (hard.isNotEmpty ? AppColors.bad : AppColors.warn),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.clean
                      ? '這份草稿沒有問題${_tries > 1 ? '（算了 $_tries 份挑最好的）' : ''}。還沒公布，員工看不到。'
                      : [
                            if (hard.isNotEmpty) '${hard.length} 個一定要改',
                            if (rule.isNotEmpty) '${rule.length} 個違反排班條件',
                            if (c.score[2] > 0)
                              '缺正職 ${short.where((i) => i.code == 'noFull').length} 天',
                            if (c.score[3] > 0)
                              '缺人 ${short.where((i) => i.code == 'short').length} 天',
                          ].join('、') +
                          '。${rule.isEmpty && hard.isEmpty && _locked.values.every((s) => s.isEmpty) ? '照現在的條件排不滿，下面列出原因。' : '下面列出來，點一下會跳到那一天。'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (hasData)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('保留已經排好的格子'),
            subtitle: Text(
              _keep ? '只補空白的格子（藍框＝跟目前班表不同）' : '整個月重新排（藍框＝跟目前班表不同）',
              style: const TextStyle(fontSize: AppType.small),
            ),
            value: _keep,
            onChanged: _busy
                ? null
                : (v) {
                    _keep = v;
                    _start();
                  },
          ),
        if (hard.isNotEmpty ||
            rule.isNotEmpty ||
            short.isNotEmpty ||
            info.isNotEmpty ||
            loose.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hard.isNotEmpty) ...[
                  Text(
                    '一定要改（改好才能公布）',
                    style: TextStyle(
                      color: AppColors.bad,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final i in hard) _issueLine(i),
                ],
                if (rule.isNotEmpty) ...[
                  Text(
                    '違反排班條件',
                    style: TextStyle(
                      color: AppColors.bad,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final i in rule) _issueLine(i),
                ],
                if (short.isNotEmpty) ...[
                  Text(
                    '缺人',
                    style: TextStyle(
                      color: AppColors.warn,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final i in short) _issueLine(i),
                ],
                if (info.isNotEmpty || loose.isNotEmpty) ...[
                  Text(
                    '提醒',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final i in info) _issueLine(i),
                  if (loose.isNotEmpty) ...[
                    Text(
                      '・${loose.join('、')} 沒設條件、也沒填可以上：先當作每天都可以，大家平均分。',
                      style: const TextStyle(fontSize: AppType.small),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busy ? null : _openRules,
                        icon: const Icon(Icons.history, size: 18),
                        label: const Text('到排班條件，照過去的班表帶入'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          '點格子可以改。小圓點：橘＝指休／不能上，綠＝可以上，紅＝另一家店有班。紅框＝有問題。',
          style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
        ),
        const SizedBox(height: 6),
        SectionCard(
          padding: const EdgeInsets.all(6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 名字欄固定，左右滑的時候看得到是誰
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _cell('', w: _nameW, header: true),
                  for (final p in fulls) nameCell(p),
                  if (parts.isNotEmpty) const SizedBox(height: 6),
                  for (final p in parts) nameCell(p),
                  const SizedBox(height: 4),
                  _cell('人力／要', w: _nameW),
                  _cell('正職', w: _nameW),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var d = 1; d <= _days; d++)
                            _cell(
                              '$d\n${wdf.format(DateTime(_m.year, _m.month, d))}',
                              header: true,
                              gap: gapOf(d),
                              color: c.shortDays.contains(d)
                                  ? AppColors.bad
                                  : null,
                              bg: _setup!.specialDays.containsKey(d)
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : ((_wd(d) == 5 || _wd(d) == 6)
                                      ? AppColors.cardHigh
                                      : null),
                            ),
                          _cell('上班', w: 34, header: true),
                          _cell('休/應休', w: 44, header: true),
                          if (ch != null) _cell('時數', w: 44, header: true),
                        ],
                      ),
                      for (final p in fulls) dayRow(p),
                      if (parts.isNotEmpty) const SizedBox(height: 6),
                      for (final p in parts) dayRow(p),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (var d = 1; d <= _days; d++)
                            _cell(
                              '${c.staffed[d]}/${need[d]}',
                              gap: gapOf(d),
                              color: c.staffed[d]! < need[d]!
                                  ? AppColors.bad
                                  : (c.staffed[d]! > need[d]!
                                      ? AppColors.warn
                                      : AppColors.primary),
                              bg: c.staffed[d]! < need[d]!
                                  ? AppColors.bad.withValues(alpha: 0.15)
                                  : null,
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          for (var d = 1; d <= _days; d++)
                            _cell(
                              '${c.fulls[d]}',
                              gap: gapOf(d),
                              color: c.fulls[d]! < minFull[d]!
                                  ? AppColors.bad
                                  : AppColors.muted,
                              bg: c.fulls[d]! < minFull[d]!
                                  ? AppColors.bad.withValues(alpha: 0.15)
                                  : null,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        _seed++;
                        _start();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('再排一次'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || !_dirty ? null : () => _saveDraft(),
                icon: const Icon(Icons.save_outlined),
                label: Text(_dirty ? '存草稿' : '已存'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _publish,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('公布 ${_m.month} 月班表'),
        ),
        const SizedBox(height: 6),
        Text(
          '「再排一次」會保留鎖住的格子，只重排其他格。公布後員工才看得到。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
        ),
      ],
    );
  }
}
