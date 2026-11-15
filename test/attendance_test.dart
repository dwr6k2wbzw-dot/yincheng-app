// 2026-11-15 班表第一階段：QR 打卡（隱城試行）、補登、匯出（老闆）。
// 跨夜、一天兩段、跨月、過期碼、重複掃、三種身分權限的完整驗證在私人 repo 的 tests/25_attendance.sql（資料庫端）；
// 這裡驗 App 端：打卡網址、補登換算時間、班表帶入、CSV 匯出（打卡機畫面在 attendance_kiosk_test.dart，要在瀏覽器跑）。要在台北、UTC、紐約三個時區都過。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/attendance_models.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/services/attendance_csv.dart';

const _k = '0f8fad5b-d9cb-469f-a165-70867728950e';

void main() {
  group('打卡網址', () {
    test('完整網址、只有 #/punch 那段都看得懂，來回一致', () {
      const base = 'https://dwr6k2wbzw-dot.github.io/yincheng-app/';
      final url = const PunchLink(_k, 59400123, 'a1b2c3d4e5f60718').toUrl(base);
      expect(url, '$base#/punch?k=$_k&w=59400123&c=a1b2c3d4e5f60718');
      final p = PunchLink.parse(url)!;
      expect((p.kiosk, p.window, p.code), (_k, 59400123, 'a1b2c3d4e5f60718'));
      expect(PunchLink.parse('#/punch?k=${_k.toUpperCase()}&w=1&c=x')!.kiosk, _k);
    });

    test('別的 QR 碼、缺欄位、打卡機代號不是 uuid 都不收', () {
      for (final s in [
        'https://example.com/',
        'WIFI:S:隱城;T:WPA;P:12345678;;',
        '#/punch?k=$_k&w=1',
        '#/punch?k=$_k&c=abc',
        '#/punch?k=not-a-uuid&w=1&c=abc',
        '#/punch?k=$_k&w=abc&c=abc',
        '#/punch?k=$_k&w=1&c=${'x' * 65}',
      ]) {
        expect(PunchLink.parse(s), isNull, reason: s);
      }
    });
  });

  group('補登換算時間（台北，早上 6 點換營業日）', () {
    final biz = DateTime(2026, 11, 14);
    test('晚上 20:30 是當天', () {
      expect(taipeiInstant(biz, 20, 30), DateTime.utc(2026, 11, 14, 12, 30));
    });
    test('跨夜：凌晨 02:15 算隔天凌晨', () {
      expect(taipeiInstant(biz, 2, 15), DateTime.utc(2026, 11, 14, 18, 15));
    });
    test('跨月：10/31 營業日的凌晨 01:00 是 11/1', () {
      expect(taipeiInstant(DateTime(2026, 10, 31), 1, 0), DateTime.utc(2026, 10, 31, 17, 0));
      expect(toTaipeiParts(taipeiInstant(DateTime(2026, 10, 31), 1, 0)), (2026, 11, 1, 1, 0));
    });
    test('跨年：12/31 營業日的 05:59 是隔年 1/1；06:00 已是當天早上', () {
      expect(toTaipeiParts(taipeiInstant(DateTime(2026, 12, 31), 5, 59)), (2027, 1, 1, 5, 59));
      expect(toTaipeiParts(taipeiInstant(DateTime(2026, 12, 31), 6, 0)), (2026, 12, 31, 6, 0));
    });
  });

  group('從班表帶入', () {
    const codes = {'A': '18:00-02:00', 'B': '14:00-22:00'};
    test('時段、班別代碼都看得懂；跨夜時段照原樣給', () {
      expect(scheduleTimes('19:30-00:30', codes), (inH: 19, inM: 30, outH: 0, outM: 30));
      expect(scheduleTimes('A', codes), (inH: 18, inM: 0, outH: 2, outM: 0));
    });
    test('休假、沒時段、亂填的回 null', () {
      for (final m in [null, 'V', '休', 'C', '25:00-26:00', '18:00']) {
        expect(scheduleTimes(m, codes), isNull, reason: '$m');
      }
    });
  });

  group('匯出 CSV', () {
    test('Excel 公式注入加 \'，逗號、引號、換行要包起來', () {
      expect(csvCell('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
      expect(csvCell('+886912'), "'+886912");
      expect(csvCell('-1'), "'-1");
      expect(csvCell('@SUM(A1)'), "'@SUM(A1)");
      expect(csvCell('忘記打卡，補登'), '忘記打卡，補登'); // 全形逗號不用包
      expect(csvCell('a,b'), '"a,b"');
      expect(csvCell('第一行\n第二行'), '"第一行\n第二行"');
      expect(csvCell(null), '');
    });

    test('時間是台北時間、跨夜下班照營業日、開頭有 BOM', () {
      final rows = [
        AttendanceExportRow(
            businessDate: DateTime(2026, 10, 31),
            personName: '小安',
            punchType: 'in',
            punchedAt: DateTime.utc(2026, 10, 31, 10, 0),
            storeName: '隱城',
            source: 'qr',
            status: 'ok',
            flags: '',
            counted: true,
            punchId: 'p1'),
        AttendanceExportRow(
            businessDate: DateTime(2026, 10, 31),
            personName: '小安',
            punchType: 'out',
            punchedAt: DateTime.utc(2026, 10, 31, 18, 5),
            storeName: '隱城',
            source: 'qr',
            status: 'pending',
            flags: 'expired duplicate',
            review: 'rejected',
            reviewReason: '=重複',
            counted: false,
            punchId: 'p2'),
      ];
      final lines = buildAttendanceCsv(rows).split('\r\n');
      expect(lines.first.split(',').length, 13);
      expect(lines[1], startsWith('2026-10-31,小安,上班,2026-10-31 18:00:00,隱城,QR,正常,,,,,算,p1'));
      expect(lines[2], contains('2026-10-31,小安,下班,2026-11-01 02:05:00,隱城,QR,待確認,'));
      expect(lines[2], contains(",不採用,'=重複,,不算,p2"));
      expect(attendanceCsvBytes(rows).take(3), [0xEF, 0xBB, 0xBF]);
      expect(attendanceCsvName('隱城', DateTime(2026, 11, 1), DateTime(2026, 11, 15)), '出勤_隱城_20261101-20261115.csv');
    });
  });

  test('示範資料：上班、下班輪流；2 分鐘內重掃標待確認', () async {
    final repo = DemoRepository();
    const link = PunchLink(_k, 1, 'x');
    final a = await repo.punch(link), b = await repo.punch(link);
    expect(a.status, anyOf('ok', 'pending'));
    expect(b.status, 'pending');
    expect(b.flags, contains('duplicate'));
  });
}

(int, int, int, int, int) toTaipeiParts(DateTime t) {
  final u = t.toUtc().add(const Duration(hours: 8));
  return (u.year, u.month, u.day, u.hour, u.minute);
}
