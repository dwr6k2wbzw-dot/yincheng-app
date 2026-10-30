import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/slip_scan.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 標題列（小鈴鐺左邊）的「交接・提醒」按鈕（老闆 2026-10-14，原本是總覽最上面的卡片）。
/// 數字＝今天還沒做的提醒＋未讀交接；打開 App、回到 App、之後每 2 分鐘更新，從交接頁回來也更新。
class HandoverButton extends StatefulWidget {
  const HandoverButton({super.key, required this.membership});
  final Membership membership;
  @override
  State<HandoverButton> createState() => _HandoverButtonState();
}

class _HandoverButtonState extends State<HandoverButton> with WidgetsBindingObserver {
  HandoverBoard? _board;
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
    try {
      final b = await AppScope.of(context).repo.handoverBoard(widget.membership.storeId);
      if (mounted) setState(() => _board = b);
    } catch (_) {
      // 沒網路時保留上一次的數字
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => HandoverScreen(membership: widget.membership)));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).repo.currentUserId;
    final b = _board;
    final n = b == null ? 0 : b.pendingCount(bizToday()) + b.unreadCount(me);
    return IconButton(
      tooltip: '交接・提醒',
      onPressed: _open,
      icon: Badge(
        isLabelVisible: n > 0,
        backgroundColor: AppColors.warn,
        label: Text(n > 9 ? '9+' : '$n'),
        child: Icon(Icons.checklist, color: n > 0 ? AppColors.warn : null),
      ),
    );
  }
}

/// 交接・提醒頁：兩個分頁「交接」「提醒」
class HandoverScreen extends StatefulWidget {
  const HandoverScreen({super.key, required this.membership, this.initialTab = 0});
  final Membership membership;
  final int initialTab; // 0＝交接、1＝提醒（從小鈴鐺通知點進來）
  @override
  State<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends State<HandoverScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  late Future<HandoverBoard> _future;
  HandoverBoard? _board;
  bool _started = false;
  final _seen = <String>{};

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  bool get _canManage => widget.membership.isManager;
  String? get _me => _repo.currentUserId;
  // 提醒：任何成員都能新增；自己建的可以改、刪，老闆／店長可管理全部（0041）
  bool _canEditReminder(WorkReminder r) => _canManage || (_me != null && r.createdBy == _me);
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
  // 0060：交接改成打勾清單（每一項一行）＋補充說明（選填）
  Future<_HandoverDraft?> _handoverSheet({HandoverNote? n}) {
    final editing = n != null;
    final items = <TextEditingController>[
      for (final i in n?.items ?? const <HandoverItem>[]) TextEditingController(text: i.body),
    ];
    // 舊交接（沒有清單）修改時：內容留在補充說明
    if (items.isEmpty) items.add(TextEditingController());
    final note = TextEditingController(text: n?.body ?? '');
    final focus = <FocusNode>[for (final _ in items) FocusNode()];
    String? photo;
    var important = n?.important ?? false;
    return showModalBottomSheet<_HandoverDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        void addItem() {
          set(() {
            items.add(TextEditingController());
            focus.add(FocusNode());
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => focus.last.requestFocus());
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(editing ? '修改交接' : '寫交接', style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('一項一行，接班的人做完一項勾一項；全部勾完才能按「已處理」。', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                const SizedBox(height: 10),
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(Icons.check_box_outline_blank, size: 20, color: AppColors.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: items[i],
                          focusNode: focus[i],
                          autofocus: !editing && i == 0,
                          maxLength: 200,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => i == items.length - 1 ? addItem() : focus[i + 1].requestFocus(),
                          decoration: InputDecoration(
                            hintText: i == 0 ? '例：冰塊機漏水，明天下午師傅來' : '第 ${i + 1} 項',
                            counterText: '',
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '刪除這一項',
                        onPressed: items.length == 1
                            ? () => set(() => items[0].clear())
                            : () => set(() {
                                  items.removeAt(i);
                                  focus.removeAt(i);
                                }),
                        icon: Icon(Icons.close, size: 18, color: AppColors.muted),
                      ),
                    ]),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      onPressed: items.length >= 50 ? null : addItem, icon: const Icon(Icons.add), label: const Text('新增一項')),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: note,
                  maxLines: 4,
                  minLines: 1,
                  maxLength: 1000,
                  decoration: const InputDecoration(labelText: '補充說明（選填）', border: OutlineInputBorder()),
                ),
                // 0079：只有勾「重要」的交接才會發到 LINE 群組（LINE 照群組人數計費）
                Material(
                  color: important ? AppColors.bad.withValues(alpha: 0.10) : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    side: BorderSide(color: important ? AppColors.bad : AppColors.muted.withValues(alpha: 0.35)),
                  ),
                  child: CheckboxListTile(
                    value: important,
                    onChanged: (v) => set(() => important = v ?? false),
                    activeColor: AppColors.bad,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: const Text('⚠ 重要，發到 LINE 群組', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(editing && (n.important) ? '已經發過；取消勾選不會收回 LINE 訊息' : '一般交接只在 App 裡看；真的要大家馬上知道的才勾',
                        style: TextStyle(fontSize: AppType.caption, color: AppColors.muted)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  if (!editing) ...[
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
                      Icon(Icons.check_circle, color: AppColors.good, size: 18),
                      const Text(' 已附照片', style: TextStyle(fontSize: AppType.small)),
                      IconButton(tooltip: '移除照片', onPressed: () => set(() => photo = null), icon: const Icon(Icons.close, size: 18)),
                    ],
                  ],
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      final list = [for (final t in items) t.text.trim()]..removeWhere((x) => x.isEmpty);
                      if (list.isEmpty && note.text.trim().isEmpty) {
                        showMessage(c, '請至少寫一項交接', error: true);
                        return;
                      }
                      Navigator.pop(c, _HandoverDraft(note.text.trim(), list, photo, important));
                    },
                    child: Text(editing ? '儲存' : '送出'),
                  ),
                ]),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _writeHandover() async {
    final d = await _handoverSheet();
    if (d == null) return;
    await _run(() => _repo.addHandover(_store, d.body, d.items, d.photo == null ? null : dataUrlBytes(d.photo!), important: d.important),
        ok: d.important ? '已送出，也會發到 LINE 群組' : '已送出交接');
  }

