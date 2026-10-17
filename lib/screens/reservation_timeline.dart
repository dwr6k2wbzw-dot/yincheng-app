import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 訂位時間軸（0061，老闆 2026-10-17，參考 inline）：每張桌一列、橫向是時間，每組訂位一條色塊。
/// 沒入座的訂位佔到入座為止（同一桌下一組開始前），入座後佔到清桌為止（老闆選「不限，直到清桌」）。
/// 點色塊＝訂位動作；點空白處＝登記現場客（帶入那張桌）。
class ReservationTimeline extends StatefulWidget {
  const ReservationTimeline({
    super.key,
    required this.day,
    required this.isToday,
    required this.list,
    required this.tables,
    required this.slots,
    required this.onTapReservation,
    required this.onTapEmpty,
  });
  final DateTime day;
  final bool isToday;
  final List<Reservation> list;
  final List<ReservationTable> tables;
  final List<String> slots;
  final void Function(Reservation r) onTapReservation;
  final void Function(ReservationTable? table, int minute) onTapEmpty;

  @override
  State<ReservationTimeline> createState() => _ReservationTimelineState();
}

/// 時間軸上的一段（一組訂位在一張桌上）
class _Block {
  _Block(this.r, this.start, this.end, {this.conflict = false});
  final Reservation r;
  final int start; // 營業日的分鐘數（凌晨 0～6 點算 24～30 點）
  int end;
  bool conflict;
}

const _hourW = 104.0;
const _rowH = 58.0;
const _labelW = 74.0;
const _headH = 44.0;

/// 營業日的分鐘數：凌晨 6 點前算前一天（加 24 小時）
int bizMinute(int m) => m < 360 ? m + 1440 : m;

/// 這個時間是不是在這個營業日（凌晨 6 點前算前一天）
bool onBizDay(DateTime t, DateTime day) {
  final s = t.toLocal().subtract(const Duration(hours: 6));
  return s.year == day.year && s.month == day.month && s.day == day.day;
}

/// 入座／清桌時間只在同一個營業日才拿來畫（補登別天的到店，時間是補登當下，不能拿來畫；Codex 審查）
DateTime? seatedOn(Reservation r) => r.seatedAt != null && onBizDay(r.seatedAt!, r.date) ? r.seatedAt : null;
DateTime? clearedOn(Reservation r) => r.clearedAt != null && onBizDay(r.clearedAt!, r.date) ? r.clearedAt : null;

String minuteLabel(int m) {
  final x = m % 1440;
  return '${(x ~/ 60).toString().padLeft(2, '0')}:${(x % 60).toString().padLeft(2, '0')}';
}

