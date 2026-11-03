import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/open_external.dart';
import '../services/slip_scan.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 功能許願（0069，老闆 2026-10-27）：老闆／店長寫下想怎麼改 App → Claude 改好給預覽 → 老闆按「上線」才正式換新版。
/// 店長每月有次數上限（新需求＋再改一次都算）；店長改好後「送審」，只有老闆能上線或退回。
class ChangeRequestsScreen extends StatefulWidget {
  const ChangeRequestsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<ChangeRequestsScreen> createState() => _ChangeRequestsScreenState();
}

class _ChangeRequestsScreenState extends State<ChangeRequestsScreen> {
  List<ChangeRequest>? _items;
  ChangeQuota? _quota;
  String? _error;
  Timer? _timer;
  bool _started = false;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repo.kickChangeRequests().then((_) => _load());
      _load();
      // 有進行中的就每 20 秒更新一次
      _timer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_items?.any((c) => c.busy) ?? false) _load();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([_repo.changeRequests(_store), _repo.changeQuota(_store)]);
      if (!mounted) return;
      setState(() {
        _items = r[0] as List<ChangeRequest>;
        _quota = r[1] as ChangeQuota;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _new() async {
    if (_quota?.exhausted ?? false) {
      showMessage(context, '本月修改次數已用完（每月 ${_quota!.limit} 次），請跟老闆說', error: true);
      return;
    }
    final body = await showChangeComposer(context,
        title: '我想改…（${widget.membership.storeName}）',
        hint: _exampleHint,
        action: '送出給後臺',
        note: '第一行當標題。寫清楚在哪個畫面、想看到什麼，越具體越準。\n只會改「${widget.membership.storeName}」，另一家店不受影響；兩家都要改，請到另一家店再許一次。',
        allowPhotos: true);
    if (body == null || !mounted) return;
    try {
      final id = await _repo.createChangeRequest(_store, body.text, photos: body.photos);
      _repo.kickChangeRequests().then((_) => _load());
      await _load();
      if (!mounted) return;
      final item = _items?.where((c) => c.id == id).firstOrNull;
      if (item != null) _open(item);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _open(ChangeRequest c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeRequestDetailScreen(membership: widget.membership, request: c),
    ));
    _load();
  }

  static const _exampleHint = '例如：\n'
      '訂位列表每一組旁邊顯示是第幾次來\n'
      '進貨頁的金額改成大字\n'
      '交接卡片上加一個「緊急」標籤';

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final q = _quota;
    return Scaffold(
      appBar: AppBar(title: const Text('功能許願')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('許願'),
      ),
      body: _error != null && items == null
          ? ErrorView(message: _error!, onRetry: _load)
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async {
                    await _repo.kickChangeRequests();
                    await _load();
                  },
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                    SectionCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('寫下想怎麼改「${widget.membership.storeName}」的 App，後臺會直接改好，給你一個預覽網址先試用。另一家店不受影響。',
                            style: TextStyle(height: 1.5)),
                        const SizedBox(height: 6),
                        Text(
                          widget.membership.role == Role.owner
                              ? '看過預覽沒問題，按「上線」大家的 App 才會換成新版。'
                              : '看過預覽沒問題就「送審」，老闆按「上線」大家的 App 才會換成新版。',
                          style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.5),
                        ),
                        if (q != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            q.limit == null ? '本月已用 ${q.used} 次（老闆不限次數）' : '本月已用 ${q.used}／${q.limit} 次（新需求、再改一次都算）',
                            style: TextStyle(color: q.exhausted ? AppColors.bad : AppColors.primary, fontSize: AppType.small),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: Text('還沒有許願，按右下角「許願」開始', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                      ),
                    for (final c in items) ...[
                      SectionCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, color: c.finished ? AppColors.muted : null)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              ChangeStatusChip(status: c.status),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${c.requesterName}・${DateFormat('M/d HH:mm').format(c.createdAt)}',
                                    overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppType.small, color: AppColors.muted)),
                              ),
                            ]),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(c),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ]),
                ),
    );
  }
}

