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
    expect([a.net, b.net], [true, false]);
    final m = ItemSale.fromRow({'name': 'C', 'grp': 'drink', 'qty': 9, 'amount': 3700, 'amount_net': 4000, 'days': 4});
    expect([m.amount, m.listAmount, m.days, m.net], [4000, 3700, 4, true]);
    // 鎖帳月份（審查 P2）：月累計 amount_net 是 null
    final l = ItemSale.fromRow({'name': 'D', 'grp': 'drink', 'qty': 2, 'amount': 600, 'amount_net': null, 'days': 1});
    expect([l.amount, l.listAmount, l.net], [600, 600, false]);
  });

  // 審查 P2：鎖帳月份沒回填含服務費金額，不能跟有分攤的混在一起、也不能標「含服務費」
  const mixed = [
    ItemSale(name: 'A', qty: 1, amount: 1100, listAmount: 1000),
    ItemSale(name: 'B', qty: 1, amount: 700, listAmount: 700, net: false),
    ItemSale(name: 'C', isDrink: false, qty: 1, amount: 330, listAmount: 300),
  ];

  test('pricedItems：有一項沒分攤就整份改原價、重新排序；全部有才用含服務費', () {
    final p = pricedItems(mixed);
    expect(p.net, false);
    expect([for (final x in p.items) '${x.name}=${x.amount}'], ['A=1000.0', 'B=700.0', 'C=300.0']);
    final q = pricedItems([mixed[0], mixed[2]]);
    expect(q.net, true);
    expect([for (final x in q.items) x.amount], [1100, 330]);
  });

  testWidgets('單日品項：沒分攤的日子標「原價／尚未分攤」，小計是原價', (tester) async {
    await tester.pumpWidget(_app(const DayItemsBlock(items: mixed)));
    expect(find.text('品項銷售・原價／尚未分攤'), findsOneWidget);
    expect(find.text('品項銷售・含服務費'), findsNothing);
    expect(find.text(r'小計 $1,700'), findsOneWidget);
    expect(find.text(r'小計 $300'), findsOneWidget);
    await tester.pumpWidget(_app(DayItemsBlock(items: [mixed[0], mixed[2]])));
    expect(find.text('品項銷售・含服務費'), findsOneWidget);
    expect(find.text(r'小計 $1,100'), findsOneWidget);
  });

  testWidgets('金額有角分時顯示到分，各列加起來＝小計（0101 以分分配）', (tester) async {
    await tester.pumpWidget(_app(const ItemSections(items: [
      ItemSale(name: 'A', qty: 1, amount: 428.79, listAmount: 400),
      ItemSale(name: 'B', qty: 1, amount: 571.71, listAmount: 600),
    ])));
    expect(find.text(r'$428.79'), findsOneWidget);
    expect(find.text(r'$571.71'), findsOneWidget);
    expect(find.text(r'小計 $1,000.50'), findsOneWidget);
    expect(ntdExact(1438), ntd(1438)); // 整數照舊
  });

  group('月累計', () {
    final ichef = {DateTime(2026, 11, 10), DateTime(2026, 11, 12)};
    final entries = [
      for (final d in [9, 10, 11, 12]) RevenueEntry(bizDate: DateTime(2026, 11, d), cash: 1000),
      RevenueEntry(bizDate: DateTime(2026, 11, 13), cash: 1000), // 今天還沒結束，不算未計入
    ];

    testWidgets('MonthItemsCard：天數、未計入範圍、兩區小計', (tester) async {
      final today = DateTime(2026, 11, 13);
      await tester.pumpWidget(_app(MonthItemsCard(
        month: DateTime(2026, 11),
        items: items,
        ichefDays: ichef,
        missing: MonthItemsCard.missingDays(entries, ichef, DateTime(2026, 11), today),
      )));
      expect(find.text('11 月銷售品項累計'), findsOneWidget);
      expect(find.text('iCHEF 2 天・到 11/12・金額含服務費・每天早上更新'), findsOneWidget);
      expect(find.text('未計入（那天沒有 iCHEF 資料）：11/9、11/11'), findsOneWidget);
      expect(find.text('小計 ${ntd(1438 + 959 + 895 + 895)}'), findsOneWidget);
      expect(MonthItemsCard.ranges([DateTime(2026, 11, 1), DateTime(2026, 11, 2), DateTime(2026, 11, 3), DateTime(2026, 11, 5)]),
          '11/1～11/3、11/5');
    });

    testWidgets('鎖帳月份（審查 P2）：整張卡改原價、標「原價／尚未分攤」並說明', (tester) async {
      await tester.pumpWidget(_app(MonthItemsCard(month: DateTime(2026, 11), items: mixed, ichefDays: ichef)));
      expect(find.text('iCHEF 2 天・到 11/12・金額原價／尚未分攤・每天早上更新'), findsOneWidget);
      expect(find.textContaining('金額含服務費'), findsNothing);
      expect(find.textContaining('已鎖帳的月份不回填'), findsOneWidget);
      expect(find.text(r'小計 $1,700'), findsOneWidget);
    });

    testWidgets('下拉更新：資料庫回傳不同金額後，月累計跟著更新', (tester) async {
      var amount = 1000.0;
      final calls = <String>[];
      Future<List<ItemSale>> load(String store, DateTime m) async {
        calls.add('$store ${m.month}');
        return [ItemSale(name: 'Gimlet', qty: 2, amount: amount, listAmount: amount)];
      }

      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(StorePalette.gold),
          home: Scaffold(body: _Harness(load: load, entries: entries, ichef: ichef))));
      await tester.pumpAndSettle();
      expect(find.text('小計 ${ntd(1000)}'), findsOneWidget);

      // 一般重畫（例如展開某一天）不重新查詢
      await tester.tap(find.text('重畫'));
      await tester.pumpAndSettle();
      expect(calls, ['yc 11']);

      amount = 2500;
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(calls, ['yc 11', 'yc 11']);
      expect(find.text('小計 ${ntd(1000)}'), findsNothing);
      expect(find.text('小計 ${ntd(2500)}'), findsOneWidget);
    });

    testWidgets('換店、跨月都重新查詢', (tester) async {
      final calls = <String>[];
      Future<List<ItemSale>> load(String store, DateTime m) async {
        calls.add('$store ${m.year}/${m.month}');
        return const [ItemSale(name: 'Gimlet', qty: 1, amount: 100, listAmount: 100)];
      }

      final h = GlobalKey<_HarnessState>();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Harness(key: h, load: load, entries: entries, ichef: ichef))));
      await tester.pumpAndSettle();
      h.currentState!.set(() => h.currentState!.store = 'xc');
      await tester.pumpAndSettle();
      h.currentState!.set(() => h.currentState!.today = DateTime(2026, 12, 2)); // 12/2 看的是 12 月（到 12/1）
      await tester.pumpAndSettle();
      expect(calls, ['yc 2026/11', 'xc 2026/11', 'xc 2026/12']);
      expect(find.text('12 月銷售品項累計'), findsOneWidget);
    });

    testWidgets('查詢失敗顯示錯誤和重試，不當成沒有資料', (tester) async {
      var fail = true;
      Future<List<ItemSale>> load(String store, DateTime m) async {
        if (fail) throw Exception('網路中斷');
        return const [ItemSale(name: 'Gimlet', qty: 1, amount: 100, listAmount: 100)];
      }

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Harness(load: load, entries: entries, ichef: ichef))));
      await tester.pumpAndSettle();
      expect(find.textContaining('11 月銷售品項累計載入失敗'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('重試'));
      await tester.pumpAndSettle();
      expect(find.textContaining('載入失敗'), findsNothing);
      expect(find.text('11 月銷售品項累計'), findsOneWidget);
    });
  });
}

/// 模擬營收頁：下拉更新時 version +1（同 RevenueScreen._reload）
class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.load, required this.entries, required this.ichef});
  final MonthItemsLoader load;
  final List<RevenueEntry> entries;
  final Set<DateTime> ichef;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int version = 0;
  String store = 'yc';
  DateTime today = DateTime(2026, 11, 13);
  void set(VoidCallback f) => setState(f);

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => setState(() => version++),
        child: ListView(children: [
          TextButton(onPressed: () => setState(() {}), child: const Text('重畫')),
          MonthItemsSection(
            storeId: store,
            version: version,
            load: widget.load,
            entries: widget.entries,
            ichef: widget.ichef,
            today: () => today,
          ),
        ]),
      );
}
