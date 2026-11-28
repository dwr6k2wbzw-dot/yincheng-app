// 盤點品項搬家（ops 0167）：看懂檔案、範本、匯出、示範資料的匯入／復原。品項都是虛構的。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/booking_import.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/product_import.dart';
import 'package:yincheng_ops/data/purchase_items_math.dart';
import 'package:yincheng_ops/services/product_xlsx.dart';
import 'package:yincheng_ops/services/reservation_xlsx.dart';

void main() {
  group('看懂檔案', () {
    test('表頭各種寫法、前面有標題列、空白列跳過', () {
      final t = readProductImportTable([
        ['我的品項清單'],
        [],
        ['名稱', ' 類別 ', 'Unit', '安全庫存', '盤點頻率', '進價'],
        ['琴酒', '酒水', '瓶', '2', '每天盤', 'NT\$1,200'],
        ['', '', '', '', '', ''],
        ['檸檬', '餐食', '顆', '20', 'weekly', ''],
      ]);
      expect(t.problem, isNull);
      expect(t.rows.length, 2);
      expect(t.hasCost, isTrue);
      final a = t.rows.first;
      expect([a.line, a.name, a.category, a.unit, a.par, a.cycle, a.cost],
          [4, '琴酒', '酒水', '瓶', '2', '每天', '1200']);
      expect(t.rows.last.line, 6);
      expect(t.rows.last.cycle, '每週');
      expect(t.rows.last.toJson().containsKey('cost_price'), isFalse,
          reason: '沒填成本價就不送這個欄位');
    });

    test('缺品名、單位、分類那一欄 → 說清楚缺哪一欄', () {
      expect(
          readProductImportTable([
            ['單位', '分類']
          ]).problem,
          contains('品名'));
      expect(
          readProductImportTable([
            ['品名', '分類']
          ]).problem,
          contains('單位'));
      expect(
          readProductImportTable([
            ['品名', '單位']
          ]).problem,
          contains('分類'));
    });

    test('多久盤一次、數字的整理；看不懂的照原樣交給資料庫', () {
      expect(normCycle(''), '');
      expect(normCycle('不追蹤'), '');
      expect(normCycle('每日'), '每天');
      expect(normCycle('每周盤'), '每週');
      expect(normCycle('每月'), '每月');
      expect(normProductNumber('1,000'), '1000');
      expect(normProductNumber('12.5元'), '12.5');
      expect(normProductNumber('很多'), '很多');
      expect(normProductNumber(''), '');
    });

    test('沒有成本價那一欄、或那一欄全空 → hasCost 是 false', () {
      expect(
          readProductImportTable([
            ['品名', '單位', '分類'],
            ['A', '瓶', '酒水']
          ]).hasCost,
          isFalse);
      expect(
          readProductImportTable([
            ['品名', '單位', '分類', '成本價'],
            ['A', '瓶', '酒水', '']
          ]).hasCost,
          isFalse);
    });

    test('資料庫回的 row（第幾個送出的列）換成檔案裡的列號', () {
      final rows = [
        const ProductImportRow(line: 3, name: 'A'),
        const ProductImportRow(line: 7, name: 'B'),
      ];
      final r = productImportResult({
        'batch': null,
        'ready': 1,
        'errors': [
          {'row': 2, 'message': '沒有單位'}
        ],
        'skipped': [
          {'row': 1, 'reason': '已經有這個品項'}
        ],
      }, rows);
      expect(r.ready, 1);
      expect(r.errors.single.line, 7);
      expect(r.errors.single.text, '沒有單位');
      expect(r.skipped.single.line, 3);
    });
  });

  group('範本與匯出', () {
    test('老闆的範本有成本價、店長的沒有；讀回來看得懂', () {
      final owner = readXlsxCells(buildProductTemplate(withCost: true),
          accept: (c) => readProductImportTable(c).problem == null);
      final mgr = readXlsxCells(buildProductTemplate(),
          accept: (c) => readProductImportTable(c).problem == null);
      expect(owner.cells.first, [...productImportColumns, productCostColumn]);
      expect(mgr.cells.first, productImportColumns);
      final t = readProductImportTable(owner.cells);
      expect(t.problem, isNull);
      expect(t.rows.length, 3);
      expect(t.hasCost, isTrue);
      expect(readProductImportTable(mgr.cells).hasCost, isFalse);
    });

    test('匯出的第一頁可以直接拿去匯入；報價拿掉的不列；沒給成本價就沒有那一欄', () {
      final products = [
        Product('a', '琴酒', '酒水', '瓶', parLevel: 2, countCycle: 'daily'),
        Product('b', '檸檬', '餐食', '顆', countCycle: 'weekly'),
      ];
      final last = {
        'a': LastCount(1.5, DateTime(2026, 11, 20), by: '示範店員'),
      };
      ItemQuote q(String name, {bool hidden = false}) => ItemQuote(
            key: name,
            name: name,
            unit: '瓶',
            group: 'drink',
            price: 780,
            date: DateTime(2026, 11, 1),
            rawName: name,
            rawUnit: '瓶',
            rawPrice: 780,
            hidden: hidden,
          );
      final bytes = buildProductsXlsx(
        products: products,
        lastCounts: last,
        costs: {'a': 1200, 'b': null},
        quotes: [q('琴酒'), q('拿掉的', hidden: true)],
      );
      final x = readXlsxCells(bytes,
          accept: (c) => readProductImportTable(c).problem == null);
      expect(x.problem, isNull);
      expect(x.cells.first.take(6).toList(),
          [...productImportColumns, productCostColumn]);
      expect(x.cells[1].take(9).toList(),
          ['琴酒', '瓶', '酒水', '2', '每天', '1200', '1.5', '2026-11-20', '示範店員']);
      final t = readProductImportTable(x.cells);
      expect(t.rows.map((r) => r.cycle).toList(), ['每天', '每週']);

      final noCost = readXlsxCells(
          buildProductsXlsx(products: products, lastCounts: last),
          accept: (c) => readProductImportTable(c).problem == null);
      expect(noCost.cells.first.contains(productCostColumn), isFalse,
          reason: '店長匯出不含成本價');
    });

    test('訂位搬家讀 Excel 的預設行為不變（不帶 accept 時找有日期那一頁）', () {
      final x =
          readXlsxCells(buildImportTemplate(today: DateTime(2026, 11, 27)));
      expect(readImportTable(x.cells).problem, isNull);
      expect(x.cells.first.first, '日期');
    });
  });

  group('示範資料：匯入、重送、整批復原', () {
    test('預覽不寫入；同名略過；重送回同一批；復原只停用', () async {
      final repo = DemoRepository();
      final before = (await repo.products('yc')).length;
      final rows = readProductImportTable([
        ['品名', '單位', '分類', '安全量', '多久盤一次', '成本價'],
        ['新琴酒', '瓶', '酒水', '1', '每天', '900'],
        ['  新  琴酒 ', '瓶', '酒水', '', '', ''],
        ['Campari', '瓶', '酒水', '', '', ''],
        ['新檸檬', '顆', '餐食', '', '', ''],
      ]).rows;
      final p = await repo.previewProductImport('yc', rows);
      expect(p.ready, 2);
      expect(p.skipped.map((e) => e.line).toList(), [3, 4]);
      expect((await repo.products('yc')).length, before, reason: '預覽不寫入');

      final r = await repo.importProducts('yc', rows, 'a.xlsx', 'req-1');
      expect(r.inserted, 2);
      expect((await repo.products('yc')).length, before + 2);
      final again = await repo.importProducts('yc', rows, 'a.xlsx', 'req-1');
      expect(again.repeat, isTrue);
      expect((await repo.products('yc')).length, before + 2);

      final costs = await repo.productCosts('yc');
      final id =
          (await repo.products('yc')).firstWhere((x) => x.name == '新琴酒').id;
      expect(costs[id], 900);

      final batches = await repo.productImports('yc');
      expect(batches.single.inserted, 2);
      expect(await repo.undoProductImport(batches.single.id), 2);
      expect((await repo.products('yc')).length, before);
      expect((await repo.productImports('yc')).single.undoneCount, 2);
      expect(() => repo.undoProductImport(batches.single.id), throwsException);

      final redo = await repo.previewProductImport('yc', rows);
      expect(redo.ready, 0);
      expect(redo.skipped.first.text, contains('已停用'));
    });

    test('一列有問題 → 整批不匯入', () async {
      final repo = DemoRepository();
      final before = (await repo.products('yc')).length;
      final rows = readProductImportTable([
        ['品名', '單位', '分類', '多久盤一次'],
        ['甲', '瓶', '酒水', ''],
        ['乙', '', '酒水', ''],
        ['丙', '瓶', '酒水', '每月'],
      ]).rows;
      final r = await repo.importProducts('yc', rows, null, 'req-2');
      expect(r.batchId, isNull);
      expect(r.errors.map((e) => e.line).toList(), [3, 4]);
      expect((await repo.products('yc')).length, before);
      expect(await repo.productImports('yc'), isEmpty);
    });
  });

  test('ImportResult 共用（訂位、品項同一個型別）', () {
    const r = ImportResult(ready: 3);
    expect(r.errors, isEmpty);
  });
}
