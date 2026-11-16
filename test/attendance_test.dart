// 2026-11-15 班表第一階段：QR 打卡（隱城試行）、補登、匯出（老闆）。
// 跨夜、一天兩段、跨月、過期碼、重複掃、三種身分權限的完整驗證在私人 repo 的 tests/25_attendance.sql（資料庫端）；
// 這裡驗 App 端：打卡網址、補登換算時間、班表帶入、CSV 匯出（打卡機畫面在 attendance_kiosk_test.dart，要在瀏覽器跑）。要在台北、UTC、紐約三個時區都過。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/attendance_models.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yincheng_ops/services/attendance_csv.dart';
import 'package:yincheng_ops/services/missed_punch.dart';

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
      // 老闆 2026-11-15：待確認的確認前不計入工時，CSV 要標出來
      final pending = AttendanceExportRow(
          businessDate: DateTime(2026, 11, 1),
          personName: '小魚',
          punchType: 'out',
          punchedAt: DateTime.utc(2026, 11, 1, 17, 0),
          storeName: '隱城',
          source: 'qr',
          status: 'pending',
          flags: 'expired',
          counted: false,
          punchId: 'p3');
      expect(buildAttendanceCsv([pending]).split('\r\n')[1], endsWith(',待確認（不算）,p3'));
      expect(attendanceCsvBytes(rows).take(3), [0xEF, 0xBB, 0xBF]);
      expect(attendanceCsvName('隱城', DateTime(2026, 11, 1), DateTime(2026, 11, 15)), '出勤_隱城_20261101-20261115.csv');
    });
  });

  group('程式審查 2026-11-15 修正', () {
    test('打卡機拿碼：資料庫回 error 列（密鑰錯、嘗試太多次）要變成錯誤，不能當成碼', () {
      expect(
          () => KioskCode.fromRow({'error': '嘗試太多次，請 10 分鐘後再試', 'server_time': '2026-11-15T00:00:00Z'}),
          throwsA(isA<KioskCodeError>().having((e) => e.message, 'message', contains('嘗試太多次'))));
      final ok = KioskCode.fromRow({
        'store_name': '隱城', 'kiosk_name': '吧台', 'win': 5, 'code': 'ab',
        'server_time': '2026-11-15T00:00:00Z', 'valid_until': '2026-11-15T00:00:30Z', 'error': null,
      });
      expect(ok.code, 'ab');
    });

    test('待確認的段落：確認前不計入工時', () {
      final s = AttendanceSession.fromRow({
        'person_id': 'p', 'person_name': '小魚', 'business_date': '2026-11-14',
        'in_at': '2026-11-14T10:00:00Z', 'out_at': '2026-11-14T14:00:00Z', 'minutes': 240, 'pending': true, 'counted_minutes': 0,
      });
      expect((s.minutes, s.countedMinutes), (240, 0));
      // 舊版資料庫沒有 counted_minutes：待確認一樣算 0
      expect(AttendanceSession.fromRow({'person_id': 'p', 'business_date': '2026-11-14', 'minutes': 60, 'pending': true}).countedMinutes, 0);
      expect(AttendanceSession.fromRow({'person_id': 'p', 'business_date': '2026-11-14', 'minutes': 60, 'pending': false}).countedMinutes, 60);
    });

    test('打卡歷程、補登人選的顯示文字', () {
      PunchHistoryEntry h(String a, [String? d]) => PunchHistoryEntry(at: DateTime.utc(2026), action: a, decision: d);
      expect([h('punch'), h('amendment_request'), h('amendment_approve'), h('review', 'confirmed'), h('review', 'rejected')].map((e) => e.label),
          ['打卡', '申請補登', '核准補登', '確認', '不採用']);
      expect(const AttendancePerson(personId: 'x', name: '阿傑', homeStoreName: '小城外', crossStore: true).label, '阿傑（小城外支援）');
      expect(const AttendancePerson(personId: 'y', name: '阿明').label, '阿明');
    });

    test('掃碼後去收信再登入：記號在 24 小時內 → 提示沒打到；看過就清掉', () async {
      SharedPreferences.setMockInitialValues({});
      final t = DateTime(2026, 11, 15, 20);
      expect(await takeMissedPunch(now: t), isFalse);
      await markPunchStarted(t);
      expect(await takeMissedPunch(now: t.add(const Duration(minutes: 10))), isTrue);
      expect(await takeMissedPunch(now: t.add(const Duration(minutes: 11))), isFalse, reason: '看過就清掉');
      await markPunchStarted(t);
      expect(await takeMissedPunch(now: t.add(const Duration(hours: 25))), isFalse, reason: '太久以前的不提示');
      await markPunchStarted(t);
      await clearPunchStarted(); // 同一頁登入、真的打了卡
      expect(await takeMissedPunch(now: t), isFalse);
    });

    test('示範資料：綁定沒確認 → 不算本人、不能打卡；只有老闆能確認', () async {
      final pending = DemoRepository();
      await pending.signIn('unverified-staff@x', 'x');
      final me = await pending.attendanceMe('yc');
      expect(me?.bindingPending, isTrue);
      expect(me?.personId, isNull);
      await expectLater(pending.punch(const PunchLink(_k, 1, 'x')), throwsA(anything));

      final staff = DemoRepository();
      await staff.signIn('staff@x', 'x');
      await expectLater(staff.verifyBinding('f1', 'demo-f1'), throwsA(anything));

      final owner = DemoRepository();
      await owner.signIn('owner@x', 'x');
      final before = (await owner.staffDirectory('yc')).firstWhere((s) => s.personId == 'f1');
      expect((before.userId, before.userVerified), ('demo-f1', false));
      await expectLater(owner.verifyBinding('f1', 'someone-else'), throwsA(anything), reason: '綁定換人了要重新整理');
      await owner.verifyBinding('f1', 'demo-f1');
      expect((await owner.staffDirectory('yc')).firstWhere((s) => s.personId == 'f1').userVerified, isTrue);
    });

    test('第二輪：沒開打卡的店，老闆仍可管理員工資料（員工沒有入口）', () async {
      final owner = DemoRepository();
      await owner.signIn('owner@x', 'x');
      final me = await owner.attendanceMe('xc');
      expect((me?.enabled, me?.canManage), (false, true));
      final staff = DemoRepository();
      await staff.signIn('staff@x', 'x');
      expect((await staff.attendanceMe('xc'))?.canManage, isFalse);
    });

    test('示範資料：已審過的可以重審，歷程留著每一次；補登人選有來支援的別家店員工', () async {
      final repo = DemoRepository();
      await repo.signIn('owner@x', 'x');
      await repo.reviewPunch('demo2', true, '有看到人');
      await repo.reviewPunch('demo2', false, '重看監視器，其實沒來');
      final hist = await repo.punchHistory('demo2');
      expect(hist.where((h) => h.action == 'review').map((h) => (h.label, h.reason)), [('確認', '有看到人'), ('不採用', '重看監視器，其實沒來')]);
      final t = DateTime(2026, 11, 15);
      final row = (await repo.attendanceExport('yc', t.subtract(const Duration(days: 30)), t)).firstWhere((r) => r.punchId == 'demo2');
      expect((row.review, row.counted), ('rejected', false));
      final people = await repo.attendancePeople('yc', t.subtract(const Duration(days: 30)), t);
      expect(people.where((p) => p.crossStore).map((p) => p.label), contains('阿傑（小城外支援）'));
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

  group('到職日、離職日（員工資料頁，2026-11-15 老闆）', () {
    test('離職日只在停用或已填離職日的人顯示', () {
      StaffEntry s({bool active = true, DateTime? leave}) =>
          StaffEntry(personId: 'p', name: '示範', kind: 'full', active: active, leaveDate: leave);
      expect(s().showsLeaveDate, isFalse);
      expect(s(active: false).showsLeaveDate, isTrue);
      expect(s(leave: DateTime(2026, 10, 31)).showsLeaveDate, isTrue);
      expect(s(active: false, leave: DateTime(2026, 10, 31)).showsLeaveDate, isTrue);
    });

    test('示範資料：老闆、店長存到職日後一覽讀得到，可清掉；不會動到離職日；員工不能改', () async {
      SharedPreferences.setMockInitialValues({});
      for (final email in ['owner@x', 'manager@x']) {
        final repo = DemoRepository();
        await repo.signIn(email, 'x');
        Future<StaffEntry> f1() async => (await repo.staffDirectory('yc')).firstWhere((x) => x.personId == 'f1');
        expect((await f1()).hireDate, isNull);
        await repo.saveHireDate('yc', 'f1', DateTime(2025, 4, 1));
        expect((await f1()).hireDate, DateTime(2025, 4, 1), reason: email);
        expect((await f1()).leaveDate, isNull);
        await repo.saveHireDate('yc', 'f1', null);
        expect((await f1()).hireDate, isNull);
      }
      final staff = DemoRepository();
      await staff.signIn('staff@x', 'x');
      await expectLater(staff.saveHireDate('yc', 'f0', DateTime(2025, 1, 1)), throwsA(anything));
    });

    test('示範資料有一位已停用的人，帶離職日（老闆看得到、員工看不到）', () async {
      SharedPreferences.setMockInitialValues({});
      final owner = DemoRepository();
      await owner.signIn('owner@x', 'x');
      final left = (await owner.staffDirectory('yc')).firstWhere((x) => x.personId == 'x0');
      expect((left.active, left.leaveDate, left.showsLeaveDate), (false, DateTime(2026, 10, 31), true));
      final staff = DemoRepository();
      await staff.signIn('staff@x', 'x');
      expect((await staff.staffDirectory('yc')).map((x) => x.personId), ['f0']);
    });
  });
}

(int, int, int, int, int) toTaipeiParts(DateTime t) {
  final u = t.toUtc().add(const Duration(hours: 8));
  return (u.year, u.month, u.day, u.hour, u.minute);
}
