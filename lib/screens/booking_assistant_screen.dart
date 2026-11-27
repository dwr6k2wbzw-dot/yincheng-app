import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 用講的改訂位設定（ops 0147，公版階段 2 第 7 步；只有老闆）。
/// AI 只會「提出」要怎麼改（改前 → 改後一項一項列出來），老闆按「確認套用」才會改；每一次套用都可以整筆改回去。
class BookingAssistantScreen extends StatefulWidget {
  const BookingAssistantScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<BookingAssistantScreen> createState() => _BookingAssistantScreenState();
}

class _BookingAssistantScreenState extends State<BookingAssistantScreen> {
  static const _examples = [
    '這週六包場，不開放線上訂位',
    '英文介紹改得更有畫面一點',
    '加開日文版',
    '低消改成每人 700'
  ];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<AssistTurn> _turns = [];
  bool _asking = false;
  bool _applying = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Repository get _repo => AppScope.of(context).repo;

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: AppMotion.fast, curve: AppMotion.curve);
        }
      });

  Future<void> _send([String? text]) async {
    final msg = (text ?? _input.text).trim();
    if (msg.isEmpty || _asking) return;
    final history = [..._turns];
    setState(() {
      _turns.add(AssistTurn.user(msg));
      _input.clear();
      _asking = true;
      _error = null;
      // 還沒決定的建議：問了新的就當作不用（避免用舊的「改前」套用）
      for (final t in _turns) {
        if (t.reply != null && t.reply!.changes.isNotEmpty && t.applied == null) {
          t.applied = false;
        }
      }
    });
    _toBottom();
    try {
      final r = await _repo.askBookingAssistant(
          widget.membership.storeId, msg, history);
      if (!mounted) return;
      setState(() => _turns.add(AssistTurn.ai(r)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _asking = false);
      _toBottom();
    }
  }

  String _requestFor(AssistTurn t) {
    final i = _turns.indexOf(t);
    for (var j = i - 1; j >= 0; j--) {
      if (_turns[j].fromUser) return _turns[j].text;
    }
    return '';
  }

  Future<void> _apply(AssistTurn t) async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await _repo.applyBookingAssist(
          widget.membership.storeId, _requestFor(t), t.reply!.changes);
      if (!mounted) return;
      setState(() => t.applied = true);
      showMessage(context, '改好了，客人重新整理訂位頁就看得到');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _openHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) =>
          _HistorySheet(repo: _repo, storeId: widget.membership.storeId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用講的改訂位設定'),
        actions: [
          IconButton(
              tooltip: '最近的修改',
              onPressed: _openHistory,
              icon: const Icon(Icons.history)),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                if (_turns.isEmpty) _intro(),
                for (final t in _turns)
                  t.fromUser ? _userBubble(t) : _aiTurn(t),
                if (_asking)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary)),
                      const SizedBox(width: 10),
                      Text('正在看你的設定…',
                          style: TextStyle(
                              color: AppColors.muted, fontSize: AppType.small)),
                    ]),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: AppColors.bad, fontSize: AppType.small)),
                  ),
              ],
            ),
          ),
          _composer(),
        ]),
      ),
    );
  }

  Widget _intro() => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('想改什麼，直接說',
              style: TextStyle(
                  fontSize: AppType.heading, fontWeight: AppFont.heading)),
          const SizedBox(height: 6),
          Text('會先列出「改前 → 改後」，你按確認才會改；改錯了可以整筆改回去。',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                  height: 1.5)),
          const SizedBox(height: 6),
          Text('目前能改：訂位頁的大標、介紹、外語地址、低消、開哪些語言，還有某一天整天不開放。',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                  height: 1.5)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _examples)
              ActionChip(
                label: Text(e),
                onPressed: () => _send(e),
                backgroundColor: AppColors.cardHigh,
                side: BorderSide(color: AppColors.line),
              ),
          ]),
        ]),
      );

  Widget _userBubble(AssistTurn t) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: AppColors.cardHigh,
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Text(t.text, style: const TextStyle(height: 1.45)),
        ),
      );

  Widget _aiTurn(AssistTurn t) {
    final r = t.reply!;
    return Padding(
      padding: const EdgeInsets.only(top: 12, right: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.reply, style: const TextStyle(height: 1.5)),
        for (final s in r.skipped)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('・$s',
                style:
                    TextStyle(color: AppColors.warn, fontSize: AppType.small)),
          ),
        if (r.changes.isNotEmpty) ...[
          const SizedBox(height: 10),
          _proposal(t),
        ],
      ]),
    );
  }

  Widget _proposal(AssistTurn t) {
    final r = t.reply!;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final c in r.changes) ...[
          Text(c.label,
              style: const TextStyle(
                  fontWeight: AppFont.heading, fontSize: AppType.small)),
          const SizedBox(height: 4),
          Text(c.beforeText,
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: AppColors.muted)),
          const SizedBox(height: 2),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.arrow_forward, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
                child: Text(c.afterText, style: const TextStyle(height: 1.45))),
          ]),
          if (c != r.changes.last) Divider(height: 20, color: AppColors.line),
        ],
        const SizedBox(height: 12),
        switch (t.applied) {
          true => Row(children: [
              Icon(Icons.check_circle, size: 18, color: AppColors.good),
              const SizedBox(width: 6),
              Text('已套用',
                  style: TextStyle(
                      color: AppColors.good, fontSize: AppType.small)),
              const Spacer(),
              TextButton(onPressed: _openHistory, child: const Text('改回去')),
            ]),
          false => Text('沒有套用',
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          null => Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: _applying ? null : () => _apply(t),
                  child: Text(_applying ? '套用中…' : '確認套用'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: _applying
                      ? null
                      : () => setState(() => t.applied = false),
                  child: const Text('不用')),
            ]),
        },
      ]),
    );
  }

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border(top: BorderSide(color: AppColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                  hintText: '例如：12/24 包場不開放', counterText: '', isDense: true),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: '送出',
            onPressed: _asking ? null : _send,
            icon: const Icon(Icons.arrow_upward),
          ),
        ]),
      );
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.repo, required this.storeId});
  final Repository repo;
  final String storeId;
  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<AssistRecord>? _rows;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.repo.bookingAssistHistory(widget.storeId);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _undo(AssistRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('整筆改回去？'),
        content: Text('這次改的 ${r.changes.length} 項都會回到改之前的樣子。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('改回去')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = r.id;
      _error = null;
    });
    try {
      await widget.repo.undoBookingAssist(r.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _when(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text('最近用 AI 改的',
                    style: TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppFont.heading)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(_error!,
                      style: TextStyle(
                          color: AppColors.bad, fontSize: AppType.small)),
                ),
              if (rows == null && _error == null)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()))
              else if (rows != null && rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: Text('還沒有用 AI 改過。',
                      style: TextStyle(color: AppColors.muted)),
                )
              else if (rows != null)
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: AppColors.line, height: 24),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(_when(r.appliedAt),
                                  style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: AppType.small)),
                              const Spacer(),
                              if (r.undoneAt != null)
                                Text('已改回去',
                                    style: TextStyle(
                                        color: AppColors.muted,
                                        fontSize: AppType.small))
                              else
                                TextButton(
                                    onPressed:
                                        _busy == null ? () => _undo(r) : null,
                                    child:
                                        Text(_busy == r.id ? '改回去中…' : '改回去')),
                            ]),
                            if ((r.request ?? '').isNotEmpty)
                              Text('「${r.request}」',
                                  style: const TextStyle(height: 1.4)),
                            const SizedBox(height: 4),
                            for (final c in r.changes)
                              Text('・${c.label}：${c.afterText}',
                                  style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: AppType.small,
                                      height: 1.45)),
                          ]);
                    },
                  ),
                ),
            ]),
      ),
    );
  }
}
