import 'package:flutter/material.dart';

import '../config.dart';
import '../theme.dart';
import 'common.dart';

/// 營收的一個組成項目（金額＋顏色）
class RevenuePart {
  final String label;
  final double amount;
  final Color color;
  const RevenuePart(this.label, this.amount, this.color);
}

const coffeeColor = Color(0xFFC08552);

bool isMultiLineStore(String storeName) => AppConfig.multiLineStores.contains(storeName);

/// 依店家決定營收要拆成哪幾項：
///   隱城：酒水／餐食（／專案）
///   小城外：咖啡／調酒／拉麵／訂金（調酒＝酒水＋餐食＋專案，與小城外 Excel 相同）
List<RevenuePart> revenueParts(
  String storeName, {
  required double drinks,
  required double food,
  double project = 0,
  double coffee = 0,
  double ramen = 0,
  double deposit = 0,
}) {
  if (isMultiLineStore(storeName)) {
    return [
      RevenuePart('咖啡', coffee, coffeeColor),
      RevenuePart('調酒', drinks + food + project, AppColors.primary),
      RevenuePart('拉麵', ramen, AppColors.warn),
      if (deposit != 0) RevenuePart('訂金', deposit, AppColors.muted),
    ];
  }
  return [
    RevenuePart('酒水', drinks, AppColors.primary),
    RevenuePart('餐食', food, AppColors.warn),
    if (project != 0) RevenuePart('專案', project, AppColors.muted),
  ];
}

/// 占比橫條＋（可選）文字說明
class MixBar extends StatelessWidget {
  const MixBar({super.key, required this.parts, this.height = 8, this.showLegend = true});
  final List<RevenuePart> parts;
  final double height;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (a, p) => a + (p.amount > 0 ? p.amount : 0));
    if (total <= 0) return const SizedBox.shrink();
    final shown = parts.where((p) => p.amount > 0).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(height / 2 + 2),
        child: Row(children: [
          for (final p in shown)
            Expanded(flex: (p.amount / total * 1000).round().clamp(1, 1000), child: Container(height: height, color: p.color)),
        ]),
      ),
      if (showLegend) ...[
        const SizedBox(height: 6),
        Text(shown.map((p) => '${p.label} ${pct(p.amount / total)}').join('・'),
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    ]);
  }
}