class ChangeStatusChip extends StatelessWidget {
  const ChangeStatusChip({super.key, required this.status});
  final ChangeStatus status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ChangeStatus.ready || ChangeStatus.merged => AppColors.good,
      ChangeStatus.review || ChangeStatus.approved => AppColors.primary,
      ChangeStatus.failed => AppColors.bad,
      ChangeStatus.cancelled => AppColors.muted,
      _ => AppColors.warn,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Text(changeStatusLabel(status), style: TextStyle(fontSize: AppType.small, color: color)),
    );
  }
}

/// 輸入框送出的內容：文字＋附的照片（JPEG data URL，0071）
class ChangeInput {
  final String text;
  final List<String> photos;
  const ChangeInput(this.text, this.photos);
}

/// 寫需求／再改一次／退回原因的輸入框（從下方滑出）；allowPhotos＝可以附照片（最多 5 張）
Future<ChangeInput?> showChangeComposer(BuildContext context,
    {required String title, String? hint, required String action, String? note, bool allowPhotos = false}) {
  final c = TextEditingController();
  final photos = <String>[];
  var picking = false;
  return showModalBottomSheet<ChangeInput>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    builder: (s) => StatefulBuilder(
      builder: (s, setS) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(s).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(note ?? '第一行當標題。寫清楚在哪個畫面、想看到什麼，越具體越準。',
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.5)),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            maxLength: 4000,
            decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
          ),
          if (allowPhotos) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 72,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (var i = 0; i < photos.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Image.memory(dataUrlBytes(photos[i]), width: 72, height: 72, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: InkWell(
                          onTap: () => setS(() => photos.removeAt(i)),
                          child: Container(
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ]),
                  ),
                if (photos.length < 5)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: picking
                        ? null
                        : () async {
                            setS(() => picking = true);
                            try {
                              final d = await pickSlipImage(fromLibrary: true);
                              if (d != null) setS(() => photos.add(d));
                            } catch (e) {
                              if (s.mounted) showMessage(s, '照片讀取失敗，請再試一次', error: true);
                            } finally {
                              if (s.mounted) setS(() => picking = false);
                            }
                          },
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        picking
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary),
                        const SizedBox(height: 2),
                        Text('加照片', style: TextStyle(fontSize: AppType.caption, color: AppColors.muted)),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Text('可以附截圖或照片（最多 5 張），在上面圈出想改的地方更準。',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
          ],
          const SizedBox(height: 8),
          Row(children: [
            TextButton(onPressed: () => Navigator.pop(s), child: const Text('取消')),
            const Spacer(),
            FilledButton.icon(
              icon: const Icon(Icons.send, size: 18),
              onPressed: () {
                final t = c.text.trim();
                if (t.isEmpty) return;
                Navigator.pop(s, ChangeInput(t, List.of(photos)));
              },
              label: Text(action),
            ),
          ]),
        ]),
      ),
    ),
  );
}

/// 一則許願的對話與操作：看預覽、再改一次、送審、上線、退回、取消
class ChangeRequestDetailScreen extends StatefulWidget {
  const ChangeRequestDetailScreen({super.key, required this.membership, required this.request});
  final Membership membership;
  final ChangeRequest request;
  @override
  State<ChangeRequestDetailScreen> createState() => _ChangeRequestDetailScreenState();
}

class _ChangeRequestDetailScreenState extends State<ChangeRequestDetailScreen> {
  late ChangeRequest _c = widget.request;
  List<ChangeMessage>? _msgs;
  Timer? _timer;
  bool _busy = false;
  bool _started = false;

