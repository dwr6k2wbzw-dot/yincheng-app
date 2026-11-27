// 班表照片辨識走 API（ops 0153）：隱城、小城外這一份照舊（每小時同步），只有公版（SELF_SIGNUP）上傳完直接辨識
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/config.dart';
import 'package:yincheng_ops/data/demo_repository.dart';

void main() {
  test('兩家店這一份：照片辨識照舊是每小時同步（不是 api）', () async {
    final repo = DemoRepository();
    expect(AppConfig.selfSignup, isFalse);
    expect(await repo.shiftPhotoAiMode('s1'), 'subscription');
  });

  test('上傳照片 → 待辨識草稿；辨識 → 草稿好了；沒有待辨識的不能辨識', () async {
    final repo = DemoRepository();
    final m = DateTime(2032, 12);
    await expectLater(repo.readShiftPhotos('s1', m), throwsA(isA<Exception>()));
    await repo.uploadShiftPhoto('s1', m, Uint8List.fromList([0xff, 0xd8]));
    var d = await repo.shiftMonth('s1', m);
    expect(d.photos, hasLength(1));
    expect(d.draft?.isPending, isTrue);
    final cells = await repo.readShiftPhotos('s1', m);
    d = await repo.shiftMonth('s1', m);
    expect(d.draft?.isReady, isTrue);
    expect(d.draft?.cellCount, cells);
    expect(d.draft?.warnings, isNotEmpty);
    expect(await repo.applyShiftDraft(d.draft!), cells);
    expect((await repo.shiftMonth('s1', m)).draft, isNull);
  });
}