  Future<void> _showPhoto(String path) => showStoragePhoto(context, path);

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

  Future<void> _editHandover(HandoverNote n) async {
    if (n.resolved) {
      showMessage(context, '這則交接已處理，要修改請先按「改回未處理」', error: true);
      return;
    }
    final d = await _handoverSheet(n: n);
    if (d == null) return;
    if (d.body == n.body.trim() && listEquals(d.items, [for (final i in n.items) i.body]) && d.important == n.important) return;
    final nowImportant = d.important && !n.important;
    await _run(() => _repo.updateHandover(n.id, d.body, d.items, important: d.important == n.important ? null : d.important),
        ok: nowImportant ? '已修改，並發到 LINE 群組' : '已修改');
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? '今天 ${DateFormat('HH:mm').format(t)}' : DateFormat('M/d（E）HH:mm', 'zh_TW').format(t);
  }

  // 清單一項：點一下打勾／取消（已處理的交接不能改）
  Widget _itemRow(HandoverNote n, HandoverItem it) {
    final muted = it.done || n.resolved;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: n.resolved ? null : () => _run(() => _repo.setHandoverItemDone(it.id, !it.done)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(it.done ? Icons.check_box : Icons.check_box_outline_blank,
              size: 24, color: it.done ? AppColors.good : (n.resolved ? AppColors.muted : AppColors.text)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.body,
                  style: TextStyle(
                    fontSize: AppType.body,
                    height: 1.4,
                    color: muted ? AppColors.muted : null,
                    decoration: it.done ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.muted,
                  )),
              if (it.done)
                Text('✓ ${it.doneName ?? ''}・${_when(it.doneAt!)}', style: TextStyle(color: AppColors.good, fontSize: AppType.caption)),
            ]),
          ),
        ]),
      ),
    );
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
                decoration: BoxDecoration(color: AppColors.warn, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: const Text('新', style: TextStyle(fontSize: AppType.caption, color: Colors.black, fontWeight: FontWeight.w700)),
              ),
            if (n.important)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.bad, borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: const Text('⚠ 重要', style: TextStyle(fontSize: AppType.caption, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            Text(n.authorName.isEmpty ? '—' : n.authorName, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(child: Text(_when(n.createdAt), style: TextStyle(color: AppColors.muted, fontSize: AppType.small))),
            if (n.items.isNotEmpty)
              Text('${n.items.length - n.itemsLeft}/${n.items.length}',
                  style: TextStyle(
                      color: n.itemsLeft == 0 ? AppColors.good : AppColors.muted, fontSize: AppType.small, fontWeight: FontWeight.w600)),
            // 任何成員都能修改、刪除（老闆 2026-10-12，0044）
            PopupMenuButton<String>(
              tooltip: '修改／刪除',
              icon: Icon(Icons.more_vert, size: 18, color: AppColors.muted),
              onSelected: (v) => v == 'edit' ? _editHandover(n) : _deleteHandover(n),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('修改內容'))),
                PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('刪除'))),
              ],
            ),
          ]),
          const SizedBox(height: 6),
          for (final it in n.items) _itemRow(n, it),
          if (n.body.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: n.items.isEmpty ? 0 : 4),
              child: SelectableText(n.body,
                  style: TextStyle(
                      fontSize: n.items.isEmpty ? 15 : 13, height: 1.5, color: n.resolved || n.items.isNotEmpty ? AppColors.muted : null)),
            ),
          if (n.editedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('已修改・${n.editedName ?? ''}・${_when(n.editedAt!)}',
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
            ),
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
                style: TextStyle(color: n.resolved ? AppColors.good : AppColors.muted, fontSize: AppType.small, height: 1.5),
              ),
            ),
            n.resolved
                ? TextButton(onPressed: () => _run(() => _repo.setHandoverResolved(n.id, false)), child: const Text('改回未處理'))
                : n.itemsLeft > 0
                    // 0060：清單全部勾完才能按已處理
                    ? FilledButton.tonal(onPressed: null, child: Text('還有 ${n.itemsLeft} 項'))
                    : FilledButton.tonal(
                        onPressed: () => _run(() => _repo.setHandoverResolved(n.id, true), ok: '已標成處理完'),
                        child: const Text('已處理'),
                      ),
          ]),
        ]),
      ),
    );
  }

  // 0079：老闆可以關掉這家店的 LINE 群組通知（只有老闆看得到這個開關）
  bool get _isOwner => widget.membership.role == Role.owner;
  bool? _lineOn;
  bool _lineLoading = false;
  int? _lineLinks; // 0081：我綁了 LINE 私訊沒

  Future<void> _linkLine() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('綁定我的 LINE 私訊'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('1. 在 LINE 私訊店裡的機器人，打「綁定」\n2. 把它回的 6 位數代碼填在這裡（10 分鐘內）',
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.6)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: '代碼', counterText: '', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('綁定')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      await _repo.linkLineOwner(code);
      if (mounted) {
        setState(() => _lineLinks = 1);
        showMessage(context, '綁定好了！之後私訊機器人不用 @ 就能問');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _unlinkLine() async {
    try {
      await _repo.unlinkLineOwner();
      if (mounted) {
        setState(() => _lineLinks = 0);
        showMessage(context, '已解除，私訊機器人不會再回答');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Widget _lineSwitch() {
    if (_lineOn == null && !_lineLoading) {
      _lineLoading = true;
      _repo.lineOwnerLinks().then((v) {
        if (mounted) setState(() => _lineLinks = v);
      }).catchError((_) {});
      _repo.lineNotifyEnabled(_store).then((v) {
        if (mounted) setState(() => _lineOn = v);
      }).catchError((_) {
        if (mounted) setState(() => _lineOn = true);
      });
    }
    final on = _lineOn ?? true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: on,
            onChanged: _lineOn == null
                ? null
                : (v) async {
                    setState(() => _lineOn = v);
                    try {
                      await _repo.saveLineNotifyEnabled(_store, v);
                      if (mounted) showMessage(context, v ? '已打開：重要交接會發到 LINE 群組' : '已關掉：交接只在 App 裡看');
                    } catch (e) {
                      if (mounted) {
                        setState(() => _lineOn = !v);
                        showMessage(context, friendlyError(e), error: true);
                      }
                    }
                  },
            title: const Text('LINE 群組通知', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(on ? '勾「⚠ 重要」的交接會發到這家店的 LINE 群組' : '已關掉，交接只在 App 裡看',
                style: TextStyle(fontSize: AppType.small, color: AppColors.muted)),
          ),
          const Divider(height: 1),
          // 0081：老闆私訊 AI 助理
          Row(children: [
            Expanded(
              child: Text((_lineLinks ?? 0) > 0 ? 'LINE 私訊助理：已綁定，私訊機器人不用 @ 就能問兩家店的事' : 'LINE 私訊助理：綁定後可以私訊機器人問店裡的事',
                  style: TextStyle(fontSize: AppType.small, color: AppColors.muted, height: 1.5)),
            ),
            (_lineLinks ?? 0) > 0
                ? TextButton(onPressed: _unlinkLine, child: const Text('解除'))
                : TextButton(onPressed: _linkLine, child: const Text('綁定我的 LINE 私訊')),
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
        if (_isOwner) _lineSwitch(),
        if (open.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('目前沒有待處理的交接', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ),
        for (final n in open) _noteCard(n),
        if (done.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('已處理（${done.length}）', style: TextStyle(color: AppColors.muted)),
              children: [for (final n in done) _noteCard(n)],
            ),
          ),
        const SizedBox(height: 8),
        Text('大家都能寫交接、修改、刪除；做完一項勾一項，全部勾完才能按「已處理」。勾「⚠ 重要」的才會發到 LINE 群組。打開這頁就會記錄你已讀。',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.caption, height: 1.5)),
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
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
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w600,
                          color: dn != null ? AppColors.muted : (overdue ? AppColors.bad : null),
                          decoration: dn != null ? TextDecoration.lineThrough : null)),
                  if (r.detail != null && r.detail!.isNotEmpty)
                    Text(r.detail!, style: const TextStyle(fontSize: AppType.small, height: 1.4)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: AppType.small, color: overdue ? AppColors.bad : (dn != null ? AppColors.good : AppColors.muted))),
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
            style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('今天沒有提醒', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ),
        for (final (r, occ, dn) in items) _todayTile(b, r, occ, dn, today),
        const SizedBox(height: 4),
        Text('點一下打勾；做完的會記錄是誰、幾點做的。凌晨 6 點前還算前一天。', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        const SizedBox(height: 20),
        if (all.isNotEmpty) ...[
          Text('全部提醒', style: TextStyle(color: AppColors.muted)),
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
                    style: const TextStyle(fontSize: AppType.small),
                  ),
                  trailing: _canEditReminder(r) ? const Icon(Icons.edit_outlined, size: 18) : null,
                  onTap: _canEditReminder(r) ? () => _editReminder(r, b) : null,
                ),
            ]),
          ),
        ],
        if (!_canManage)
          Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('每個人都能新增提醒；自己建的可以修改、刪除。', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
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
              Text(r == null ? '新增提醒' : '修改提醒', style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w700)),
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
                    final x = await showDatePicker(context: c, initialDate: due, firstDate: DateTime(2025), lastDate: DateTime(2035));
                    if (x != null) set(() => due = x);
                  },
                  icon: const Icon(Icons.event),
                  label: Text(DateFormat('yyyy/M/d（E）', 'zh_TW').format(due)),
                ),
              if (repeat == 'weekly')
                Wrap(spacing: 6, children: [
                  for (var i = 0; i < 7; i++)
                    SelectChip(
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
                  Expanded(
                    child: Text('（月份沒有這天就算月底）', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
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
                    child: Text('刪除', style: TextStyle(color: AppColors.bad)),
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
          ? (b != null
              ? FloatingActionButton.extended(
                  onPressed: () => _editReminder(null, b), icon: const Icon(Icons.add_alarm), label: const Text('新增提醒'))
              : null)
          : FloatingActionButton.extended(onPressed: _writeHandover, icon: const Icon(Icons.edit_note), label: const Text('寫交接')),
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

/// 寫／改交接的內容（0060）
class _HandoverDraft {
  final String body;
  final List<String> items;
  final String? photo;
  final bool important; // 0079：發到 LINE 群組
  const _HandoverDraft(this.body, this.items, this.photo, [this.important = false]);
}
