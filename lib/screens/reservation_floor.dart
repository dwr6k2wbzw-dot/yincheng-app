import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'reservation_timeline.dart' show bizMinute, minuteLabel, seatedOn, clearedOn;

/// 訂位座位圖（老闆 2026-11-01）：把每張桌畫在平面圖上，一眼看出哪桌空、哪桌有人、哪桌等著清。
/// 上方選時間（今天預設「現在」），每張桌顯示那個時間的狀態；點桌子＝訂位動作或登記現場客。
/// 老闆／店長可按「排版」拖桌子到想要的位置、調大小，排好的位置存在資料庫，全店共用。
class ReservationFloorPlan extends StatefulWidget {
  const ReservationFloorPlan({
    super.key,
    required this.storeId,
    required this.day,
    required this.isToday,
    required this.list,
    required this.tables,
    required this.slots,
    required this.canArrange,
    required this.onTapReservation,
    required this.onTapEmpty,
    required this.onLayoutSaved,
  });
  final String storeId;
  final DateTime day;
  final bool isToday;
  final List<Reservation> list;
  final List<ReservationTable> tables;
  final List<String> slots;
  final bool canArrange;
  final void Function(Reservation r) onTapReservation;
  final void Function(ReservationTable? table, int minute) onTapEmpty;
  final VoidCallback onLayoutSaved;

  @override
  State<ReservationFloorPlan> createState() => _ReservationFloorPlanState();
}

/// 平面圖的格子數：手機直立 4 格剛好一格放桌號＋人名；排版時可以往下多加列
const _cols = 4;
const _gap = 8.0;

/// 一張桌在某個時間的狀態
enum _Seat { free, upcoming, seated, cleared }

class _TableState {
  _TableState(this.seat, this.r, {this.next, this.primary = true});
  final _Seat seat;
  final Reservation? r; // 佔著這張桌的訂位
  final Reservation? next; // 空桌時：接下來的訂位
  final bool primary; // 併桌：只在第一張桌顯示完整資料
}

class _ReservationFloorPlanState extends State<ReservationFloorPlan> {
  int? _minute; // null＝現在（只有今天可以）
  Timer? _tick;
  bool _arranging = false;
  bool _saving = false;
  late List<ReservationTable> _draft; // 排版中的位置

  @override
  void initState() {
    super.initState();
    if (widget.isToday) _tick = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
    _draft = _autoPlace(widget.tables);
  }

