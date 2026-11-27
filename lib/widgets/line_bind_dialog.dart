import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../theme.dart';
import 'common.dart';

/// 0156：顯示群組綁定代碼（倒數 10 分鐘、可複製整句、過期可重新產生）
class LineBindDialog extends StatefulWidget {
  final String storeName;
  final LineBindCode first;
  final Future<LineBindCode> Function() regenerate;
  const LineBindDialog(
      {super.key,
      required this.storeName,
      required this.first,
      required this.regenerate});

  @override
  State<LineBindDialog> createState() => _LineBindDialogState();
}

class _LineBindDialogState extends State<LineBindDialog> {
  late LineBindCode _code = widget.first;
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _again() async {
    setState(() => _busy = true);
    try {
      final c = await widget.regenerate();
      if (mounted) setState(() => _code = c);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final expired = _code.expired(now);
    final command = _code.command(widget.storeName);
    final small =
        TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.6);
    return AlertDialog(
      title: const Text('LINE 群組綁定代碼'),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SelectableText(
                _code.code,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                  color: expired ? AppColors.muted : null,
                  decoration: expired ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(_code.remaining(now),
                  style: TextStyle(
                      fontSize: AppType.small,
                      color: expired ? AppColors.bad : AppColors.muted)),
            ),
            const SizedBox(height: 16),
            Text('1. 把店裡的 LINE 機器人拉進工作群組\n2. 在群組打下面這一句（10 分鐘內、用一次就失效）',
                style: small),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: SelectableText(command,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Text('只有拿到這組代碼的人才能把群組綁到這家店；不要傳給店外的人。', style: small),
          ]),
      actions: [
        if (expired)
          TextButton(
              onPressed: _busy ? null : _again, child: const Text('重新產生'))
        else
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (context.mounted) showMessage(context, '已複製，貼到 LINE 群組送出');
            },
            child: const Text('複製這一句'),
          ),
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('好了')),
      ],
    );
  }
}
