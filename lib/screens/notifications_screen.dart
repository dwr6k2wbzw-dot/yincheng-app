import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/app_update.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'handover_screen.dart';
import 'reservations_screen.dart';

/// 標題列的小鈴鐺（老闆 2026-10-12）：新交接、新提醒、班表修改、App 有新版本時顯示紅色數字。
/// 打開 App、回到 App、之後每 2 分鐘檢查一次。自己做的事不提醒自己。
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, required this.membership, this.onOpenSchedule});
  final Membership membership;
  final VoidCallback? onOpenSchedule; // 點班表通知 → 切到班表分頁
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with WidgetsBindingObserver {
  NotificationFeed? _feed;
  bool _update = false;
  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final repo = AppScope.of(context).repo;
    final r = await Future.wait<dynamic>([
      repo.notifications(widget.membership.storeId).then<NotificationFeed?>((f) => f, onError: (_) => null),
      checkAppUpdate(),
    ]);
    if (!mounted) return;
    setState(() {
      _feed = (r[0] as NotificationFeed?) ?? _feed;
      _update = r[1] as bool;
    });
  }

  Future<void> _open() async {
    final action = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => NotificationsScreen(membership: widget.membership, update: _update),
    ));
    if (action == 'schedule') widget.onOpenSchedule?.call();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final n = (_feed?.unreadCount ?? 0) + (_update ? 1 : 0);
    return IconButton(
      tooltip: '通知',
      onPressed: _open,
      icon: Badge(
        isLabelVisible: n > 0,
        backgroundColor: AppColors.bad,
        label: Text(n > 9 ? '9+' : '$n'),
        child: Icon(n > 0 ? Icons.notifications : Icons.notifications_outlined),
      ),
    );
  }
}

/// 通知清單：最上面是「有新版本」，其下依時間排列；打開即全部標為已讀（未讀的這次仍標示）
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.membership, required this.update});
  final Membership membership;
  final bool update;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<NotificationFeed> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _future = _load();
    }
  }

  Future<NotificationFeed> _load() async {
    final repo = AppScope.of(context).repo;
    final f = await repo.notifications(widget.membership.storeId);
    // 看過就標已讀；失敗（例如沒網路）不影響顯示
    repo.markNotificationsSeen(widget.membership.storeId).catchError((_) {});
    return f;
  }

  void _tap(AppNotification n) {
    switch (n.kind) {
      case 'handover':
      case 'reminder':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HandoverScreen(membership: widget.membership, initialTab: n.kind == 'reminder' ? 1 : 0),
        ));
      case 'schedule':
        Navigator.of(context).pop('schedule');
      case 'reservation':
        // 改人數申請（0056）：直接打開那一天的訂位
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReservationsScreen(membership: widget.membership, initialDay: n.refMonth),
        ));
    }
  }

  static IconData _icon(String kind) => switch (kind) {
        'handover' => Icons.edit_note,
        'reminder' => Icons.alarm,
        'schedule' => Icons.calendar_month_outlined,
        'reservation' => Icons.event_seat_outlined,
        _ => Icons.notifications_outlined,
      };

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '剛剛';
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘前';
    if (d.inHours < 24) return '${d.inHours} 小時前';
    return DateFormat('M/d HH:mm').format(t);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('通知')),
        body: FutureBuilder<NotificationFeed>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load()));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final f = snap.data!;
            return RefreshIndicator(
              onRefresh: () async => setState(() => _future = _load()),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                if (widget.update) ...[
                  SectionCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(Icons.system_update, color: AppColors.primary),
                      title: const Text('App 有新版本', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('點這裡更新到最新版'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: reloadApp,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (f.items.isEmpty && !widget.update)
                  Padding(
                    padding: EdgeInsets.only(top: 64),
                    child: Text('最近 30 天沒有新通知', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                  ),
                if (f.items.isNotEmpty)
                  SectionCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (final n in f.items)
                        ListTile(
                          leading: Icon(_icon(n.kind), color: f.isUnread(n) ? AppColors.primary : AppColors.muted),
                          title: Text(
                            n.actorName.isEmpty ? n.title : '${n.title}・${n.actorName}',
                            style: TextStyle(fontWeight: f.isUnread(n) ? FontWeight.w700 : FontWeight.w400),
                          ),
                          subtitle: Text(
                            [if ((n.body ?? '').isNotEmpty) n.body!, _when(n.createdAt)].join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: f.isUnread(n)
                              ? Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: AppColors.bad, shape: BoxShape.circle))
                              : null,
                          onTap: () => _tap(n),
                        ),
                    ]),
                  ),
                const SizedBox(height: 12),
                Text('有人新增交接、新增提醒、修改班表，或 App 有新版本時會通知；自己做的不會通知自己。',
                    style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5)),
              ]),
            );
          },
        ),
      );
}
