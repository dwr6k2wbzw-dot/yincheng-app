import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/line_bind.dart';

void main() {
  group('LINE 群組綁定代碼（ops 0156）', () {
    final now = DateTime(2026, 11, 27, 18, 0, 0);

    test('從資料庫回傳讀出代碼與到期時間', () {
      final c = LineBindCode.fromJson({'code': '01234567', 'expires_at': '2026-11-27T10:10:00Z'});
      expect(c.code, '01234567');
      expect(c.expiresAt.isUtc, isFalse);
      expect(c.expiresAt.toUtc(), DateTime.utc(2026, 11, 27, 10, 10));
    });

    test('群組裡要打的那一句', () {
      expect(LineBindCode('12345678', now).command('隱城'), '綁定 隱城 12345678');
    });

    test('倒數與過期', () {
      final c = LineBindCode('12345678', now.add(const Duration(minutes: 9, seconds: 5)));
      expect(c.remaining(now), '還有 9 分 05 秒');
      expect(c.expired(now), isFalse);
      expect(c.remaining(now.add(const Duration(minutes: 10))), '已過期，請重新產生');
      expect(c.expired(now.add(const Duration(minutes: 9, seconds: 5))), isTrue);
    });
  });
}