class _ReservationTimelineState extends State<ReservationTimeline> {
  ScrollController? _h;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 今天：每分鐘重畫一次（現在時間的紅線、未清桌的色塊）
    if (widget.isToday) _tick = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _h?.dispose();
    super.dispose();
  }

  int get _now {
    final n = DateTime.now();
    return bizMinute(n.hour * 60 + n.minute);
  }

  int _minuteOf(DateTime t) {
    final l = t.toLocal();
    // 跟營業日比：隔天凌晨的時間算 24 點以後
    final d = DateTime(l.year, l.month, l.day);
    final m = l.hour * 60 + l.minute;
    if (d.isAfter(widget.day)) return m + 1440 * d.difference(widget.day).inDays;
    return bizMinute(m);
  }

  int _startOf(Reservation r) => seatedOn(r) != null ? _minuteOf(seatedOn(r)!) : bizMinute(minutesOf(r.time));

  @override
  Widget build(BuildContext context) {
    final shown = widget.list.where((r) => r.active).toList();
    final slotMins = [for (final s in widget.slots) bizMinute(minutesOf(s))];
    var from = slotMins.isEmpty ? 18 * 60 : slotMins.reduce((a, b) => a < b ? a : b);
    var to = slotMins.isEmpty ? 26 * 60 : slotMins.reduce((a, b) => a > b ? a : b) + 180;
    for (final r in shown) {
      final s = _startOf(r);
      if (s < from) from = s;
      if (clearedOn(r) != null && _minuteOf(clearedOn(r)!) > to) to = _minuteOf(clearedOn(r)!);
      if (s + 120 > to) to = s + 120;
    }
    if (widget.isToday && _now + 60 > to) to = _now + 60;
    final startH = (from ~/ 60) - (from % 60 == 0 ? 1 : 0);
    final endH = ((to + 59) ~/ 60).clamp(startH + 4, 31);
    final t0 = startH * 60, t1 = endH * 60;
    double x(int m) => (m - t0) / 60 * _hourW;
    final width = (endH - startH) * _hourW;

    // 每張桌的色塊
    final tables = [
      ...widget.tables.where((t) => t.active),
      // 停用的桌如果這天還有訂位，也列出來
      ...widget.tables.where((t) => !t.active && shown.any((r) => r.tableIds.contains(t.id))),
    ];
    final known = {for (final t in widget.tables) t.id};
    final byTable = <String, List<_Block>>{};
    final unassigned = <_Block>[];
    _Block mk(Reservation r) {
      final s = _startOf(r);
      final e = clearedOn(r) != null ? _minuteOf(clearedOn(r)!) : (r.clearedAt != null ? s + 120 : t1);
      return _Block(r, s, e < s + 10 ? s + 10 : e);
    }

    for (final r in shown) {
      final ids = r.tableIds.where(known.contains).toList();
      if (ids.isEmpty) {
        unassigned.add(mk(r));
      } else {
        for (final id in ids) {
          byTable.putIfAbsent(id, () => []).add(mk(r));
        }
      }
    }
    for (final bs in byTable.values) {
      bs.sort((a, b) => a.start.compareTo(b.start));
      var occupied = -1; // 前面已入座的組最晚佔到幾點（還沒清桌就到最右邊）
      for (var i = 0; i < bs.length; i++) {
        final b = bs[i];
        if (occupied > b.start) b.conflict = true; // 前面有一組還沒清桌（Codex 審查：往後每一組都要標）
        if (b.r.seatedAt != null) {
          if (b.end > occupied) occupied = b.end;
        } else if (i + 1 < bs.length && b.end > bs[i + 1].start) {
          b.end = bs[i + 1].start; // 還沒入座：畫到下一組開始
        }
      }
    }
    // 未排桌：同時段的排成好幾列
    final lanes = <List<_Block>>[];
    unassigned.sort((a, b) => a.start.compareTo(b.start));
    for (final b in unassigned) {
      if (b.r.clearedAt == null) b.end = b.start + 120 < t1 ? b.start + 120 : (t1 > b.start + 30 ? t1 : b.start + 30);
      final lane = lanes.firstWhere((l) => l.last.end <= b.start, orElse: () {
        final l = <_Block>[];
        lanes.add(l);
        return l;
      });
      lane.add(b);
    }

    // 每個整點在店裡（或預計在店裡）的人數
    int guestsAt(int m) {
      final seen = <String>{};
      var n = 0;
      for (final bs in [...byTable.values, unassigned]) {
        for (final b in bs) {
          if (b.start <= m && m < b.end && seen.add(b.r.id)) n += b.r.party;
        }
      }
      return n;
    }

    _h ??= ScrollController(
        initialScrollOffset: widget.isToday ? (x(_now) - 120).clamp(0, double.infinity).toDouble() : 0);

    Widget label(String a, String b, {Color? color}) => Container(
          height: _rowH,
          width: _labelW,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 0.6))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a, style: TextStyle(fontWeight: FontWeight.w700, color: color), overflow: TextOverflow.ellipsis),
            if (b.isNotEmpty) Text(b, style: TextStyle(fontSize: 10, color: AppColors.muted), overflow: TextOverflow.ellipsis),
          ]),
        );

    Widget row(List<_Block> blocks, ReservationTable? table) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final m = t0 + (d.localPosition.dx / _hourW * 60).round();
            widget.onTapEmpty(table, m);
          },
          child: Container(
            height: _rowH,
            width: width,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line, width: 0.6))),
            child: Stack(children: [
              for (var h = startH; h < endH; h++)
                Positioned(left: x(h * 60), top: 0, bottom: 0, child: Container(width: 0.6, color: AppColors.line)),
              for (final b in blocks)
                Positioned(
                  left: x(b.start) + 1,
                  width: (x(b.end) - x(b.start) - 2).clamp(36, width).toDouble(),
                  top: 3,
                  bottom: 3,
                  child: _blockView(b),
                ),
            ]),
          ),
        );

    final rows = <(Widget, Widget)>[
      for (var i = 0; i < lanes.length; i++)
        (label(i == 0 ? '未排桌' : '', i == 0 ? '點一下排桌' : '', color: AppColors.warn), row(lanes[i], null)),
      for (final t in tables)
        (label(t.name, '${t.seats} 人${t.combinable ? '・可併' : ''}${t.active ? '' : '・停用'}'), row(byTable[t.id] ?? const [], t)),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (tables.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('還沒有設定桌位：老闆或店長按右上角「桌位設定」新增桌子。', style: TextStyle(color: AppColors.warn, fontSize: 13)),
        ),
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            SizedBox(height: _headH, width: _labelW),
            for (final r in rows) r.$1,
          ]),
          Expanded(
            child: SingleChildScrollView(
              controller: _h,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Stack(children: [
                  Column(children: [
                    SizedBox(
                      height: _headH,
                      child: Stack(children: [
                        for (var h = startH; h < endH; h++)
                          Positioned(
                            left: x(h * 60) + 6,
                            top: 6,
                            child: Row(children: [
                              Text(minuteLabel(h * 60), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular)),
                              const SizedBox(width: 6),
                              Icon(Icons.person, size: 12, color: AppColors.muted),
                              Text('${guestsAt(h * 60)}', style: TextStyle(fontSize: 11, color: AppColors.muted, fontFeatures: tabular)),
                            ]),
                          ),
                      ]),
                    ),
                    for (final r in rows) r.$2,
                  ]),
                  if (widget.isToday && _now >= t0 && _now <= t1)
                    Positioned(
                      left: x(_now) - 1,
                      top: _headH - 14,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Column(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            color: AppColors.bad,
                            child: Text(minuteLabel(_now), style: const TextStyle(fontSize: 10, color: Colors.white)),
                          ),
                          Expanded(child: Container(width: 2, color: AppColors.bad)),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Text('點色塊：入座、清桌、排桌等；點空白處：登記現場客。沒入座的訂位佔到入座為止，入座後佔到清桌為止。紅框＝前一組還沒清桌。',
          style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5)),
    ]);
  }

  Widget _blockView(_Block b) {
    final r = b.r;
    final cleared = r.clearedAt != null;
    final seated = r.seatedAt != null && !cleared;
    final base = cleared ? AppColors.muted : (seated ? AppColors.good : AppColors.primary);
    final tag = r.walkIn ? '現場' : (r.source == 'web' ? '網路' : '電話');
    return GestureDetector(
      onTap: () => widget.onTapReservation(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: base.withValues(alpha: cleared ? 0.12 : 0.22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: b.conflict ? AppColors.bad : base.withValues(alpha: 0.7), width: b.conflict ? 2 : 1),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                '$tag ${r.time}${seatedOn(r) != null ? '・${minuteLabel(_minuteOf(seatedOn(r)!))}入座' : ''}${cleared ? '・已清桌' : ''}',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(fontSize: 10, color: base, fontWeight: FontWeight.w600),
              ),
              Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cleared ? AppColors.muted : null)),
            ]),
          ),
          Text('${r.party}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cleared ? AppColors.muted : null)),
        ]),
      ),
    );
  }
}

