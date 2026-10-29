import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/repository.dart';
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
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          // 黑金版：卡片加一條細邊框
          border: AppColors.p.style == DashboardStyle.gold ? Border.all(color: AppColors.line) : null,
        ),
        child: child,
      );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub, this.subColor, this.trailing});
  final String label;
  final String value;
  final String? sub;
  final Color? subColor;
  /// 大數字右邊的小字（例：總覽來客數旁的上月／近 3 月平均）
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(fontSize: AppType.display, fontWeight: FontWeight.w500, fontFeatures: tabular)),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, style: TextStyle(color: subColor ?? AppColors.muted, fontSize: AppType.small)),
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
            Icon(Icons.error_outline, color: AppColors.bad, size: 40),
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


/// 照片自動清理（老闆 2026-10-11）：上傳超過 2 個月的照片會被刪掉
const photoExpiredMessage = '這張照片已超過保存期限（上傳後 2 個月）自動刪除，資料本身還在';

/// 顯示 Storage 裡的照片（送貨單、交接、班表；路徑 receipts/{店家}/...）
/// 照片已被自動清理時，顯示「已超過保存期限」而不是錯誤訊息
Future<void> showStoragePhoto(BuildContext context, String path) async {
  try {
    final url = await AppScope.of(context).repo.shiftPhotoUrl(path);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            // 圖片下載失敗（網路不穩、暫時錯誤…）不一定是過期，訊息不要說死
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('照片載入失敗，請檢查網路後再試一次', textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    final missing = RegExp(r'not.?found|404|does not exist', caseSensitive: false).hasMatch(e.toString());
    showMessage(context, missing ? photoExpiredMessage : friendlyError(e), error: !missing);
  }
}