  Repository get _repo => AppScope.of(context).repo;
  bool get _owner => widget.membership.role == Role.owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
      _timer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_c.busy) _load();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([
        _repo.changeRequests(widget.membership.storeId),
        _repo.changeMessages(_c.id),
      ]);
      if (!mounted) return;
      setState(() {
        _c = (r[0] as List<ChangeRequest>).where((x) => x.id == _c.id).firstOrNull ?? _c;
        _msgs = r[1] as List<ChangeMessage>;
      });
    } catch (_) {}
  }

  Future<void> _do(Future<void> Function() f, {String? ok, bool kick = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
      if (kick) _repo.kickChangeRequests().then((_) => _load());
      await _load();
      if (ok != null && mounted) showMessage(context, ok);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _followup() async {
    final body = await showChangeComposer(context,
        title: _c.status == ChangeStatus.failed ? '再試一次' : '再改一次',
        hint: _c.status == ChangeStatus.failed ? '可以補充說明，或直接寫「請重試」' : '例如：按鈕再大一點、顏色改成金色',
        note: '寫下要怎麼調整，後臺會接著上一版修改。這也算一次修改次數。',
        action: '送出',
        allowPhotos: true);
    if (body == null) return;
    await _do(() => _repo.followupChangeRequest(_c.id, body.text, photos: body.photos), kick: true, ok: '已送出，後臺開始修改');
  }

  Future<void> _approve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('上線'),
        content: const Text('確定看過預覽、沒問題了嗎？\n上線後約 10～15 分鐘，所有人的 App 都會換成新版。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('再看看')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('上線')),
        ],
      ),
    );
    if (ok != true) return;
    await _do(() => _repo.approveChangeRequest(_c.id), kick: true, ok: '已核准，正在上線');
  }

  Future<void> _return() async {
    final reason = await showChangeComposer(context,
        title: '退回', hint: '例如：欄位放到最下面', note: '寫下要店長或後臺再調整的地方。', action: '退回');
    if (reason == null) return;
    await _do(() => _repo.returnChangeRequest(_c.id, reason.text), ok: '已退回');
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('取消這個許願'),
        content: const Text('取消後這次的修改不會上線（已用的次數不會退回）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('不要')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('取消許願')),
        ],
      ),
    );
    if (ok != true) return;
    await _do(() => _repo.cancelChangeRequest(_c.id), kick: true, ok: '已取消');
  }

  @override
  Widget build(BuildContext context) {
    final me = AppScope.of(context).repo.currentUserId;
    final canCancel = !_c.finished && _c.status != ChangeStatus.approved && (_owner || _c.requestedBy == me);
    return Scaffold(
      appBar: AppBar(
        title: const Text('許願內容'),
        actions: [
          if (canCancel)
            PopupMenuButton<String>(
              onSelected: (_) => _cancel(),
              itemBuilder: (_) => [const PopupMenuItem(value: 'cancel', child: Text('取消這個許願'))],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text(_c.title, style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            ChangeStatusChip(status: _c.status),
            const SizedBox(width: 8),
            Text('${_c.requesterName}・${DateFormat('M/d HH:mm').format(_c.createdAt)}',
                style: TextStyle(fontSize: AppType.small, color: AppColors.muted)),
          ]),
          const SizedBox(height: 12),
          _statusCard(),
          const SizedBox(height: 16),
          if (_msgs == null) const Center(child: CircularProgressIndicator()),
          for (final m in _msgs ?? const <ChangeMessage>[]) _bubble(m),
        ]),
      ),
    );
  }

  Widget _statusCard() {
    final s = _c.status;
    final children = <Widget>[];
    void text(String t, {Color? color}) =>
        children.add(Text(t, style: TextStyle(height: 1.5, color: color)));
    final preview = _c.hasPreview && s != ChangeStatus.merged && s != ChangeStatus.cancelled
        ? OutlinedButton.icon(
            onPressed: () => openExternal(_c.previewUrl!),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('看預覽'),
          )
        : null;
    switch (s) {
      case ChangeStatus.queued:
      case ChangeStatus.running:
        children.add(Row(children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(child: Text(s == ChangeStatus.queued ? '排隊中，幾分鐘內會開始…' : '後臺正在修改，通常 15～30 分鐘。')),
        ]));
        text('可以先離開這個畫面，改好會在小鈴鐺通知。', color: AppColors.muted);
        if (_c.hasPreview) text('（下面的預覽還是上一版）', color: AppColors.muted);
      case ChangeStatus.ready:
        text(_owner ? '改好了！先點「看預覽」試試看，沒問題就按「上線」。' : '改好了！先點「看預覽」試試看，沒問題就「送審」給老闆。');
        text('預覽版用的是真的資料，試的時候請小心（例如不要真的取消訂位）。', color: AppColors.muted);
      case ChangeStatus.failed:
        text(_c.lastError ?? '這次沒有成功', color: AppColors.bad);
        text('可以按「再試一次」，或補充說明讓後臺換個方式做。', color: AppColors.muted);
      case ChangeStatus.review:
        text(_owner ? '店長已送審，看過預覽沒問題就按「上線」，或寫原因退回。' : '已送審，等老闆核准上線。');
      case ChangeStatus.approved:
        children.add(const Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Expanded(child: Text('上線中…')),
        ]));
      case ChangeStatus.merged:
        text('已上線！約 10 分鐘後小鈴鐺會出現「App 有新版本」，點一下就會換成新版。', color: AppColors.good);
      case ChangeStatus.cancelled:
        text('已取消', color: AppColors.muted);
    }
    final buttons = <Widget>[
      if (preview != null) preview,
      if (s == ChangeStatus.ready || s == ChangeStatus.review || s == ChangeStatus.failed)
        OutlinedButton.icon(
          onPressed: _busy ? null : _followup,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(s == ChangeStatus.failed ? '再試一次' : '再改一次'),
        ),
      if (s == ChangeStatus.ready && !_owner)
        FilledButton.icon(
          onPressed: _busy ? null : () => _do(() => _repo.submitChangeRequest(_c.id), ok: '已送審，等老闆核准'),
          icon: const Icon(Icons.outbox_outlined, size: 18),
          label: const Text('送審給老闆'),
        ),
      if (s == ChangeStatus.review && _owner)
        OutlinedButton.icon(
          onPressed: _busy ? null : _return,
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('退回'),
        ),
      if ((s == ChangeStatus.ready || s == ChangeStatus.review) && _owner && _c.hasPreview)
        FilledButton.icon(
          onPressed: _busy ? null : _approve,
          icon: const Icon(Icons.rocket_launch_outlined, size: 18),
          label: const Text('上線'),
        ),
    ];
    if (buttons.isNotEmpty) {
      children.add(const SizedBox(height: 12));
      children.add(Wrap(spacing: 8, runSpacing: 8, children: buttons));
    }
    return SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
  }

  Widget _bubble(ChangeMessage m) {
    final claude = m.kind == 'claude';
    final system = m.kind == 'system';
    final label = switch (m.kind) {
      'request' => '需求・${m.authorName}',
      'followup' => '再改一次・${m.authorName}',
      'claude' => '後臺',
      _ => m.authorName,
    };
    if (system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('— ${m.body}・${DateFormat('M/d HH:mm').format(m.createdAt)} —',
            textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.small, color: AppColors.muted)),
      );
    }
    return Align(
      alignment: claude ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: claude ? AppColors.card : AppColors.cardHigh,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: claude ? Border.all(color: AppColors.primary.withValues(alpha: 0.4)) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label・${DateFormat('M/d HH:mm').format(m.createdAt)}',
              style: TextStyle(fontSize: AppType.caption, color: claude ? AppColors.primary : AppColors.muted)),
          const SizedBox(height: 4),
          SelectableText(m.body, style: const TextStyle(height: 1.5)),
          if (m.photoIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final id in m.photoIds) _ChangePhotoThumb(id: id)]),
          ],
        ]),
      ),
    );
  }
}

