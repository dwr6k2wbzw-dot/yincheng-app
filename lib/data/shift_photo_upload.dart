import 'dart:typed_data';

import 'repository.dart';

/// 上傳一張班表照片；[read]＝true（api 模式，ops 0153）接著辨識「上傳的那一個月」。
/// 店、月份、資料來源在呼叫時就固定下來，整段不經過畫面（Codex P2 兩輪）：
/// 上傳途中切換月份、離開班表頁或切換店，照片和辨識都還是原本那家店、那個月，辨識照樣啟動。
/// [onUploaded]：上傳好、開始辨識前通知畫面（畫面已經關掉就不要碰它，由呼叫的人判斷）。
/// 回傳：read＝這次有沒有辨識；cells＝讀到幾格（null＝照片在辨識途中有變動）。辨識失敗直接丟錯。
Future<({bool read, int? cells})> uploadShiftPhotoThenRead(
  Repository repo, {
  required String storeId,
  required DateTime month,
  required Uint8List bytes,
  bool read = false,
  void Function()? onUploaded,
}) async {
  await repo.uploadShiftPhoto(storeId, month, bytes);
  if (!read) return (read: false, cells: null);
  onUploaded?.call();
  final cells = await repo.readShiftPhotos(storeId, month);
  return (read: true, cells: cells);
}