/// 選桌（0061）：勾選一張或多張（併桌）；忙碌中的桌會標出來；「自動選桌」挑最合適的空桌
Future<List<String>?> pickTables(BuildContext context,
    {required List<ReservationTable> tables, required List<String> selected, required int party, required Set<String> busy}) {
  final sel = {...selected};
  final act = tables.where((t) => t.active || selected.contains(t.id)).toList();
  List<String> auto() {
    final free = act.where((t) => t.active && !busy.contains(t.id)).toList();
    final single = free.where((t) => t.seats >= party).toList()..sort((a, b) => a.seats.compareTo(b.seats));
    if (single.isNotEmpty) return [single.first.id];
    // 可併的桌照順序併到夠坐
    final comb = free.where((t) => t.combinable).toList();
    final out = <String>[];
    var seats = 0;
    for (final t in comb) {
      out.add(t.id);
      seats += t.seats;
      if (seats >= party) return out;
    }
    return const [];
  }

  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.card,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final seats = act.where((t) => sel.contains(t.id)).fold<int>(0, (s, t) => s + t.seats);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(
                  child: Text('排桌・$party 位（已選 ${sel.length} 桌、$seats 個位子）',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () {
                    final a = auto();
                    if (a.isEmpty) {
                      showMessage(c, '找不到夠坐的空桌，請自己選', error: true);
                      return;
                    }
                    set(() => sel
                      ..clear()
                      ..addAll(a));
                  },
                  child: const Text('自動選桌'),
                ),
              ]),
            ),
            Flexible(
              child: act.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('還沒有設定桌位', style: TextStyle(color: AppColors.muted)),
                    )
                  : ListView(shrinkWrap: true, children: [
                      for (final t in act)
                        CheckboxListTile(
                          dense: true,
                          value: sel.contains(t.id),
                          onChanged: (v) => set(() => v == true ? sel.add(t.id) : sel.remove(t.id)),
                          title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            '${t.seats} 人',
                            if (t.combinable) '可併',
                            if (busy.contains(t.id)) '這時段有人',
                            if (!t.active) '已停用',
                          ].join('・'),
                              style: TextStyle(fontSize: 12, color: busy.contains(t.id) ? AppColors.warn : AppColors.muted)),
                        ),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                TextButton(onPressed: () => set(sel.clear), child: const Text('全部取消')),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(c, [for (final t in act) if (sel.contains(t.id)) t.id]),
                  child: const Text('儲存'),
                ),
              ]),
            ),
          ]),
        ),
      );
    }),
  );
}

