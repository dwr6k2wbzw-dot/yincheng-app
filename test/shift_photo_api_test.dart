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
    final done = uploadShiftPhotoThenRead(repo, storeId: 's1', month: shownMonth, bytes: Uint8List.fromList([0xff, 0xd8]), read: true);
    shownMonth = DateTime(2033, 1); // 上傳還沒好，使用者切到下個月
    expect(repo.readMonths, isEmpty, reason: '上傳完成前不辨識');
    repo.gate.complete();
    final r = await done;
    expect(shownMonth, DateTime(2033, 1));
    expect(repo.uploadedMonths.last, 's1 2032-12');
    expect(repo.readMonths, ['s1 2032-12']);
    expect(r.read, isTrue);
    expect(r.cells, 5);
  });

  test('上傳途中畫面被關掉（離開班表頁、切換店）：辨識照樣啟動，不碰畫面（Codex P2 第二輪）', () async {
    final repo = _SlowUploadRepo();
    var screenAlive = true;
    var touchedScreenAfterClose = false;
    final done = uploadShiftPhotoThenRead(
      repo,
      storeId: 's1',
      month: DateTime(2032, 12),
      bytes: Uint8List.fromList([1]),
      read: true,
      // 跟班表頁一樣：畫面不在就不碰它
      onUploaded: () {
        if (!screenAlive) return;
        touchedScreenAfterClose = true;
      },
    );
    screenAlive = false; // 上傳還沒好，畫面就被關掉
    repo.gate.complete();
    final r = await done;
    expect(repo.readMonths, ['s1 2032-12'], reason: '辨識要照樣啟動');
    expect(r.read, isTrue);
    expect(touchedScreenAfterClose, isFalse);
  });

  test('辨識失敗：錯誤丟回給呼叫的人（不吞掉）', () async {
    final repo = _SlowUploadRepo()..gate.complete()..readError = Exception('次數用完了');
    await expectLater(
      uploadShiftPhotoThenRead(repo, storeId: 's1', month: DateTime(2032, 12), bytes: Uint8List.fromList([1]), read: true),
      throwsA(isA<Exception>()),
    );
  });

  test('沒有要辨識（兩家店的每小時同步）：只上傳', () async {
    final repo = _SlowUploadRepo()..gate.complete();
    var notified = false;
    final r = await uploadShiftPhotoThenRead(repo,
        storeId: 's1', month: DateTime(2032, 12), bytes: Uint8List.fromList([1]), onUploaded: () => notified = true);
    expect(repo.uploadedMonths, ['s1 2032-12']);
    expect(repo.readMonths, isEmpty);
    expect(r.read, isFalse);
    expect(notified, isFalse);
  });
}

class _SlowUploadRepo extends DemoRepository {
  final gate = Completer<void>();
  final uploadedMonths = <String>[];
  final readMonths = <String>[];
  Exception? readError;
  @override
  Future<void> uploadShiftPhoto(String storeId, DateTime month, Uint8List jpeg) async {
    await gate.future;
    uploadedMonths.add('$storeId ${month.year}-${month.month}');
  }

  @override
  Future<int?> readShiftPhotos(String storeId, DateTime month) async {
    if (readError != null) throw readError!;
    readMonths.add('$storeId ${month.year}-${month.month}');
    return 5;
  }
}
