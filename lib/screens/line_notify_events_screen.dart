import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/line_notify_events.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 哪些通知要發到 LINE 群組（ops 0162，公版；只有老闆）。
/// 每一種勾了才發到這家店綁的工作群組；小鈴鐺照舊全部都有。
class LineNotifyEventsScreen extends StatefulWidget {
  const LineNotifyEventsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<LineNotifyEventsScreen> createState() => _LineNotifyEventsScreenState();
}

class _LineNotifyEventsScreenState extends State<LineNotifyEventsScreen> {
  Set<String>? _saved; // 資料庫裡的
  Set<String> _on = {};
  String? _loadError;
  bool _started = false;
  bool _busy = false;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  bool get _dirty => _saved != null && !_sameSet(_saved!, _on);

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final v = await _repo.lineNotifyEvents(_store);
      if (mounted) {
        setState(() {
          _saved = {...v};
          _on = {...v};
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = friendlyError(e));
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _repo.saveLineNotifyEvents(_store, _on);
      if (!mounted) return;
      setState(() => _saved = {..._on});
      showMessage(
        context,
        _on.isEmpty ? '已存好：目前不發任何通知到群組' : '已存好：${lineNotifySummary(_on)}',
      );
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('還沒存，要離開嗎？'),
        content: const Text('剛剛勾的不會存起來'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('留下來'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('不存，離開'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String>{for (final e in lineNotifyEvents) e.group}.toList();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('LINE 群組通知')),
        body: _saved == null
            ? (_loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : const Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                    child: Text(
                      '勾了的才會發到這家店的 LINE 工作群組；App 的小鈴鐺照舊全部都有。',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: AppType.small,
                        height: 1.5,
                      ),
                    ),
                  ),
                  for (final g in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                      child: Text(
                        g,
                        style: const TextStyle(fontWeight: AppFont.heading),
                      ),
                    ),
                    SectionCard(
                      // ListTile 的點擊水波要畫在自己的 Material 上（卡片有底色會蓋掉）
                      child: Material(
                        type: MaterialType.transparency,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final e in lineNotifyEvents.where(
                              (e) => e.group == g,
                            ))
                              CheckboxListTile(
                                key: ValueKey('line-event-${e.key}'),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                value: _on.contains(e.key),
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(
                                          () => v == true
                                              ? _on.add(e.key)
                                              : _on.remove(e.key),
                                        ),
                                title: Text(e.label),
                                subtitle: Text(
                                  e.detail,
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: AppType.small,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  const SizedBox(height: 8),
                  const InfoLine(
                    icon: null,
                    text: '發到群組是照群組人數算則數',
                    detail:
                        'LINE 發到群組的訊息照群組人數計算（群組 14 人，發一則＝14 則）。官方帳號的免費方案每月 200 則，勾越多用得越快。'
                        '功能許願、許願單只有老闆、店長看得到，群組裡有兼職，所以不提供發到群組。',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy || !_dirty ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(_busy ? '存檔中…' : (_dirty ? '存檔' : '已存好')),
                  ),
                  if (!_sameSet(_on, lineNotifyDefault))
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _on = {...lineNotifyDefault}),
                      child: const Text('改回預設（只發重要交接）'),
                    ),
                ],
              ),
      ),
    );
  }
}
