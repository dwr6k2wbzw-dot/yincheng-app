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

/// 一行狀態＋ⓘ（老闆 2026-10-29：說明文字不要每次佔半個畫面）。
/// 平常只顯示一行（例：「每小時從日報表同步・最後 10/29 11:25」），點 ⓘ 才展開完整說明。
class InfoLine extends StatefulWidget {
  const InfoLine({super.key, required this.text, this.detail, this.icon = Icons.sync, this.padding = const EdgeInsets.fromLTRB(4, 2, 0, 6)});
  final String text;
  final String? detail;
  final IconData? icon;
  final EdgeInsets padding;
  @override
  State<InfoLine> createState() => _InfoLineState();
}

class _InfoLineState extends State<InfoLine> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final st = TextStyle(color: AppColors.muted, fontSize: AppType.caption, height: 1.5);
    final hasDetail = widget.detail != null && widget.detail!.isNotEmpty;
    return Padding(
      padding: widget.padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: hasDetail ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 14, color: AppColors.muted), const SizedBox(width: 6)],
              Expanded(child: Text(widget.text, style: st, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (hasDetail)
                Icon(_open ? Icons.expand_less : Icons.info_outline, size: 16, color: AppColors.muted),
            ]),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          alignment: Alignment.topLeft,
          child: _open && hasDetail
              ? Padding(padding: const EdgeInsets.only(top: 2, right: 8), child: Text(widget.detail!, style: st))
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

/// 篩選／選擇用的小按鈕（2026-10-29 取代 Flutter 內建 ChoiceChip／FilterChip）。
/// 內建元件在網頁版會把中文字寬量錯、字被切掉，所以自己畫；參數名稱跟內建的一樣，方便替換。
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.avatar,
    this.tooltip,
    this.selectedColor,
    this.visualDensity,
    this.showCheckmark,
  });
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;
  final String? tooltip;
  final Color? selectedColor;
  final VisualDensity? visualDensity; // 保留參數相容，不影響外觀
  final bool? showCheckmark; // 同上：選到的一律靠底色與金色字區分

  @override
  Widget build(BuildContext context) {
    final enabled = onSelected != null;
    final accent = AppColors.primary;
    final fill = selected ? (selectedColor ?? accent.withValues(alpha: 0.16)) : Colors.transparent;
    final fg = selected ? accent : AppColors.text;
    Widget chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => onSelected!(!selected) : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: selected ? accent.withValues(alpha: 0.55) : AppColors.line),
          ),
          child: IconTheme.merge(
            data: IconThemeData(size: 16, color: fg),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: AppType.small, color: fg, fontWeight: selected ? AppFont.label : FontWeight.w400, height: 1.2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (avatar != null) ...[avatar!, const SizedBox(width: 6)],
                label,
              ]),
            ),
          ),
        ),
      ),
    );
    if (!enabled) chip = Opacity(opacity: 0.45, child: chip);
    if (tooltip != null) chip = Tooltip(message: tooltip!, child: chip);
    return Semantics(button: true, selected: selected, enabled: enabled, child: chip);
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub, this.subColor, this.trailing, this.unit});
  final String label;
  final String value;
  final String? sub;
  final Color? subColor;
  /// 大數字右邊的小字（例：總覽來客數旁的上月／近 3 月平均）
  final Widget? trailing;
  /// 大數字後面的小字單位（例：人、元）
  final String? unit;
  @override
  Widget build(BuildContext context) => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            (trailing == null ? (Widget c) => Expanded(child: c) : (Widget c) => Flexible(child: c))(
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: value),
                  if (unit != null)
                    TextSpan(text: ' $unit', style: TextStyle(fontSize: AppType.small, fontWeight: FontWeight.w400, color: AppColors.muted)),
                ]), style: const TextStyle(fontSize: AppType.display, fontWeight: AppFont.figure, fontFeatures: tabular)),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: trailing!))],
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
