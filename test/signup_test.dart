// 自助註冊（ops 0119）：欄位檢查跟資料庫同一套；資料庫回來的訊息顯示時拿掉最前面的代號。
import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/repository.dart';
import 'package:yincheng_ops/data/signup.dart';

void main() {
  test('店名、名字：空白不行、最多 40 個字、前後空白不算', () {
    expect(signupNameError('', '店名'), '請填店名');
    expect(signupNameError('   ', '你的名字'), '請填你的名字');
    expect(signupNameError('巷口小酒館', '店名'), isNull);
    expect(signupNameError('  ${'店' * 40}  ', '店名'), isNull);
    expect(signupNameError('店' * 41, '店名'), '店名最多 40 個字');
    // 表情符號一個算一個字（跟資料庫的 length() 一樣算字，不算位元組）
    expect(signupNameError('🍸' * 40, '店名'), isNull);
    expect(signupNameError('🍸' * 41, '店名'), isNotNull);
  });

  test('資料庫擋下來的訊息：顯示時拿掉 SIGNUP_ 代號', () {
    expect(friendlyError(Exception('PostgrestException(message: SIGNUP_TAKEN：這個店名已經有人用了，請換一個（例如加上地區或分店名）, code: 23505)')),
        '這個店名已經有人用了，請換一個（例如加上地區或分店名）');
    expect(friendlyError(Exception('PostgrestException(message: SIGNUP_UNVERIFIED：請先到信箱點確認信，完成 Email 驗證, code: 42501)')),
        '請先到信箱點確認信，完成 Email 驗證');
    expect(friendlyError(Exception('PostgrestException(message: SIGNUP_CLOSED：這裡不開放自己建立店家，請跟老闆要邀請碼, code: 42501)')),
        '這裡不開放自己建立店家，請跟老闆要邀請碼');
  });
}
