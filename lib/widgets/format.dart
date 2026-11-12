import 'package:intl/intl.dart';

// 金額格式（從 common.dart 拆出來：不依賴 app_state，單元測試可以直接用）
final money = NumberFormat('#,##0', 'zh_TW');
String ntd(num v) => '\$${money.format(v)}';
String pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

/// 品項金額（0101 以分分配時可能有小數）：整數照 [ntd]，有角分就顯示到分——
/// 這樣畫面上每一列加起來剛好等於小計，不會因為四捨五入差 1 元
final _moneyCents = NumberFormat('#,##0.00', 'zh_TW');
String ntdExact(num v) {
  final c = (v * 100).round();
  return c % 100 == 0 ? ntd(c ~/ 100) : '\$${_moneyCents.format(c / 100)}';
}