/// 這組訂位的時段裡，哪些桌已經有別組（還沒清桌）
Set<String> busyTables(List<Reservation> all, Reservation? me, int minute) {
  final out = <String>{};
  for (final r in all) {
    if (me != null && r.id == me.id) continue;
    if (!r.active || r.clearedAt != null) continue;
    final seat = seatedOn(r);
    final s = seat != null ? bizMinute(seat.toLocal().hour * 60 + seat.toLocal().minute) : bizMinute(minutesOf(r.time));
    // 已入座：從入座到清桌都算忙；還沒入座：前後 2 小時內算忙
    final busy = r.seatedAt != null ? s <= minute + 120 : (s - minute).abs() < 120;
    if (busy) out.addAll(r.tableIds);
  }
  return out;
}

/// 桌位設定（0061）：老闆／店長新增、修改、停用（不能刪除）
class ReservationTablesScreen extends StatefulWidget {
  const ReservationTablesScreen({super.key, required this.storeId, required this.storeName});
  final String storeId;
  final String storeName;
  @override
  State<ReservationTablesScreen> createState() => _ReservationTablesScreenState();
}

class _ReservationTablesScreenState extends State<ReservationTablesScreen> {
  Future<List<ReservationTable>>? _future;
  bool _changed = false;

  Repository get _repo => AppScope.of(context).repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _repo.reservationTables(widget.storeId);
  }

  void _reload() => setState(() => _future = _repo.reservationTables(widget.storeId));

  Future<void> _edit(ReservationTable? t, int nextSort) async {
    final name = TextEditingController(text: t?.name ?? '');
    final seats = TextEditingController(text: '${t?.seats ?? 2}');
    final sort = TextEditingController(text: '${t?.sort ?? nextSort}');
    var comb = t?.combinable ?? false;
    var active = t?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(t == null ? '新增桌位' : '修改桌位'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, maxLength: 12, autofocus: t == null, decoration: const InputDecoration(labelText: '桌號（例：A1、吧台1）')),
              TextField(controller: seats, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '最多坐幾位')),
              TextField(controller: sort, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '排序（數字小的排上面）')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: comb,
                onChanged: (v) => set(() => comb = v),
                title: const Text('可以跟旁邊的桌子併桌'),
              ),
              if (t != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (v) => set(() => active = v),
                  title: const Text('使用中'),
                  subtitle: const Text('關掉＝停用（不會出現在時間軸，舊的訂位紀錄保留）', style: TextStyle(fontSize: 12)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('儲存')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final n = int.tryParse(seats.text.trim());
    final so = int.tryParse(sort.text.trim()) ?? 0;
    if (name.text.trim().isEmpty || n == null || n < 1 || n > 50) {
      showMessage(context, '請填桌號，人數 1～50', error: true);
      return;
    }
    try {
      await _repo.saveReservationTable(widget.storeId,
          ReservationTable(id: t?.id ?? '', name: name.text.trim(), seats: n, combinable: comb, sort: so, active: active));
      _changed = true;
      if (mounted) showMessage(context, '已儲存');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).pop(_changed);
        },
        child: Scaffold(
          appBar: AppBar(title: Text('桌位設定・${widget.storeName}')),
          body: FutureBuilder<List<ReservationTable>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!;
              final next = list.isEmpty ? 1 : list.map((t) => t.sort).reduce((a, b) => a > b ? a : b) + 1;
              return Scaffold(
                floatingActionButton: FloatingActionButton.extended(
                  onPressed: () => _edit(null, next),
                  icon: const Icon(Icons.add),
                  label: const Text('新增桌位'),
                ),
                body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                  Text('時間軸照這裡的順序排。停用的桌子不會出現在時間軸，舊訂位紀錄保留。',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  SectionCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (final t in list)
                        ListTile(
                          onTap: () => _edit(t, next),
                          title: Text(t.name,
                              style: TextStyle(fontWeight: FontWeight.w700, color: t.active ? null : AppColors.muted)),
                          subtitle: Text(['${t.seats} 人', if (t.combinable) '可併桌', if (!t.active) '已停用', '排序 ${t.sort}'].join('・'),
                              style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                    ]),
                  ),
                ]),
              );
            },
          ),
        ),
      );
}