/// 許願附的照片縮圖（點了放大）；讀過的存在記憶體，不重複下載
class _ChangePhotoThumb extends StatefulWidget {
  const _ChangePhotoThumb({required this.id});
  final String id;
  static final _cache = <String, Uint8List>{};
  @override
  State<_ChangePhotoThumb> createState() => _ChangePhotoThumbState();
}

class _ChangePhotoThumbState extends State<_ChangePhotoThumb> {
  Future<Uint8List>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _ChangePhotoThumb._cache.containsKey(widget.id)
        ? Future.value(_ChangePhotoThumb._cache[widget.id])
        : AppScope.of(context).repo.changePhoto(widget.id).then((b) => _ChangePhotoThumb._cache[widget.id] = b);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _f,
        builder: (context, snap) {
          final box = BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.sm));
          if (snap.hasError) {
            return Container(width: 72, height: 72, decoration: box, child: Icon(Icons.broken_image_outlined, color: AppColors.muted));
          }
          if (!snap.hasData || snap.data!.isEmpty) {
            return Container(width: 72, height: 72, decoration: box, child: Icon(Icons.image_outlined, color: AppColors.muted));
          }
          final bytes = snap.data!;
          return InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => Dialog(
                insetPadding: const EdgeInsets.all(8),
                child: InteractiveViewer(maxScale: 6, child: Image.memory(bytes, fit: BoxFit.contain)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover),
            ),
          );
        },
      );
}
