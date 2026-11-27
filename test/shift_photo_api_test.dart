// 班表照片辨識走 API（ops 0153）：隱城、小城外這一份照舊（每小時同步），只有公版（SELF_SIGNUP）上傳完直接辨識
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/config.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/shift_photo_upload.dart';

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

  test('上傳途中切換月份：照片和辨識都還是上傳的那個月（Codex P2）', () async {
    final repo = _SlowUploadRepo();
    var shownMonth = DateTime(2032, 12); // 畫面上目前的月份
    final readCalls = <String>[];
    final done = uploadShiftPhotoThenRead(
      repo,
      storeId: 's1',
      month: shownMonth,
      bytes: Uint8List.fromList([0xff, 0xd8]),
      read: (s, m) async => readCalls.add('$s ${m.year}-${m.month}'),
    );
    shownMonth = DateTime(2033, 1); // 上傳還沒好，使用者切到下個月
    expect(readCalls, isEmpty, reason: '上傳完成前不辨識');
    repo.gate.complete();
    await done;
    expect(shownMonth, DateTime(2033, 1));
    expect(repo.uploadedMonths, ['2032-12']);
    expect(readCalls, ['s1 2032-12']);
  });

  test('沒有給辨識（兩家店的每小時同步）：只上傳', () async {
    final repo = _SlowUploadRepo()..gate.complete();
    await uploadShiftPhotoThenRead(repo, storeId: 's1', month: DateTime(2032, 12), bytes: Uint8List.fromList([1]));
    expect(repo.uploadedMonths, ['2032-12']);
  });
}

class _SlowUploadRepo extends DemoRepository {
  final gate = Completer<void>();
  final uploadedMonths = <String>[];
  @override
  Future<void> uploadShiftPhoto(String storeId, DateTime month, Uint8List jpeg) async {
    await gate.future;
    uploadedMonths.add('${month.year}-${month.month}');
  }
}

