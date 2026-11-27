import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 客戶許願（平台）（ops 0159）：平台管理者看所有店寫的許願單、改狀態、寫回覆。
/// 只有公版那一份（SELF_SIGNUP）、而且 platform_admin_me() 是 true 的人才有入口；
/// 隱城、小城外這一份完全看不到。回覆後那家店的老闆、店長會在許願單看到，也會跳小鈴鐺。
class PlatformAdminWishesScreen extends StatefulWidget {
  const PlatformAdminWishesScreen({super.key});
  @override
  State<PlatformAdminWishesScreen> createState() =>
      _PlatformAdminWishesScreenState();
}

/// 分頁：四種狀態＋全部（null）
const _tabs = <PlatformWishStatus?>[
  PlatformWishStatus.received,
  PlatformWishStatus.planned,
  PlatformWishStatus.declined,
  PlatformWishStatus.done,
  null,
];

class _PlatformAdminWishesScreenState extends State<PlatformAdminWishesScreen> {
  List<PlatformAdminWish>? _items;
  Map<PlatformWishStatus, int> _counts = const {};
  String? _error;
  bool _started = false;
  PlatformWishStatus? _tab = PlatformWishStatus.received;

  Repository get _repo => AppScope.of(context).repo;

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
      final r = await Future.wait([
        _repo.platformAdminWishes(),
        _repo.platformAdminWishCounts(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = r[0] as List<PlatformAdminWish>;
        _counts = r[1] as Map<PlatformWishStatus, int>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  int get _total => _counts.values.fold(0, (a, b) => a + b);

  String _tabLabel(PlatformWishStatus? s) =>
      '${s == null ? '全部' : platformAdminStatusLabel(s)} ${s == null ? _total : (_counts[s] ?? 0)}';

  Future<void> _open(PlatformAdminWish w) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => _ReplySheet(repo: _repo, item: w),
    );
    if (!mounted || result == null) return;
    if (result == 'stale') {
      await _load();
      if (mounted) showMessage(context, '別人剛回覆過，已重新整理', error: true);
    } else if (result == 'sent') {
      await _load();
      if (mounted) showMessage(context, '已回覆，店家會收到通知');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final shown = items == null
        ? const <PlatformAdminWish>[]
        : [
            for (final w in items)
              if (_tab == null || w.wish.status == _tab) w,
          ];
    return Scaffold(
      appBar: AppBar(title: const Text('客戶許願（平台）')),
      body: _error != null && items == null
          ? ErrorView(message: _error!, onRetry: _load)
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 分頁：手機寬度放不下就換行，五個都看得到（不用橫向捲）
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final s in _tabs)
                          ChoiceChip(
                            label: Text(_tabLabel(s)),
                            selected: _tab == s,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            onSelected: (_) => setState(() => _tab = s),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: AppColors.bad,
                        fontSize: AppType.small,
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      children: [
                        if (shown.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 64),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  size: 40,
                                  color: AppColors.muted,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _tab == null
                                      ? '還沒有任何店寫許願單'
                                      : '沒有「${platformAdminStatusLabel(_tab!)}」的許願單',
                                  style: TextStyle(color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                        for (final w in shown) ...[
                          _AdminWishCard(item: w, onTap: () => _open(w)),
                          const SizedBox(height: 10),
                        ],
                        if (items.length >= 500)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '只列出最新的 500 則',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: AppType.caption,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

String _when(DateTime t) => DateFormat('M/d HH:mm').format(toTaipei(t));

class _AdminStatusChip extends StatelessWidget {
  const _AdminStatusChip({required this.status});
  final PlatformWishStatus status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PlatformWishStatus.done => AppColors.good,
      PlatformWishStatus.planned => AppColors.primary,
      PlatformWishStatus.declined => AppColors.muted,
      PlatformWishStatus.received => AppColors.warn,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        platformAdminStatusLabel(status),
        style: TextStyle(fontSize: AppType.caption, color: color),
      ),
    );
  }
}

class _AdminWishCard extends StatelessWidget {
  const _AdminWishCard({required this.item, required this.onTap});
  final PlatformAdminWish item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final w = item.wish;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: AppType.small,
                        fontWeight: AppFont.label,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _AdminStatusChip(status: w.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                w.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppType.title,
                  fontWeight: AppFont.heading,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                w.body.replaceAll(RegExp(r'\s*\n+\s*'), ' '), // 卡片上把換行併成一行，才不會空一大格
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${w.authorName.isEmpty ? '' : '${w.authorName}・'}${_when(w.createdAt)}'
                '${w.reply != null ? '・已回覆' : ''}',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.caption,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 回覆：選狀態、寫回覆、送出。回傳 'sent'／'stale'（別人剛回覆過）／null（沒送）
class _ReplySheet extends StatefulWidget {
  const _ReplySheet({required this.repo, required this.item});
  final Repository repo;
  final PlatformAdminWish item;
  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  late PlatformWishStatus _status = widget.item.wish.status;
  late final _reply = TextEditingController(text: widget.item.wish.reply ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  bool get _changed =>
      _status != widget.item.wish.status ||
      _reply.text.trim() != (widget.item.wish.reply ?? '');

  Future<void> _send() async {
    final err = validateAdminReply(_reply.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (!_changed) {
      setState(() => _error = '狀態和回覆都沒有改');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.platformAdminReply(widget.item, _status, _reply.text);
      if (mounted) Navigator.of(context).pop('sent');
    } catch (e) {
      if (!mounted) return;
      if (isWishStale(e)) {
        Navigator.of(context).pop('stale');
        return;
      }
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.item.wish;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.item.storeName,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: AppType.small,
                fontWeight: AppFont.label,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              w.title,
              style: const TextStyle(
                fontSize: AppType.heading,
                fontWeight: AppFont.heading,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${w.authorName.isEmpty ? '' : '${w.authorName}・'}${_when(w.createdAt)}',
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText(
                  w.body,
                  style: const TextStyle(fontSize: AppType.body, height: 1.6),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bad.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: AppColors.bad,
                    fontSize: AppType.small,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text('狀態', style: TextStyle(fontWeight: AppFont.label)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in PlatformWishStatus.values)
                  ChoiceChip(
                    label: Text(platformAdminStatusLabel(s)),
                    selected: _status == s,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _status = s),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '店家會看到：${platformWishStatusLabel(_status)}',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: AppType.caption,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reply,
              enabled: !_busy,
              minLines: 3,
              maxLines: 8,
              maxLength: platformWishBodyMax,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '回覆（店家看得到）',
                hintText: '例：收到，排進下個月的待辦，做好會再通知你。',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('送出回覆'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
