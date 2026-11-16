import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 班表修改紀錄（0113，老闆店長）：一次修改一張卡片（誰、什麼時候、照片套用／自動排班／手動），
/// 點開看每一格從什麼改成什麼，可以整批還原。之後又被改過的格子要先處理才能還原。
class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen(
      {super.key,
      required this.membership,
      required this.month,
      required this.people});
  final Membership membership;
  final DateTime month;
  final List<ShiftPerson> people;
  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  late Future<List<ShiftChange>> _future;
  bool _started = false;
  bool _busy = false;
  bool _changed = false;

  Repository get _repo => AppScope.of(context).repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _future =
          _repo.shiftChangeHistory(widget.membership.storeId, widget.month);
    }
  }

  void _reload() => setState(() => _future =
      _repo.shiftChangeHistory(widget.membership.storeId, widget.month));

  String _name(String id) =>
      widget.people.where((p) => p.id == id).firstOrNull?.name ?? '（已移除的人）';

  static String sourceLabel(String s) => switch (s) {
        'photo' => '照片套用',
        'plan' => '自動排班公布',
        'undo' => '還原',
        _ => '手動修改',
      };

  Future<void> _undo(List<ShiftChange> g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('還原這次修改（${g.length} 格）？'),
        content: const Text('會把這幾格改回修改前的樣子。\n\n只還原班表格子；備註、統計數字、照片套用時新增的人員不會還原。'
            '這幾格之後如果又被改過，就不能整批還原。還原也會留紀錄，可以再還原回去。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('還原')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await _repo.undoShiftChange(
          widget.membership.storeId, g.first.changeId);
      if (!mounted) return;
      _changed = true;
      showMessage(context, '已還原 $n 格');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final md = DateFormat('M/d', 'zh_TW');
    final when = DateFormat('M/d HH:mm', 'zh_TW');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // 還原還在送的時候不能離開，不然班表頁不會重新整理（Codex P2）
        if (!didPop && !_busy) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${widget.month.month} 月班表修改紀錄')),
        body: FutureBuilder<List<ShiftChange>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError)
              return ErrorView(
                  message: friendlyError(snap.error!), onRetry: _reload);
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());
            // 依「一次修改」分組，最新的在前面
            final groups = <String, List<ShiftChange>>{};
            for (final c in snap.data!) {
              groups.putIfAbsent(c.changeId, () => []).add(c);
            }
            final list = groups.values.toList()
              ..sort((a, b) => b.first.at.compareTo(a.first.at));
            return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text('每一次修改一張卡片，點開看改了哪幾格。這個功能上線以前的修改沒有紀錄。',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: AppType.small)),
                  const SizedBox(height: 8),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('這個月還沒有修改紀錄',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted)),
                    ),
                  for (final g in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SectionCard(
                        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                        child: Theme(
                          data: Theme.of(context)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                                '${sourceLabel(g.first.source)}・${g.length} 格',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '${when.format(toTaipei(g.first.at))}・${g.first.actorName ?? '後臺'}',
                                style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: AppType.small)),
                            children: [
                              for (final c in (g.toList()
                                    ..sort((a, b) {
                                      final x =
                                          a.workDate.compareTo(b.workDate);
                                      return x != 0
                                          ? x
                                          : _name(a.personId)
                                              .compareTo(_name(b.personId));
                                    }))
                                  .take(200))
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(children: [
                                    SizedBox(
                                        width: 48,
                                        child: Text(md.format(c.workDate),
                                            style: const TextStyle(
                                                fontSize: AppType.small))),
                                    Expanded(
                                        child: Text(_name(c.personId),
                                            style: const TextStyle(
                                                fontSize: AppType.small))),
                                    Text(
                                        '${c.before ?? '空白'} → ${c.after ?? '空白'}',
                                        style: const TextStyle(
                                            fontSize: AppType.small,
                                            fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                              if (g.length > 200)
                                Text('…還有 ${g.length - 200} 格',
                                    style: TextStyle(
                                        color: AppColors.muted,
                                        fontSize: AppType.small)),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _busy ? null : () => _undo(g),
                                  icon: const Icon(Icons.undo, size: 18),
                                  label: const Text('還原這次修改'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ]);
          },
        ),
      ),
    );
  }
}
