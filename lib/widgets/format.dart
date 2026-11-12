import 'package:intl/intl.dart';

// 金額格式（從 common.dart 拆出來：不依賴 app_state，單元測試可以直接用）
final money = NumberFormat('#,##0', 'zh_TW');
String ntd(num v) => '\$${money.format(v)}';
String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
