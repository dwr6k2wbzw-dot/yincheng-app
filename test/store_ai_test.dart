import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/store_ai.dart';

void main() {
  group('店家自己的 AI（ops 0157）', () {
    test('三家都有建議模型、哪裡拿金鑰', () {
      expect(
          storeAiProviders.map((p) => p.label), ['Claude', 'OpenAI', 'Gemini']);
      for (final p in storeAiProviders) {
        expect(p.models, isNotEmpty);
        expect(storeAiModelProblem(p.models.first), isNull);
        expect(p.whereToGet, isNotEmpty);
      }
      expect(storeAiProviderFrom('openai'), StoreAiProvider.openai);
      expect(storeAiProviderFrom('mistral'), isNull);
    });

    test('模型名稱：跟資料庫同一套規則（開頭的 models/ 拿掉）', () {
      expect(storeAiModelProblem('models/gemini-2.5-flash'), isNull);
      expect(storeAiModelProblem(''), '請選或填一個模型');
      expect(storeAiModelProblem('gpt 5; drop'), isNotNull);
      expect(storeAiModelProblem('-gpt'), isNotNull);
      expect(storeAiModelProblem('a' * 81), isNotNull);
    });

    test('金鑰：整串、不能有空白、不能太短', () {
      expect(storeAiKeyProblem('sk-proj-0000000000000000000000ABCD'), isNull);
      expect(storeAiKeyProblem(''), '請貼上金鑰');
      expect(storeAiKeyProblem('sk-short'), isNotNull);
      expect(
          storeAiKeyProblem('sk-proj 0000000000000000000000ABCD'), isNotNull);
      expect(
          storeAiKeyProblem('sk-proj-000000000000000000000\nABCD'), isNotNull);
      expect(
          storeAiKeyProblem('  sk-proj-0000000000000000000000ABCD  '), isNull,
          reason: '前後空白會去掉');
    });

    test('資料庫那一列：只看得到哪一家、模型、末 4 碼、驗證時間', () {
      final s = StoreAiSetting.fromRow({
        'provider': 'gemini',
        'model': 'gemini-2.5-flash',
        'key_last4': 'WXYZ',
        'verified_at': '2026-11-27T10:00:00Z',
        'last_error': null,
      })!;
      expect(s.provider, StoreAiProvider.gemini);
      expect(s.keyLast4, 'WXYZ');
      expect(s.verifiedAt, DateTime.utc(2026, 11, 27, 10));
      expect(
          StoreAiSetting.fromRow(
              {'provider': 'x', 'model': 'm', 'key_last4': 'AAAA'}),
          isNull);
    });

    test('示範版：金鑰無效不存、成功只留末 4 碼、可以測試、可以清除', () async {
      final repo = DemoRepository();
      await repo.signIn('owner@demo', 'x');
      expect(await repo.storeAiSetting('yc'), isNull);
      final bad = await repo.saveStoreAi('yc', StoreAiProvider.openai,
          'gpt-5-mini', 'sk-bad-00000000000000000000000000');
      expect(bad.ok, isFalse);
      expect(bad.error, contains('OpenAI 的金鑰無效'));
      expect(await repo.storeAiSetting('yc'), isNull);
      final ok = await repo.saveStoreAi('yc', StoreAiProvider.gemini,
          'models/gemini-2.5-flash', 'AIza-demo-000000000000000000WXYZ');
      expect(ok.ok, isTrue);
      expect(ok.last4, 'WXYZ');
      final s = (await repo.storeAiSetting('yc'))!;
      expect(s.provider, StoreAiProvider.gemini);
      expect(s.model, 'gemini-2.5-flash');
      expect(s.keyLast4, 'WXYZ');
      expect((await repo.testStoreAi('yc')).ok, isTrue);
      await repo.clearStoreAi('yc');
      expect(await repo.storeAiSetting('yc'), isNull);
      expect((await repo.testStoreAi('yc')).ok, isFalse);
    });
  });
}
