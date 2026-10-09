import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

final money = NumberFormat('#,##0', 'zh_TW');
String ntd(num v) => '\$${money.format(v)}';
String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub, this.subColor});
  final String label;
  final String value;
  final String? sub;
  final Color? subColor;
  @override
  Widget build(BuildContext context) => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, style: TextStyle(color: subColor ?? AppColors.muted, fontSize: 12)),
          ],
        ]),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: AppColors.bad, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('重試')),
            ],
          ]),
        ),
      );
}

void showMessage(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? AppColors.bad : null,
    behavior: SnackBarBehavior.floating,
  ));
}
