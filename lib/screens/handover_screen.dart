import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/slip_scan.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 總覽最上面的小卡：「今天有 N 件提醒、M 則交接未讀」，點了進入交接・提醒頁
class HandoverSummaryCard extends StatefulWidget {
  const HandoverSummaryCard({super.key, required this.membership});
  final Membership membership;
  @override
  State<HandoverSummaryCard> createState() => _HandoverSummaryCardState();
}

class _HandoverSummaryCardState extends State<HandoverSummaryCard> {
  Future<HandoverBoard>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<HandoverBoard> _load() => AppScope.of(context).repo.handoverBoard(widget.membership.storeId);

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => HandoverScreen(membership: widget.membership)));
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HandoverBoard>(
        future: _future,
        builder: (context, snap) {
          final me = AppScope.of(context).repo.currentUserId;
          final b = snap.data;
          final pending = b?.pendingCount(bizToday()) ?? 0;
          final unread = b?.unreadCount(me) ?? 0;
          final open = b?.notes.where((n) => !n.resolved).length ?? 0;
          final urgent = pending > 0 || unread > 0;
          final String text;
          if (snap.hasError) {
            text = '交接・提醒（讀取失敗，點一下重試）';
          } else if (b == null) {
            text = '交接・提醒';
          } else if (!urgent) {
            text = open > 0 ? '今天的提醒都做完了・$open 則交接處理中' : '今天的提醒都做完了，沒有新的交接';
          } else {
            text = [
              if (pending > 0) '今天有 $pending 件提醒',
              if (unread > 0) '$unread 則交接未讀',
            ].join('、');
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: urgent ? AppColors.warn.withValues(alpha: 0.18) : AppColors.card,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _open,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Icon(urgent ? Icons.notifications_active : Icons.checklist,
                        color: urgent ? AppColors.warn : AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(text,
                          style: TextStyle(fontWeight: urgent ? FontWeight.w700 : FontWeight.w500, fontSize: 15)),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

/// 交接・提醒頁：兩個分頁「交接」「提醒」
class HandoverScreen extends StatefulWidget {
  const HandoverScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends State<HandoverScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<HandoverBoard> _future;
  HandoverBoard? _board;
  bool _started = false;
  final _seen = <String>{};

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  bool get _canManage => widget.membership.isManager;
  String? get _me => _repo.currentUserId;
  bool get _hasSchedule => AppConfig.scheduleStores.contains(widget.membership.storeName);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _future = _load();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<HandoverBoard> _load() async {
    final b = await _repo.handoverBoard(_store, withSchedule: _hasSchedule);
    if (mounted) setState(() => _board = b); // 標題的未讀／待辦數字一起更新
    // 打開就算讀過（只標一次；失敗不影響畫面）
    final ids = b.notes.where((n) => n.unreadFor(_me) && !_seen.contains(n.id)).map((n) => n.id).toList();
    _seen.addAll(ids);
    _repo.markHandoverRead(_store, ids).catchError((_) {});
    return b;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    try {
      await f();
      if (ok != null && mounted) showMessage(context, ok);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  // ---------------- 交接 ----------------
  Future<void> _writeHandover() async {
    final body = TextEditingController();
    String? photo;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('寫交接', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: body,
              autofocus: true,
              maxLines: 6,
              minLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(hintText: '例：冰塊機漏水，已叫修，明天下午師傅來', border: OutlineInputBorder()),
            ),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final p = await pickSlipImage();
                    if (p != null) set(() => photo = p);
                  } catch (e) {
                    if (c.mounted) showMessage(c, '照片讀取失敗：$e', error: true);
                  }
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(photo == null ? '附照片' : '換照片'),
              ),
              if (photo != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle, color: AppColors.good, size: 18),
                const Text(' 已附照片', style: TextStyle(fontSize: 13)),
                IconButton(onPressed: () => set(() => photo = null), icon: const Icon(Icons.close, size: 18)),
              ],
              const Spacer(),
              FilledButton(
                onPressed: () {
                  if (body.text.trim().isEmpty) return;
                  Navigator.pop(c, true);
                },
                child: const Text('送出'),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    await _run(() => _repo.addHandover(_store, body.text.trim(), photo == null ? null : dataUrlBytes(photo!)),
        ok: '已送出交接');
  }

  Future<void> _showPhoto(String path) async {
    try {
      final url = await _repo.shiftPhotoUrl(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          insetPadding: const EdgeInsets.all(8),
          child: InteractiveViewer(maxScale: 5, child: Image.network(url, fit: BoxFit.contain)),
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteHandover(HandoverNote n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('刪除這則交接？'),
        content: Text(n.body, maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok == true) await _run(() => _repo.deleteHandover(n.id), ok: '已刪除');
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? '今天 ${DateFormat('HH:mm').format(t)}' : DateFormat('M/d（E）HH:mm', 'zh_TW').format(t);
  }

  Widget _noteCard(HandoverNote n) {
    final readers = n.readers.entries.where((e) => e.key != n.authorId).map((e) => e.value).where((x) => x.isNotEmpty).toList();
    final isNew = n.unreadFor(_me) || (_seen.contains(n.id) && !n.resolved);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (isNew)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.warn, borderRadius: BorderRadius.circular(6)),
                child: const Text('新', style: TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w700)),
              ),
            Text(n.authorName.isEmpty ? '—' : n.authorName, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(child: Text(_when(n.createdAt), style: const TextStyle(color: AppColors.muted, fontSize: 12))),
            if (_canManage)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '刪除',
                onPressed: () => _deleteHandover(n),
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.muted),
              ),
          ]),
          const SizedBox(height: 6),
          SelectableText(n.body, style: TextStyle(fontSize: 15, height: 1.5, color: n.resolved ? AppColors.muted : null)),
          if (n.photoPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                onPressed: () => _showPhoto(n.photoPath!),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('看照片'),
              ),
            ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Text(
                [
                  if (readers.isNotEmpty) '已讀：${readers.join('、')}',
                  if (n.resolved) '✓ ${n.resolvedName ?? ''} 已處理（${_when(n.resolvedAt!)}）',
                ].join('\n'),
                style: TextStyle(color: n.resolved ? AppColors.good : AppColors.muted, fontSize: 12, height: 1.5),
              ),
            ),
            n.resolved
                ? TextButton(onPressed: () => _run(() => _repo.setHandoverResolved(n.id, false)), child: const Text('改回未處理'))
                : FilledButton.tonal(
                    onPressed: () => _run(() => _repo.setHandoverResolved(n.id, true), ok: '已標成處理完'),
                    child: const Text('已處理'),
                  ),
          ]),
        ]),
      ),
    );
  }

  Widget _handoverTab(HandoverBoard b) {
    final open = b.notes.where((n) => !n.resolved).toList();
    final done = b.notes.where((n) => n.resolved).toList();
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        if (open.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('目前沒有待處理的交接', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ),
        for (final n in open) _noteCard(n),
        if (done.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('已處理（${done.length}）', style: const TextStyle(color: AppColors.muted)),
              children: [for (final n in done) _noteCard(n)],
            ),
          ),
        const SizedBox(height: 8),
        const Text('大家都能寫交接、標已處理；打開這頁就會記錄你已讀。刪除只有老闆或店長可以。',
            style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5)),
      ]),
    );
  }

  // ---------------- 提醒 ----------------
  String _assignee(WorkReminder r, HandoverBoard b) {
    if (r.assignOnShift) {
      if (!_hasSchedule) return '當天上班的人';
      final on = b.people.where((p) => p.active && ShiftMonth.isOn(b.todayMarks[p.id])).map((p) => p.name).toList();
      return '當天上班的人${on.isEmpty ? '' : '（${on.join('、')}）'}';
    }
    if (r.assignPersonId != null) {
      for (final p in b.people) {
        if (p.id == r.assignPersonId) return p.name;
      }
      return '指定人員';
    }
    return '';
  }

  Future<void> _toggleDone(WorkReminder r, DateTime occ, ReminderDone? dn) async {
    if (dn == null) {
      await _run(() => _repo.setReminderDone(_store, r.id, occ, true));
      return;
    }
    if (dn.doneBy != _me && !_canManage) {
      showMessage(context, '這是 ${dn.doneName} 打的勾，只有本人或老闆、店長能取消');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('取消打勾？'),
        content: Text('「${r.title}」會變回還沒做'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('不用')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('取消打勾')),
        ],
      ),
    );
    if (ok == true) await _run(() => _repo.setReminderDone(_store, r.id, occ, false));
  }

  Widget _todayTile(HandoverBoard b, WorkReminder r, DateTime occ, ReminderDone? dn, DateTime today) {
    final overdue = dn == null && occ.isBefore(today);
    final who = _assignee(r, b);
    final sub = [
      r.repeatLabel,
      if (who.isNotEmpty) '給：$who',
      if (overdue) '${occ.month}/${occ.day}（${WorkReminder.weekdayNames[occ.weekday % 7]}）那次還沒做',
      if (dn != null) '✓ ${dn.doneName} ${DateFormat('HH:mm').format(dn.doneAt)} 完成',
    ].join('・');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: overdue ? AppColors.bad.withValues(alpha: 0.16) : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _toggleDone(r, occ, dn),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(dn != null ? Icons.check_box : Icons.check_box_outline_blank,
                  color: dn != null ? AppColors.good : (overdue ? AppColors.bad : AppColors.muted), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: dn != null ? AppColors.muted : (overdue ? AppColors.bad : null),
                          decoration: dn != null ? TextDecoration.lineThrough : null)),
                  if (r.detail != null && r.detail!.isNotEmpty)
                    Text(r.detail!, style: const TextStyle(fontSize: 13, height: 1.4)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12, color: overdue ? AppColors.bad : (dn != null ? AppColors.good : AppColors.muted))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _reminderTab(HandoverBoard b) {
    final today = bizToday();
    final items = b.todayItems(today);
    final all = [...b.reminders]..sort((a, c) => (a.active == c.active ? 0 : (a.active ? -1 : 1)));
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        Text('今天 ${DateFormat('M/d（E）', 'zh_TW').format(today)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('今天沒有提醒', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ),
        for (final (r, occ, dn) in items) _todayTile(b, r, occ, dn, today),
        const SizedBox(height: 4),
        const Text('點一下打勾；做完的會記錄是誰、幾點做的。凌晨 6 點前還算前一天。',
            style: TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 20),
        if (all.isNotEmpty) ...[
          const Text('全部提醒', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final r in all)
                ListTile(
                  title: Text(r.title, style: TextStyle(color: r.active ? null : AppColors.muted)),
                  subtitle: Text(
                    [
                      r.repeatLabel,
                      if (_assignee(r, b).isNotEmpty) '給：${_assignee(r, b)}',
                      if (!r.active) '已暫停',
                      if (r.active && r.nextOccurrence(today) != null && r.repeat != 'daily')
                        '下次 ${DateFormat('M/d（E）', 'zh_TW').format(r.nextOccurrence(today)!)}',
                    ].join('・'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: _canManage ? const Icon(Icons.edit_outlined, size: 18) : null,
                  onTap: _canManage ? () => _editReminder(r, b) : null,
                ),
            ]),
          ),
        ],
        if (!_canManage)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('提醒由老闆或店長建立。', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
      ]),
    );
  }

  Future<void> _editReminder(WorkReminder? r, HandoverBoard b) async {
    final title = TextEditingController(text: r?.title ?? '');
    final detail = TextEditingController(text: r?.detail ?? '');
    var repeat = r?.repeat ?? 'daily';
    var due = r?.dueDate ?? bizToday();
    var weekday = r?.weekday ?? 1;
    var monthDay = r?.monthDay ?? 1;
    // 指派：'' 不指定、'shift' 當天上班的人、其他＝班表人員 id
    var assign = r == null ? '' : (r.assignOnShift ? 'shift' : (r.assignPersonId ?? ''));
    var active = r?.active ?? true;
    final people = b.people.where((p) => p.active || p.id == r?.assignPersonId).toList();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(r == null ? '新增提醒' : '修改提醒', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: title,
                maxLength: 60,
                decoration: const InputDecoration(labelText: '要做什麼', hintText: '例：跟大倉捷叫貨'),
              ),
              TextField(
                controller: detail,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(labelText: '說明（選填）'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'once', label: Text('一次')),
                  ButtonSegment(value: 'daily', label: Text('每天')),
                  ButtonSegment(value: 'weekly', label: Text('每週')),
                  ButtonSegment(value: 'monthly', label: Text('每月')),
                ],
                selected: {repeat},
                onSelectionChanged: (v) => set(() => repeat = v.first),
              ),
              const SizedBox(height: 10),
              if (repeat == 'once')
                OutlinedButton.icon(
                  onPressed: () async {
                    final x = await showDatePicker(
                        context: c, initialDate: due, firstDate: DateTime(2025), lastDate: DateTime(2035));
                    if (x != null) set(() => due = x);
                  },
                  icon: const Icon(Icons.event),
                  label: Text(DateFormat('yyyy/M/d（E）', 'zh_TW').format(due)),
                ),
              if (repeat == 'weekly')
                Wrap(spacing: 6, children: [
                  for (var i = 0; i < 7; i++)
                    ChoiceChip(
                      label: Text('週${WorkReminder.weekdayNames[i]}'),
                      selected: weekday == i,
                      onSelected: (_) => set(() => weekday = i),
                    ),
                ]),
              if (repeat == 'monthly')
                Row(children: [
                  const Text('每月'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: monthDay,
                    items: [for (var i = 1; i <= 31; i++) DropdownMenuItem(value: i, child: Text('$i 號'))],
                    onChanged: (v) => set(() => monthDay = v ?? 1),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('（月份沒有這天就算月底）', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
                ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: assign,
                decoration: const InputDecoration(labelText: '給誰'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('不指定（大家都看得到）')),
                  if (_hasSchedule) const DropdownMenuItem(value: 'shift', child: Text('當天上班的人')),
                  for (final p in people) DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => set(() => assign = v ?? ''),
              ),
              if (r != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('啟用'),
                  subtitle: const Text('關掉就暫停，不會出現在今天的清單'),
                  value: active,
                  onChanged: (v) => set(() => active = v),
                ),
              const SizedBox(height: 8),
              Row(children: [
                if (r != null)
                  TextButton(
                    onPressed: () => Navigator.pop(c, 'delete'),
                    child: const Text('刪除', style: TextStyle(color: AppColors.bad)),
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (title.text.trim().isEmpty) return;
                    Navigator.pop(c, 'save');
                  },
                  child: const Text('儲存'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (result == 'delete' && r != null) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('刪除「${r.title}」？'),
          content: const Text('完成紀錄也會一起刪掉。只是暫時不用的話，可以改成關掉「啟用」。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('刪除')),
          ],
        ),
      );
      if (ok == true) await _run(() => _repo.deleteReminder(r.id), ok: '已刪除提醒');
      return;
    }
    if (result != 'save') return;
    final x = WorkReminder(
      id: r?.id ?? '',
      title: title.text.trim(),
      detail: detail.text.trim(),
      repeat: repeat,
      dueDate: repeat == 'once' ? due : null,
      weekday: repeat == 'weekly' ? weekday : null,
      monthDay: repeat == 'monthly' ? monthDay : null,
      startDate: r?.startDate ?? bizToday(),
      assignOnShift: assign == 'shift',
      assignPersonId: assign.isEmpty || assign == 'shift' ? null : assign,
      active: active,
    );
    await _run(() => _repo.saveReminder(_store, x, isNew: r == null), ok: r == null ? '已新增提醒' : '已儲存');
  }

  // ---------------- 畫面 ----------------
  @override
  Widget build(BuildContext context) {
    final b = _board;
    final onReminders = _tabs.index == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.membership.storeName}・交接・提醒'),
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: b == null || b.unreadCount(_me) == 0 ? '交接' : '交接（${b.unreadCount(_me)}）'),
          Tab(text: b == null || b.pendingCount(bizToday()) == 0 ? '提醒' : '提醒（${b.pendingCount(bizToday())}）'),
        ]),
      ),
      floatingActionButton: onReminders
          ? (_canManage && b != null
              ? FloatingActionButton.extended(
                  onPressed: () => _editReminder(null, b), icon: const Icon(Icons.add_alarm), label: const Text('新增提醒'))
              : null)
          : FloatingActionButton.extended(
              onPressed: _writeHandover, icon: const Icon(Icons.edit_note), label: const Text('寫交接')),
      body: FutureBuilder<HandoverBoard>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
          final d = _board ?? snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          return TabBarView(controller: _tabs, children: [_handoverTab(d), _reminderTab(d)]);
        },
      ),
    );
  }
}
