import 'models.dart';
import 'repository.dart';

/// 正職排在兼職前面（老闆 2026-11-28「正職都排在最上面」）。
/// 只在相鄰、而且 [group] 一樣的那一段裡調整（例如同一天、同樣停用），段跟段的先後不動；
/// 同一類裡照原本的順序（資料庫給的班表人員排序）。
List<T> fullTimeFirst<T>(List<T> list, bool Function(T) isFull, {Object? Function(T)? group}) {
  final out = <T>[];
  var i = 0;
  while (i < list.length) {
    final g = group?.call(list[i]);
    var j = i + 1;
    while (j < list.length && group?.call(list[j]) == g) {
      j++;
    }
    final run = list.sublist(i, j);
    out
      ..addAll(run.where(isFull))
      ..addAll(run.where((x) => !isFull(x)));
    i = j;
  }
  return out;
}

/// 班表人員裡的正職（含停用的）；別家店來支援的人不在裡面，當兼職排
Set<String> fullTimeIds(ShiftMonth m) => {
      for (final p in m.people)
        if (p.isFull) p.id
    };

/// 再加上另一家店的正職：出勤、異常、加班會有跨店來支援的人，正職一樣排前面。
/// 只有兩家店都是老闆的人讀得到另一家店；讀不到（店長、網路）就只看本店，支援的人當兼職排
Future<Set<String>> fullTimeIdsAllStores(Repository repo, String storeId, ShiftMonth m) async {
  final ids = fullTimeIds(m);
  try {
    for (final s in await repo.shiftLinkStores(storeId)) {
      ids.addAll([for (final p in s.people) if (p.isFull) p.id]);
    }
  } catch (_) {}
  return ids;
}
