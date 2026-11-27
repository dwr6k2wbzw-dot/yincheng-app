import 'package:flutter/material.dart';

import '../theme.dart';

/// 開店精靈最下面的按鈕列：上一步／先略過／主要按鈕。
/// 寬度夠就排一列；手機很窄（例如 320 寬）或字放大時，主要按鈕改成滿寬放上面、
/// 上一步和先略過放下面一列，不會擠出畫面（Codex P2）。
class OnboardingActionBar extends StatelessWidget {
  const OnboardingActionBar({
    super.key,
    required this.label,
    required this.onPrimary,
    this.onBack,
    this.onSkip,
    this.showBack = false,
    this.showSkip = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback onPrimary;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final bool showBack;
  final bool showSkip;
  final bool busy;

  /// 排成一列需要的寬度（上一步＋先略過＋主要按鈕＋間距，照字的放大倍數算）
  static const double _rowWidth = 340;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final primary = FilledButton(
      onPressed: busy ? null : onPrimary,
      style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label, textAlign: TextAlign.center),
    );
    final back = showBack
        ? TextButton.icon(
            onPressed: busy ? null : onBack,
            icon: const Icon(Icons.chevron_left),
            label: const Text('上一步'),
          )
        : null;
    final skip = showSkip
        ? TextButton(
            onPressed: busy ? null : onSkip,
            child: const Text('先略過'),
          )
        : null;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < _rowWidth * scale;
            if (!narrow) {
              return Row(children: [
                if (back != null) back,
                const Spacer(),
                if (skip != null) skip,
                const SizedBox(width: 8),
                primary,
              ]);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                primary,
                if (back != null || skip != null) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [if (back != null) back, if (skip != null) skip],
                  ),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}
