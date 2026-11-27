import 'package:flutter/material.dart';

import '../data/shift_templates.dart';
import '../theme.dart';

/// 選業態（ops 0152，只有公版）：一張卡一種，點了就選；開店畫面、排班條件頁的「套用業態範本」共用。
class ShiftTemplatePicker extends StatelessWidget {
  const ShiftTemplatePicker(
      {super.key,
      required this.selected,
      required this.onChanged,
      this.enabled = true});
  final String selected;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final t in shiftTemplates) ...[
        _TemplateCard(
            t: t,
            selected: t.kind == selected,
            onTap: enabled ? () => onChanged(t.kind) : null),
        const SizedBox(height: 8),
      ],
    ]);
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard(
      {required this.t, required this.selected, required this.onTap});
  final ShiftTemplate t;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected ? AppColors.primary : AppColors.line;
    return Semantics(
      button: true,
      selected: selected,
      label: '${t.label}，${t.note}，${t.summary}',
      enabled: onTap != null,
      // 底下的 InkWell 被 excludeSemantics 蓋掉了，點的動作要掛在這一層，讀螢幕軟體才點得到（Codex P2）
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.cardHigh : AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: border, width: selected ? 1.5 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Row(children: [
                Icon(t.icon,
                    color: selected ? AppColors.primary : AppColors.muted,
                    size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.label,
                            style: const TextStyle(
                                fontSize: AppType.title,
                                fontWeight: AppFont.heading)),
                        const SizedBox(height: 2),
                        Text(t.note,
                            style: TextStyle(
                                color: AppColors.muted,
                                fontSize: AppType.small)),
                        const SizedBox(height: 2),
                        Text(t.summary,
                            style: TextStyle(
                                color: AppColors.muted,
                                fontSize: AppType.caption)),
                      ]),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: selected
                      ? Icon(Icons.check_circle,
                          key: const ValueKey(1), color: AppColors.primary)
                      : Icon(Icons.radio_button_unchecked,
                          key: const ValueKey(0), color: AppColors.line),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