  @override
  void didUpdateWidget(covariant ReservationFloorPlan old) {
    super.didUpdateWidget(old);
    if (!_arranging && old.tables != widget.tables) _draft = _autoPlace(widget.tables);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Repository get _repo => AppScope.of(context).repo;

  int get _nowMinute {
    final n = DateTime.now();
    return bizMinute(n.hour * 60 + n.minute);
  }

  /// 正在看的時間（營業日分鐘數）
  int get _viewMinute {
    if (_minute != null) return _minute!;
    if (widget.isToday) return _nowMinute;
    final s = widget.slots.isEmpty ? const <int>[] : [for (final s in widget.slots) bizMinute(minutesOf(s))];
    return s.isEmpty ? 19 * 60 : s.reduce((a, b) => a < b ? a : b);
  }

  int _minuteOf(DateTime t) {
    final l = t.toLocal();
    final d = DateTime(l.year, l.month, l.day);
    final m = l.hour * 60 + l.minute;
    if (d.isAfter(widget.day)) return m + 1440 * d.difference(widget.day).inDays;
    return bizMinute(m);
  }

  /// 沒排過位置的桌子：照 sort 由左到右、由上到下排在已排的桌子下面
  static List<ReservationTable> _autoPlace(List<ReservationTable> tables) {
    final act = tables.where((t) => t.active).toList();
    final placed = act.where((t) => t.placed).toList();
    final loose = act.where((t) => !t.placed).toList()..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name));
    final taken = <(int, int)>{};
    for (final t in placed) {
      for (var x = 0; x < t.w; x++) {
        for (var y = 0; y < t.h; y++) {
          taken.add((t.posX! + x, t.posY! + y));
        }
      }
    }
    var startY = placed.isEmpty ? 0 : placed.map((t) => t.posY! + t.h).reduce((a, b) => a > b ? a : b);
    final out = [...placed];
    var x = 0, y = startY;
    for (final t in loose) {
      while (taken.contains((x, y))) {
        x++;
        if (x >= _cols) {
          x = 0;
          y++;
        }
      }
      out.add(t.copyWith(posX: x, posY: y, w: 1, h: 1));
      taken.add((x, y));
      x++;
      if (x >= _cols) {
        x = 0;
        y++;
      }
    }
    return out;
  }

  /// 每張桌在 _viewMinute 的狀態
  Map<String, _TableState> _states(List<ReservationTable> tables) {
    final m = _viewMinute;
    final shown = widget.list.where((r) => r.active).toList();
    final out = <String, _TableState>{};
    for (final t in tables) {
      Reservation? occ;
      _Seat seat = _Seat.free;
      Reservation? next;
      var bestNext = 1 << 30;
      for (final r in shown.where((r) => r.tableIds.contains(t.id))) {
        final seatedAt = seatedOn(r);
        final clearedAt = clearedOn(r);
        final start = seatedAt != null ? _minuteOf(seatedAt) : bizMinute(minutesOf(r.time));
        if (clearedAt != null) {
          final end = _minuteOf(clearedAt);
          if (start <= m && m < end) {
            occ = r;
            seat = _Seat.seated;
          } else if (end <= m && m < end + 20 && occ == null) {
            occ = r; // 剛清桌 20 分鐘內：淡淡標一下，方便知道剛走
            seat = _Seat.cleared;
          }
          continue;
        }
        if (seatedAt != null) {
          // 已入座還沒清桌：從入座起一直佔著
          if (m >= start) {
            occ = r;
            seat = _Seat.seated;
          }
          continue;
        }
        // 還沒入座：預計佔 2 小時
        if (start <= m && m < start + 120) {
          if (occ == null || seat != _Seat.seated) {
            occ = r;
            seat = _Seat.upcoming;
          }
        } else if (start > m && start < bestNext) {
          bestNext = start;
          next = r;
        }
      }
      // 併桌：同一組佔多張桌，只在第一張（照位置順序）顯示完整資料
      var primary = true;
      if (occ != null && occ.tableIds.length > 1) {
        final mine = tables.where((x) => occ!.tableIds.contains(x.id)).toList()
          ..sort((a, b) => (a.posY ?? 0) != (b.posY ?? 0) ? (a.posY ?? 0).compareTo(b.posY ?? 0) : (a.posX ?? 0).compareTo(b.posX ?? 0));
        primary = mine.isNotEmpty && mine.first.id == t.id;
      }
      out[t.id] = _TableState(seat, occ, next: occ == null ? next : null, primary: primary);
    }
    return out;
  }

  // ---------------- 排版 ----------------

  void _startArrange() => setState(() {
        _arranging = true;
        _draft = _autoPlace(widget.tables);
      });

  Future<void> _saveArrange() async {
    setState(() => _saving = true);
    try {
      await _repo.saveTableLayout(widget.storeId, _draft);
      if (!mounted) return;
      setState(() {
        _arranging = false;
        _saving = false;
      });
      showMessage(context, '座位圖已儲存');
      widget.onLayoutSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = '$e';
      showMessage(context, msg.contains('pos_x') || msg.contains('column') ? '資料庫還沒開放存座位圖位置，請請後臺處理' : friendlyError(e), error: true);
    }
  }

  bool _fits(ReservationTable t, int x, int y, int w, int h) {
    if (x < 0 || y < 0 || x + w > _cols) return false;
    for (final o in _draft) {
      if (o.id == t.id) continue;
      final ox = o.posX!, oy = o.posY!;
      final overlap = x < ox + o.w && ox < x + w && y < oy + o.h && oy < y + h;
      if (overlap) return false;
    }
    return true;
  }

  void _move(ReservationTable t, int x, int y) {
    if (!_fits(t, x, y, t.w, t.h)) return;
    setState(() => _draft = [for (final o in _draft) o.id == t.id ? o.copyWith(posX: x, posY: y) : o]);
  }

  Future<void> _resize(ReservationTable t) async {
    var w = t.w, h = t.h;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${t.name}・大小', style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
              const SizedBox(height: 4),
              Text('以格子為單位。長桌、沙發區可以拉成 2 格寬或 2 格高。', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              const SizedBox(height: 16),
              _stepper('寬', w, (v) => set(() => w = v)),
              const SizedBox(height: 8),
              _stepper('高', h, (v) => set(() => h = v)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('確定')),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final x = t.posX!, y = t.posY!;
    // 放不下就往左上找最近的空位
    for (var dy = 0; dy < 12; dy++) {
      for (var dx = 0; dx < _cols; dx++) {
        final nx = x - dx, ny = y - dy;
        if (_fits(t, nx, ny, w, h)) {
          setState(() => _draft = [for (final o in _draft) o.id == t.id ? o.copyWith(posX: nx, posY: ny, w: w, h: h) : o]);
          return;
        }
      }
    }
    if (mounted) showMessage(context, '這個大小放不進去，先把旁邊的桌子移開', error: true);
  }

  Widget _stepper(String label, int v, ValueChanged<int> onChanged) => Row(children: [
        Text(label, style: const TextStyle(fontSize: AppType.body)),
        const Spacer(),
        IconButton(onPressed: v > 1 ? () => onChanged(v - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
        SizedBox(width: 40, child: Text('$v 格', textAlign: TextAlign.center, style: const TextStyle(fontFeatures: tabular))),
        IconButton(onPressed: v < 3 ? () => onChanged(v + 1) : null, icon: const Icon(Icons.add_circle_outline)),
      ]);

  // ---------------- 畫面 ----------------

  @override
  Widget build(BuildContext context) {
    final tables = _arranging ? _draft : _autoPlace(widget.tables);
    final states = _arranging ? const <String, _TableState>{} : _states(tables);
    final shown = widget.list.where((r) => r.active).toList();
    final known = {for (final t in widget.tables) t.id};
    final unassigned = shown.where((r) => !r.tableIds.any(known.contains)).toList()..sort((a, b) => a.time.compareTo(b.time));
    final m = _viewMinute;
    // 這個時間店裡（或預計）的人數、空桌數
    final seenRes = <String>{};
    var guests = 0, freeTables = 0;
    for (final t in tables) {
      final s = states[t.id];
      if (s == null) continue;
      if (s.r != null && (s.seat == _Seat.seated || s.seat == _Seat.upcoming)) {
        if (seenRes.add(s.r!.id)) guests += s.r!.party;
      } else {
        freeTables++;
      }
    }
    final rowsNeeded = tables.isEmpty ? 2 : tables.map((t) => t.posY! + t.h).reduce((a, b) => a > b ? a : b) + (_arranging ? 2 : 0);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.tables.where((t) => t.active).isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('還沒有設定桌位：老闆或店長按右上角「桌位設定」新增桌子。', style: TextStyle(color: AppColors.warn, fontSize: AppType.small)),
        ),
      if (!_arranging) _timeBar(),
      if (!_arranging) const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: _arranging ? AppColors.primary.withValues(alpha: 0.6) : AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 標題列：時間、人數、空桌；排版時換成說明
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
            child: Row(children: [
              Expanded(
                child: _arranging
                    ? Text('長按拖曳桌子到想要的位置，點一下調大小', style: TextStyle(color: AppColors.muted, fontSize: AppType.small))
                    : Row(children: [
                        Text(_minute == null && widget.isToday ? '現在 ${minuteLabel(m)}' : minuteLabel(m),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular)),
                        const SizedBox(width: 10),
                        Icon(Icons.person, size: 13, color: AppColors.muted),
                        const SizedBox(width: 2),
                        Text('$guests', style: TextStyle(fontSize: AppType.small, color: AppColors.muted, fontFeatures: tabular)),
                        const SizedBox(width: 10),
                        Text('空 $freeTables 桌', style: TextStyle(fontSize: AppType.small, color: AppColors.muted, fontFeatures: tabular)),
                      ]),
              ),
              if (widget.canArrange && !_arranging)
                TextButton.icon(
                  onPressed: _startArrange,
                  icon: const Icon(Icons.open_with, size: 16),
                  label: const Text('排版'),
                ),
              if (_arranging) ...[
                TextButton(onPressed: _saving ? null : () => setState(() => _arranging = false), child: const Text('取消')),
                FilledButton(
                  onPressed: _saving ? null : _saveArrange,
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('儲存'),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: LayoutBuilder(builder: (c, box) {
              final cell = (box.maxWidth - _gap * (_cols - 1)) / _cols;
              double px(int v) => v * (cell + _gap);
              final height = rowsNeeded * (cell + _gap) - _gap;
              return SizedBox(
                height: height,
                child: Stack(children: [
                  // 排版時：每一格都是放置區
                  if (_arranging)
                    for (var y = 0; y < rowsNeeded; y++)
                      for (var x = 0; x < _cols; x++)
                        Positioned(
                          left: px(x),
                          top: px(y),
                          width: cell,
                          height: cell,
                          child: DragTarget<ReservationTable>(
                            onWillAcceptWithDetails: (d) => _fits(d.data, x, y, d.data.w, d.data.h),
                            onAcceptWithDetails: (d) => _move(d.data, x, y),
                            builder: (c, cand, rej) => Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                border: Border.all(color: cand.isNotEmpty ? AppColors.primary : AppColors.line.withValues(alpha: 0.7), width: cand.isNotEmpty ? 2 : 0.6),
                                color: cand.isNotEmpty ? AppColors.primary.withValues(alpha: 0.12) : null,
                              ),
                            ),
                          ),
                        ),
                  for (final t in tables)
                    Positioned(
                      left: px(t.posX!),
                      top: px(t.posY!),
                      width: px(t.w) - _gap,
                      height: px(t.h) - _gap,
                      child: _arranging
                          ? LongPressDraggable<ReservationTable>(
                              data: t,
                              delay: const Duration(milliseconds: 150),
                              feedback: SizedBox(width: px(t.w) - _gap, height: px(t.h) - _gap, child: _tableCard(t, null, lifted: true)),
                              childWhenDragging: Opacity(opacity: 0.25, child: _tableCard(t, null)),
                              child: GestureDetector(onTap: () => _resize(t), child: _tableCard(t, null)),
                            )
                          : _tableCard(t, states[t.id]),
                    ),
                ]),
              );
            }),
          ),
        ]),
      ),
      if (!_arranging) ...[
        const SizedBox(height: 10),
        _legend(),
        if (unassigned.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            Icon(Icons.table_restaurant_outlined, size: 16, color: AppColors.warn),
            const SizedBox(width: 6),
            Text('未排桌 ${unassigned.length} 組', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warn)),
            const SizedBox(width: 8),
            Text('點一下排桌', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in unassigned)
              ActionChip(
                onPressed: () => widget.onTapReservation(r),
                avatar: Text('${r.party}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warn, fontFeatures: tabular)),
                label: Text('${r.time} ${r.name}'),
                side: BorderSide(color: AppColors.warn.withValues(alpha: 0.6)),
              ),
          ]),
        ],
        const SizedBox(height: 8),
        Text('點桌子：有客人＝入座、清桌、換桌等；空桌＝登記現場客坐這桌。上方切換時間可以看之後哪幾桌有訂位。',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.caption, height: 1.5)),
      ],
    ]);
  }

  /// 時間列：今天有「現在」，之後是每個時段
  Widget _timeBar() {
    final slots = [for (final s in widget.slots) bizMinute(minutesOf(s))]..sort();
    final chips = <(int?, String)>[
      if (widget.isToday) (null, '現在'),
      for (final s in slots) (s, minuteLabel(s)),
    ];
    final cur = _minute;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (c, i) {
          final (v, label) = chips[i];
          final sel = v == cur || (v == null && cur == null && widget.isToday) || (cur == null && !widget.isToday && i == 0);
          return ChoiceChip(
            selected: sel,
            showCheckmark: false,
            label: Text(label, style: TextStyle(fontFeatures: tabular, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
            onSelected: (_) => setState(() => _minute = v),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _legend() {
    Widget dot(Color c, String label, {bool outline = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: outline ? null : c.withValues(alpha: 0.35),
              border: Border.all(color: c.withValues(alpha: outline ? 0.6 : 0.9)),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: AppType.caption, color: AppColors.muted)),
        ]);
    return Wrap(spacing: 14, runSpacing: 6, children: [
      dot(AppColors.muted, '空桌', outline: true),
      dot(AppColors.primary, '有訂位'),
      dot(AppColors.good, '已入座'),
      dot(AppColors.muted, '剛清桌'),
    ]);
  }

  Widget _tableCard(ReservationTable t, _TableState? s, {bool lifted = false}) {
    final seat = s?.seat ?? _Seat.free;
    final r = s?.r;
    final Color accent = switch (seat) {
      _Seat.free => AppColors.muted,
      _Seat.upcoming => AppColors.primary,
      _Seat.seated => AppColors.good,
      _Seat.cleared => AppColors.muted,
    };
    final filled = seat == _Seat.upcoming || seat == _Seat.seated;
    final bg = filled ? accent.withValues(alpha: 0.2) : (seat == _Seat.cleared ? AppColors.muted.withValues(alpha: 0.1) : AppColors.cardHigh);
    final border = filled ? accent.withValues(alpha: 0.75) : AppColors.line;
    final secondary = s != null && !s.primary; // 併桌的第二張以後
    final tall = t.h > 1 || t.w > 1;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppType.small, color: filled ? accent : AppColors.text)),
          ),
          if (r != null && !secondary && filled)
            Text('${r.party}', style: TextStyle(fontSize: AppType.title, fontWeight: AppFont.figure, height: 1, color: accent, fontFeatures: tabular))
          else if (r == null || !filled)
            Text('${t.seats}', style: TextStyle(fontSize: AppType.caption, color: AppColors.muted.withValues(alpha: 0.8), fontFeatures: tabular)),
        ]),
        const Spacer(),
        if (_arranging)
          Text('${t.seats} 人${t.combinable ? '・可併' : ''}', style: TextStyle(fontSize: AppType.micro, color: AppColors.muted))
        else if (r != null && filled) ...[
          Text(secondary ? '併桌' : r.name,
              maxLines: tall ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.caption, height: 1.2, color: secondary ? AppColors.muted : AppColors.text)),
          Text(
            seat == _Seat.seated
                ? '${seatedOn(r) != null ? minuteLabel(_minuteOf(seatedOn(r)!)) : r.time} 入座'
                : '${r.time}${r.walkIn ? '・現場' : ''}',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(fontSize: AppType.micro, color: accent, fontWeight: FontWeight.w600, fontFeatures: tabular),
          ),
        ] else if (r != null && seat == _Seat.cleared)
          Text('剛清桌', style: TextStyle(fontSize: AppType.micro, color: AppColors.muted))
        else if (s?.next != null)
          Text('${s!.next!.time} ${s.next!.name}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppType.micro, color: AppColors.muted, fontFeatures: tabular))
        else
          Text('空', style: TextStyle(fontSize: AppType.micro, color: AppColors.muted.withValues(alpha: 0.7))),
      ]),
    );

    final card = Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: _arranging ? AppColors.primary.withValues(alpha: 0.5) : border, width: filled ? 1.2 : 1),
          boxShadow: lifted ? [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))] : null,
        ),
        child: content,
      ),
    );
    if (_arranging) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () {
        if (r != null && filled) {
          widget.onTapReservation(r);
        } else {
          widget.onTapEmpty(t, _viewMinute);
        }
      },
      child: card,
    );
  }
}
