import 'package:flutter/material.dart';

import '../config.dart';

/// 排班的業態範本（ops 0152，只有公版）：開店時選，帶入每天要幾人、班別／時段、排班設定，之後店長自己改。
/// 內容跟資料庫 app.shift_template(kind) 一樣（那邊才是真的寫入；這裡只給畫面顯示），要改兩邊一起改。
class ShiftTemplate {
  final String kind;
  final String label;
  final String note;
  final IconData icon;

  /// 週一～週日：(要幾人, 正職至少)
  final List<(int, int)> staffing;

  /// 班別代碼＋時間（空＝用 V／休 記號）
  final List<(String, String)> codes;
  final List<String> ranges;
  const ShiftTemplate({
    required this.kind,
    required this.label,
    required this.note,
    required this.icon,
    required this.staffing,
    this.codes = const [],
    this.ranges = const [],
  });

  /// 一句話摘要：「平日 2 人・週五六 4 人・班別 B、BL」
  String get summary {
    final needs = [for (final s in staffing) s.$1];
    final parts = <String>[];
    final lo = needs.reduce((a, b) => a < b ? a : b),
        hi = needs.reduce((a, b) => a > b ? a : b);
    if (lo == hi) {
      parts.add('每天 $lo 人');
    } else {
      final busy = [
        for (var i = 0; i < 7; i++)
          if (needs[i] == hi) i,
      ];
      parts.add('平日 $lo 人');
      parts.add('${_days(busy)} $hi 人');
    }
    parts.add(
      codes.isEmpty ? '用 V／休 記號' : '班別 ${codes.map((c) => c.$1).join('、')}',
    );
    return parts.join('・');
  }

  static String _days(List<int> idx) {
    const n = ['一', '二', '三', '四', '五', '六', '日'];
    return '週${idx.map((i) => n[i]).join()}';
  }
}

const shiftTemplates = <ShiftTemplate>[
  ShiftTemplate(
    kind: 'bar',
    label: '酒吧',
    note: '晚上營業、週五六最忙',
    icon: Icons.local_bar_outlined,
    staffing: [(2, 1), (2, 1), (2, 1), (3, 1), (4, 1), (4, 1), (3, 1)],
    codes: [('B', '18:00-01:00'), ('BL', '19:00-02:00')],
    ranges: ['18:00-23:00', '20:00-02:00'],
  ),
  ShiftTemplate(
    kind: 'cafe',
    label: '咖啡廳',
    note: '白天營業、週末較忙',
    icon: Icons.local_cafe_outlined,
    staffing: [(2, 1), (2, 1), (2, 1), (2, 1), (2, 1), (3, 1), (3, 1)],
    codes: [('AM', '08:00-16:00'), ('PM', '12:00-20:00')],
    ranges: ['08:00-12:00', '12:00-16:00', '16:00-20:00'],
  ),
  ShiftTemplate(
    kind: 'restaurant',
    label: '餐廳',
    note: '午餐、晚餐兩個尖峰',
    icon: Icons.restaurant_outlined,
    staffing: [(4, 2), (4, 2), (4, 2), (4, 2), (5, 2), (5, 2), (5, 2)],
    codes: [('L', '10:30-15:00'), ('D', '16:30-22:00'), ('F', '11:00-21:00')],
    ranges: ['11:00-15:00', '17:00-21:00'],
  ),
  ShiftTemplate(
    kind: 'other',
    label: '其他',
    note: '先放最基本的，之後自己改',
    icon: Icons.storefront_outlined,
    staffing: [(2, 1), (2, 1), (2, 1), (2, 1), (2, 1), (2, 1), (2, 1)],
    ranges: ['09:00-13:00', '13:00-17:00', '17:00-21:00'],
  ),
];

const defaultShiftTemplate = 'other';

/// 排班條件頁的「套用業態範本」：只有公版、只有老闆、這家店還沒有人力也沒有班別／時段
bool showApplyTemplate({
  required bool isOwner,
  required bool staffingEmpty,
  required bool optionsEmpty,
}) => AppConfig.selfSignup && isOwner && staffingEmpty && optionsEmpty;
