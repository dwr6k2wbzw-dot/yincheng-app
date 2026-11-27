import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 許願單（ops 0149，公版「客戶用講的改功能」第一項）：App 少了什麼功能，寫一則送到平台待辦。
/// 平台回覆的狀態（收到／排進待辦／先不做／做好了）和說明顯示在這裡，也會跳小鈴鐺。
/// 只有公版那一份（SELF_SIGNUP）有入口；只有老闆、店長看得到。
class PlatformWishesScreen extends StatefulWidget {
  const PlatformWishesScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<PlatformWishesScreen> createState() => _PlatformWishesScreenState();
}

class _PlatformWishesScreenState extends State<PlatformWishesScreen> {
  List<PlatformWish>? _items;
  String? _error;
  bool _started = false;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;

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
      final items = await _repo.platformWishes(_store);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }
  }

  int get _used => wishesThisMonth(_items ?? const [], taipeiNow());

  Future<void> _new() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => _WishComposer(repo: _repo, storeId: _store),
    );
    if (sent == true) {
      await _load();
      if (mounted) showMessage(context, '送出了。平台回覆時會跳通知。');
    }
  }

  void _open(PlatformWish w) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    builder: (s) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (s, ctl) => ListView(
        controller: ctl,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            w.title,
            style: const TextStyle(
              fontSize: AppType.heading,
              fontWeight: AppFont.heading,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              WishStatusChip(status: w.status),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _meta(w),
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: AppType.small,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SelectableText(
            w.body,
            style: const TextStyle(fontSize: AppType.body, height: 1.6),
          ),
          if (w.reply != null) ...[
            const SizedBox(height: 20),
            _ReplyBlock(wish: w),
          ],
        ],
      ),
    ),
  );

  static String _meta(PlatformWish w) =>
      '${w.authorName.isEmpty ? '' : '${w.authorName}・'}${DateFormat('M/d HH:mm').format(toTaipei(w.createdAt))}';

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final full = _used >= platformWishMonthlyLimit;
    return Scaffold(
      appBar: AppBar(title: const Text('許願單')),
      floatingActionButton: items == null
          ? null
          : FloatingActionButton.extended(
              onPressed: full ? null : _new,
              backgroundColor: full ? AppColors.cardHigh : null,
              icon: const Icon(Icons.lightbulb_outline),
              label: Text(full ? '這個月寫滿了' : '寫許願單'),
            ),
      body: _error != null && items == null
          ? ErrorView(message: _error!, onRetry: _load)
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'App 少了什麼功能？寫下來送給平台。',
                          style: TextStyle(
                            fontSize: AppType.title,
                            fontWeight: AppFont.heading,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '每一則都會有人看。決定要做、先不做或做好了，都會回覆在這裡，也會跳通知。',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: AppType.small,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '本月已寫 $_used／$platformWishMonthlyLimit 則',
                          style: TextStyle(
                            color: full ? AppColors.bad : AppColors.primary,
                            fontSize: AppType.small,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 56),
                      child: Column(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 40,
                            color: AppColors.muted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '還沒有許願單',
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '按右下角「寫許願單」開始',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: AppType.small,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final w in items) ...[
                    _WishCard(wish: w, meta: _meta(w), onTap: () => _open(w)),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
    );
  }
}

class _WishCard extends StatelessWidget {
  const _WishCard({
    required this.wish,
    required this.meta,
    required this.onTap,
  });
  final PlatformWish wish;
  final String meta;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    wish.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.title,
                      fontWeight: AppFont.heading,
                      color: wish.status == PlatformWishStatus.declined
                          ? AppColors.muted
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                WishStatusChip(status: wish.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              wish.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: AppType.small,
                height: 1.5,
              ),
            ),
            if (wish.reply != null) ...[
              const SizedBox(height: 12),
              _ReplyBlock(wish: wish, compact: true),
            ],
            const SizedBox(height: 10),
            Text(
              meta,
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

/// 平台回覆：左邊一條細線，像信件裡的引用
class _ReplyBlock extends StatelessWidget {
  const _ReplyBlock({required this.wish, this.compact = false});
  final PlatformWish wish;
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.7),
          width: 2,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '平台回覆${wish.repliedAt == null ? '' : '・${DateFormat('M/d').format(toTaipei(wish.repliedAt!))}'}',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: AppType.caption,
            fontWeight: AppFont.label,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          wish.reply!,
          maxLines: compact ? 3 : null,
          overflow: compact ? TextOverflow.ellipsis : null,
          style: TextStyle(
            fontSize: compact ? AppType.small : AppType.body,
            height: 1.55,
          ),
        ),
      ],
    ),
  );
}

class WishStatusChip extends StatelessWidget {
  const WishStatusChip({super.key, required this.status});
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
        platformWishStatusLabel(status),
        style: TextStyle(fontSize: AppType.caption, color: color),
      ),
    );
  }
}

/// 寫一則：標題、想要什麼、為什麼（可以不寫）。錯誤直接顯示在表單裡（不被鍵盤蓋住）
class _WishComposer extends StatefulWidget {
  const _WishComposer({required this.repo, required this.storeId});
  final Repository repo;
  final String storeId;
  @override
  State<_WishComposer> createState() => _WishComposerState();
}

class _WishComposerState extends State<_WishComposer> {
  final _title = TextEditingController(),
      _what = TextEditingController(),
      _why = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _what.dispose();
    _why.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final err = validateWish(_title.text, _what.text, _why.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.createPlatformWish(
        widget.storeId,
        _title.text.trim(),
        composeWishBody(_what.text, _why.text),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
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
          const Text(
            '寫許願單',
            style: TextStyle(
              fontSize: AppType.heading,
              fontWeight: AppFont.heading,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '寫清楚在哪個畫面、想做到什麼，平台比較好判斷。',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: AppType.small,
              height: 1.5,
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
                style: TextStyle(color: AppColors.bad, fontSize: AppType.small),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: true,
            maxLength: platformWishTitleMax,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '標題',
              hintText: '例：訂位頁可以讓客人選座位區',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _what,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '想要什麼',
              hintText: '例：客人訂位時可以選「吧台」或「沙發區」',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _why,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '為什麼需要（可以不寫）',
              hintText: '例：現在都要打電話來問',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
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
                  : const Text('送出'),
            ),
          ),
        ],
      ),
    ),
  );
}
