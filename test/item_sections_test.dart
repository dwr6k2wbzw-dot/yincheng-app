// 2026-11-13 品項銷售分酒水／餐食兩區（老闆）：小計＝那一區品項加總（含服務費，＝每日營收酒水／餐食）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/widgets/item_sections.dart';
import 'package:yincheng_ops/theme.dart';
import 'package:yincheng_ops/widgets/format.dart';

Widget _app(Widget child) =>
    MaterialApp(theme: buildTheme(StorePalette.gold), home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  // 隱城 2026-11-12 實際分配結果的一部分
  const items = [
    ItemSale(name: 'Blood and Sand', qty: 3, amount: 1438, listAmount: 1350),
    ItemSale(name: 'Sicily Espresso Martini', qty: 2, amount: 959, listAmount: 900),
    ItemSale(name: 'Little Women', qty: 2, amount: 895, listAmount: 840),
    ItemSale(name: 'Vesper', qty: 2, amount: 895, listAmount: 840),
    ItemSale(name: '布布拉麵', isDrink: false, qty: 2, amount: 746, listAmount: 700),
    ItemSale(name: '關東煮', isDrink: false, qty: 1, amount: 298, listAmount: 280),
  ];

  testWidgets('酒水、餐食分兩區，各有小計；各自只先顯示前 3 名，可展開', (tester) async {
    await tester.pumpWidget(_app(const ItemSections(items: items, top: 3)));
    expect(find.text('酒水'), findsOneWidget);
    expect(find.text('餐食'), findsOneWidget);
    expect(find.text('小計 ${ntd(1438 + 959 + 895 + 895)}'), findsOneWidget);
    expect(find.text('小計 ${ntd(746 + 298)}'), findsOneWidget);
    expect(find.text('Vesper'), findsNothing);
    expect(find.text('關東煮'), findsOneWidget); // 餐食只有 2 項，全部顯示、沒有展開按鈕
    expect(find.text('全部 4 項'), findsOneWidget);
    await tester.tap(find.text('全部 4 項'));
    await tester.pump();
    expect(find.text('Vesper'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('只有酒水時不顯示餐食區', (tester) async {
    await tester.pumpWidget(_app(ItemSections(items: items.where((x) => x.isDrink).toList())));
    expect(find.text('餐食'), findsNothing);
  });

  test('含服務費金額讀 amount_net，舊資料庫沒有就用原價', () {
    final a = ItemSale.fromRow({'name': 'A', 'grp': 'drink', 'qty': 1, 'amount': 420, 'amount_net': 448});
    expect([a.amount, a.listAmount], [448, 420]);
    final b = ItemSale.fromRow({'name': 'B', 'grp': 'food', 'qty': 1, 'amount': 280});
    expect([b.amount, b.listAmount, b.isDrink], [280, 280, false]);
    final m = ItemSale.fromRow({'name': 'C', 'grp': 'drink', 'qty': 9, 'amount': 4000, 'amount_list': 3700, 'days': 4});
    expect([m.amount, m.listAmount, m.days], [4000, 3700, 4]);
  });
}
