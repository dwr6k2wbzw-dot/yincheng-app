import 'dart:typed_data';

import 'repository.dart';

/// 上傳一張班表照片，接著（api 模式）辨識「上傳的那一個月」（ops 0153）。
/// 店、月份在呼叫時就固定下來：上傳途中切換月份，辨識也不會跑到新選的月份（Codex P2）。
/// [read]＝null：照舊等每小時同步辨識。
Future<void> uploadShiftPhotoThenRead(
  Repository repo, {
  required String storeId,
  required DateTime month,
  required Uint8List bytes,
  Future<void> Function(String storeId, DateTime month)? read,
}) async {
  await repo.uploadShiftPhoto(storeId, month, bytes);
  if (read != null) await read(storeId, month);
}
