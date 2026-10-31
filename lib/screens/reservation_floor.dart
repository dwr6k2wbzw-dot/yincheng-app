import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/clock.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'reservation_timeline.dart' show bizMinute, minuteLabel, seatedOn, clearedOn;

/// 訂位座位圖（老闆 2026-11-01，照 iCHEF 座位表的樣子）：平面圖 10 格寬，每張桌一個圓（吧台、小圓桌）或方塊（方桌），
/// 整張圖一次看完，兩指可以放大看人名；上方選時間（今天預設「現在」），每張桌顯示那個時間的狀態。
/// 點桌子＝訂位動作或登記現場客。老闆／店長可按「排版」長按拖曳桌子、點一下改桌形與大小，存在資料庫全店共用。
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

/// 平面圖的格子：10 格寬（隱城吧台 A1～A8 一排 8 張、右邊還放得下 B／C／D 桌）；一格 64 邏輯像素，縮到手機寬度剛好整張看完
const _cols = 10;
const _cell = 64.0;
const _gap = 6.0;
const _minRows = 7;

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
  final _tc = TransformationController();
  double _fit = 1; // 整張圖剛好塞進寬度的縮放
  Size _viewSize = const Size(360, 300); // 平面圖可視範圍（放大時以中央為準）
  double _scale = 1; // 目前縮放（決定桌子上顯示多少字）
  bool _zoomed = false;
  static String? _floorPick; // 記住上次看的樓層（換天、重開頁面都一樣）

  @override
  void initState() {
    super.initState();
    if (widget.isToday) _tick = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
    _draft = _autoPlace(widget.tables);
    _tc.addListener(_onTransform);
  }

  @override
  void didUpdateWidget(covariant ReservationFloorPlan old) {
    super.didUpdateWidget(old);
    if (!_arranging && old.tables != widget.tables) _draft = _autoPlace(widget.tables);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tc.removeListener(_onTransform);
    _tc.dispose();
    super.dispose();
  }

  bool _shownDetailed = false; // 上次畫的時候是不是「放大版」（跨過門檻才重畫，手指動不重畫整張圖）
  void _onTransform() {
    _scale = _tc.value.getMaxScaleOnAxis();
    if (_detailed != _shownDetailed) setState(() {});
  }

  bool get _detailed => _tc.value.getMaxScaleOnAxis() >= _fit * 1.6;

  Repository get _repo => AppScope.of(context).repo;

  int get _nowMinute {
    final n = taipeiNow();
    return bizMinute(n.hour * 60 + n.minute);
  }

  /// 正在看的時間（營業日分鐘數）
  int get _viewMinute {
    if (_minute != null) return _minute!;
    if (widget.isToday) return _nowMinute;
    final s = [for (final s in widget.slots) bizMinute(minutesOf(s))];
    return s.isEmpty ? 19 * 60 : s.reduce((a, b) => a < b ? a : b);
  }

  int _minuteOf(DateTime t) {
    final l = toTaipei(t);
    final d = DateTime(l.year, l.month, l.day);
    final m = l.hour * 60 + l.minute;
    if (d.isAfter(widget.day)) return m + 1440 * calendarDaysBetween(widget.day, d);
    return bizMinute(m);
  }

  /// 沒排過位置的桌子：照 sort 由左到右、由上到下排在已排的桌子下面
  static List<ReservationTable> _autoPlace(List<ReservationTable> tables) {
    // 每個樓層各自排（位置是每層自己的座標）
    final floors = {for (final t in tables.where((t) => t.active)) t.floor};
    return [for (final f in floors) ..._autoPlaceFloor(tables.where((t) => t.active && t.floor == f).toList())];
  }

  static List<ReservationTable> _autoPlaceFloor(List<ReservationTable> act) {
    final placed = act.where((t) => t.placed && t.posX! + t.w <= _cols).toList();
    final loose = act.where((t) => !placed.contains(t)).toList()
      ..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name));
    final taken = <(int, int)>{};
    for (final t in placed) {
      for (var x = 0; x < t.w; x++) {
        for (var y = 0; y < t.h; y++) {
          taken.add((t.posX! + x, t.posY! + y));
        }
      }
    }
    final out = [...placed];
    var x = 0, y = placed.isEmpty ? 0 : placed.map((t) => t.posY! + t.h).reduce(math.max);
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
      var seat = _Seat.free;
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

  // ---------------- 縮放 ----------------

  void _setZoom(bool zoomIn, Size viewport) {
    final target = zoomIn ? math.min(_fit * 1.8, 1.0) : _fit;
    final cur = _tc.value;
    // 放大：以目前畫面中心為準；縮小：回到左上整張圖
    if (!zoomIn) {
      _tc.value = Matrix4.identity()..scaleByDouble(target, target, target, 1);
    } else {
      final curS = cur.getMaxScaleOnAxis();
      final center = Offset(viewport.width / 2, viewport.height / 2);
      final scene = Offset((center.dx - cur.getTranslation().x) / curS, (center.dy - cur.getTranslation().y) / curS);
      _tc.value = Matrix4.identity()
        ..translateByDouble(center.dx - scene.dx * target, center.dy - scene.dy * target, 0, 1)
        ..scaleByDouble(target, target, target, 1);
    }
    setState(() => _zoomed = zoomIn);
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
      showMessage(context, friendlyError(e), error: true);
    }
  }

  bool _fits(ReservationTable t, int x, int y, int w, int h) {
    if (x < 0 || y < 0 || x + w > _cols) return false;
    for (final o in _draft) {
      if (o.id == t.id || o.floor != t.floor) continue;
      final ox = o.posX!, oy = o.posY!;
      if (x < ox + o.w && ox < x + w && y < oy + o.h && oy < y + h) return false;
    }
    return true;
  }

  void _move(ReservationTable t, int x, int y) {
    if (!_fits(t, x, y, t.w, t.h)) return;
    setState(() => _draft = [for (final o in _draft) o.id == t.id ? o.copyWith(posX: x, posY: y) : o]);
  }

  Future<void> _editTable(ReservationTable t) async {
    var w = t.w, h = t.h, round = t.isRound, floor = t.floor;
    const floorOptions = ['1F', '2F', '3F'];
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${t.name}・桌形與大小', style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
              const SizedBox(height: 4),
              Text('圓＝吧台、小圓桌；方＝方桌、沙發區。長桌可以拉成 2～3 格寬。', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, icon: Icon(Icons.circle_outlined), label: Text('圓桌')),
                  ButtonSegment(value: false, icon: Icon(Icons.crop_square), label: Text('方桌')),
                ],
                selected: {round},
                showSelectedIcon: false,
                onSelectionChanged: (v) => set(() => round = v.first),
              ),
              const SizedBox(height: 10),
              Row(children: [
                const Text('樓層', style: TextStyle(fontSize: AppType.body)),
                const Spacer(),
                SegmentedButton<String>(
                  segments: [for (final f in floorOptions) ButtonSegment(value: f, label: Text(f))],
                  selected: {floorOptions.contains(floor) ? floor : floorOptions.first},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: (v) => set(() => floor = v.first),
                ),
              ]),
              const SizedBox(height: 4),
              _stepper('寬', w, (v) => set(() => w = v)),
              _stepper('高', h, (v) => set(() => h = v)),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('確定')),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final shape = round ? 'round' : 'square';
    final moved = t.copyWith(floor: floor);
    if (floor != t.floor) {
      // 換樓層：放到那層最下面的空位，順便切過去看
      final onFloor = _draft.where((o) => o.floor == floor && o.id != t.id).toList();
      final startY = onFloor.isEmpty ? 0 : onFloor.map((o) => o.posY! + o.h).reduce(math.max);
      for (var y = startY; y < startY + 20; y++) {
        for (var x = 0; x <= _cols - w; x++) {
          if (_fits(moved, x, y, w, h)) {
            setState(() {
              _draft = [for (final o in _draft) o.id == t.id ? o.copyWith(posX: x, posY: y, w: w, h: h, shape: shape, floor: floor) : o];
              _floorPick = floor;
            });
            return;
          }
        }
      }
      // 那層找不到空位：不要退回舊樓層的座標找（會跟舊樓層的桌重疊；健檢 2026-11-01 Bug 6）
      if (mounted) showMessage(context, '$floor 放不下這張桌，先把那層的桌子移一移', error: true);
      return;
    }
    final x = t.posX!, y = t.posY!;
    // 放不下就往左上找最近的空位
    for (var dy = 0; dy < 12; dy++) {
      for (var dx = 0; dx < _cols; dx++) {
        final nx = x - dx, ny = y - dy;
        if (_fits(moved, nx, ny, w, h)) {
          setState(() => _draft = [for (final o in _draft) o.id == t.id ? o.copyWith(posX: nx, posY: ny, w: w, h: h, shape: shape) : o]);
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

  List<String> get _floors {
    final f = {for (final t in widget.tables.where((t) => t.active)) t.floor, for (final t in _draft) t.floor}.toList()..sort();
    return f.isEmpty ? const ['1F'] : f;
  }

  String get _floor {
    final fs = _floors;
    if (_floorPick != null && fs.contains(_floorPick)) return _floorPick!;
    // 預設看桌子最多的那層（隱城主要座位在二樓）
    final all = _arranging ? _draft : widget.tables.where((t) => t.active).toList();
    String best = fs.first;
    var bestN = -1;
    for (final f in fs) {
      final n = all.where((t) => t.floor == f).length;
      if (n > bestN) {
        bestN = n;
        best = f;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final allTables = _arranging ? _draft : _autoPlace(widget.tables);
    final floor = _floor;
    final tables = allTables.where((t) => t.floor == floor).toList();
    final states = _arranging ? const <String, _TableState>{} : _states(allTables);
    final shown = widget.list.where((r) => r.active).toList();
    final known = {for (final t in widget.tables) t.id};
    final unassigned = shown.where((r) => !r.tableIds.any(known.contains)).toList()..sort((a, b) => a.time.compareTo(b.time));
    final m = _viewMinute;
    // 這個時間店裡（或預計）的人數、空桌數
    final seenRes = <String>{};
    var guests = 0, freeTables = 0;
    for (final t in allTables) {
      final s = states[t.id];
      if (s == null) continue;
      if (s.r != null && (s.seat == _Seat.seated || s.seat == _Seat.upcoming)) {
        if (seenRes.add(s.r!.id)) guests += s.r!.party;
      } else if (t.floor == floor) {
        freeTables++;
      }
    }
    final rows = math.max(_minRows, tables.isEmpty ? 0 : tables.map((t) => t.posY! + t.h).reduce(math.max)) + (_arranging ? 2 : 0);
    const canvasW = _cols * _cell + (_cols - 1) * _gap;
    final canvasH = rows * _cell + (rows - 1) * _gap;

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
          // 樓層分頁（照 iCHEF：1F／2F…；只有一層就不顯示）
          if (_floors.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Row(children: [
                for (final f in _floors) ...[
                  ChoiceChip(
                    selected: f == floor,
                    showCheckmark: false,
                    label: Text(f, style: TextStyle(fontFeatures: tabular, fontWeight: f == floor ? FontWeight.w700 : FontWeight.w500)),
                    onSelected: (_) => setState(() {
                      _floorPick = f;
                      _zoomed = false;
                      _tc.value = Matrix4.identity()..scaleByDouble(_fit, _fit, _fit, 1);
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                Text('${tables.length} 桌', style: TextStyle(fontSize: AppType.caption, color: AppColors.muted, fontFeatures: tabular)),
              ]),
            ),
          // 標題列：時間、人數、空桌、放大；排版時換成說明＋取消／儲存
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
            child: Row(children: [
              Expanded(
                child: _arranging
                    ? Text('長按桌子拖到想要的位置；點一下改圓／方、大小、樓層', style: TextStyle(color: AppColors.muted, fontSize: AppType.small))
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
              if (!_arranging)
                IconButton(
                  tooltip: _zoomed ? '看整張圖' : '放大看人名',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _setZoom(!_zoomed, _viewSize),
                  icon: Icon(_zoomed ? Icons.zoom_out_map : Icons.zoom_in, size: 20),
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
                  child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('儲存'),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: LayoutBuilder(builder: (c, box) {
              final fit = math.min(1.0, box.maxWidth / canvasW);
              if (fit != _fit) {
                _fit = fit;
                if (!_zoomed) {
                  // 第一次（或寬度變了）：整張圖剛好塞進寬度
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_zoomed) _tc.value = Matrix4.identity()..scaleByDouble(fit, fit, fit, 1);
                  });
                }
              }
              // 排版時用 1:1 的格子（手指才抓得到），畫面高度固定、可以拖著看
              final arrangeScale = math.max(fit, 0.85);
              final viewH = _arranging ? math.min(canvasH * arrangeScale, 460.0) : canvasH * fit;
              _viewSize = Size(box.maxWidth, viewH);
              return SizedBox(
                height: viewH,
                child: InteractiveViewer(
                  transformationController: _tc,
                  constrained: false,
                  minScale: fit,
                  maxScale: 2.5,
                  boundaryMargin: const EdgeInsets.all(8),
                  panEnabled: true,
                  child: SizedBox(
                    width: canvasW,
                    height: canvasH,
                    child: _canvas(tables, states, rows),
                  ),
                ),
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
        Text('點桌子：有客人＝入座、清桌、換桌等；空桌＝登記現場客坐這桌。兩指放大可以看到人名；上方切換時間看之後哪幾桌有訂位。',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.caption, height: 1.5)),
      ],
    ]);
  }

  Widget _canvas(List<ReservationTable> tables, Map<String, _TableState> states, int rows) {
    // 這裡在 LayoutBuilder 裡面建，_fit 已經算好；記下這次畫的是哪一版，縮放跨過門檻才重畫
    _shownDetailed = _detailed;
    double px(int v) => v * (_cell + _gap);
    return Stack(children: [
      // 排版時：每一格都是放置區
      if (_arranging)
        for (var y = 0; y < rows; y++)
          for (var x = 0; x < _cols; x++)
            Positioned(
              left: px(x),
              top: px(y),
              width: _cell,
              height: _cell,
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
                  delay: const Duration(milliseconds: 200),
                  feedback: Transform.scale(
                    scale: math.max(_scale, 0.85),
                    alignment: Alignment.topLeft,
                    child: SizedBox(width: px(t.w) - _gap, height: px(t.h) - _gap, child: _tableCard(t, null, lifted: true)),
                  ),
                  childWhenDragging: Opacity(opacity: 0.25, child: _tableCard(t, null)),
                  child: GestureDetector(onTap: () => _editTable(t), child: _tableCard(t, null)),
                )
              : _tableCard(t, states[t.id]),
        ),
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
              shape: BoxShape.circle,
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

  /// 一張桌：圓（吧台、小圓桌）或方；縮小時只放桌號＋人數（像 iCHEF），放大才放人名、時間
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
    final bg = filled ? accent.withValues(alpha: 0.24) : (seat == _Seat.cleared ? AppColors.muted.withValues(alpha: 0.12) : AppColors.cardHigh);
    final border = _arranging ? AppColors.primary.withValues(alpha: 0.5) : (filled ? accent.withValues(alpha: 0.85) : AppColors.line);
    final secondary = s != null && !s.primary; // 併桌的第二張以後
    final round = t.isRound && t.w == t.h;
    final detailed = _detailed && !_arranging;
    final nameColor = filled ? accent : AppColors.text;

    // 桌號 + 人數（永遠有）
    final head = Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Flexible(
        child: Text(t.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: detailed ? 15 : 19, height: 1, color: nameColor)),
      ),
      const SizedBox(width: 3),
      if (r != null && filled && !secondary)
        Text('${r.party}', style: TextStyle(fontSize: detailed ? 15 : 17, fontWeight: FontWeight.w600, height: 1, color: accent, fontFeatures: tabular))
      else if (secondary)
        Text('併', style: TextStyle(fontSize: 11, height: 1.1, color: accent))
      else
        Text('${t.seats}', style: TextStyle(fontSize: 11, height: 1.1, color: AppColors.muted.withValues(alpha: 0.9), fontFeatures: tabular)),
    ]);

    Widget? sub;
    if (_arranging) {
      sub = Text('${t.seats} 人', style: TextStyle(fontSize: 11, color: AppColors.muted));
    } else if (detailed && r != null && filled) {
      sub = Column(mainAxisSize: MainAxisSize.min, children: [
        Text(secondary ? '併桌' : r.name,
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.2, color: secondary ? AppColors.muted : AppColors.text)),
        Text(
          seat == _Seat.seated ? '${seatedOn(r) != null ? minuteLabel(_minuteOf(seatedOn(r)!)) : r.time} 入座' : '${r.time}${r.walkIn ? ' 現場' : ''}',
          maxLines: 1,
          style: TextStyle(fontSize: 9.5, height: 1.2, color: accent, fontWeight: FontWeight.w600, fontFeatures: tabular),
        ),
      ]);
    } else if (detailed && r != null && seat == _Seat.cleared) {
      sub = Text('剛清桌', style: TextStyle(fontSize: 10, color: AppColors.muted));
    } else if (detailed && s?.next != null) {
      sub = Text('${s!.next!.time} ${s.next!.name}',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: AppColors.muted, fontFeatures: tabular));
    } else if (!detailed && r != null && filled && !secondary) {
      // 縮小時：人名縮成兩個字，看得出是誰
      final n = r.name.trim();
      sub = Text(n.length > 3 ? n.substring(0, 3) : n, maxLines: 1, overflow: TextOverflow.clip,
          style: TextStyle(fontSize: 10.5, height: 1.1, color: AppColors.text.withValues(alpha: 0.85)));
    } else if (!detailed && seat == _Seat.cleared) {
      sub = Icon(Icons.cleaning_services_outlined, size: 11, color: AppColors.muted);
    }

    final card = Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          shape: round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: round ? null : BorderRadius.circular(AppRadius.sm + 2),
          border: Border.all(color: border, width: filled ? 1.5 : 1),
          boxShadow: lifted ? [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 6))] : null,
        ),
        padding: EdgeInsets.symmetric(horizontal: round ? 6 : 5, vertical: 4),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [head, if (sub != null) ...[const SizedBox(height: 3), sub]]),
      ),
    );
    if (_arranging) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
