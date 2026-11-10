import 'package:flutter/material.dart';

import '../theme.dart';

/// 電腦、平板上內容置中、最寬 [maxWidth]，不要拉滿整個螢幕（2026-11-10）。
/// 包在整個 App 外面（MaterialApp.builder），每一頁、對話框都在這一欄裡；手機寬度不受影響。
class ContentWidthLimit extends StatelessWidget {
  const ContentWidthLimit({super.key, required this.child, this.maxWidth = 640});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= maxWidth) return child;
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: Container(
          width: maxWidth,
          // 兩側一條細線，看得出這一欄是 App 的範圍
          foregroundDecoration: BoxDecoration(border: Border.symmetric(vertical: BorderSide(color: AppColors.line))),
          // 畫面寬度也跟著改，裡面照寬度排版的元件才會算對
          child: MediaQuery(data: mq.copyWith(size: Size(maxWidth, mq.size.height)), child: child),
        ),
      ),
    );
  }
}
