/// 兩家店是同一個人（ops 0098、0117）：班表人員的連結。
/// 連結後兩家店不能同一天排這個人（資料庫 shift_entries_guard 擋、自動排班會避開）。
/// 只有兩家店都是老闆的人能連，而且只能連同一個組織的店——資料庫都會擋，這裡只決定畫面上要列什麼。
library;

import 'models.dart';

/// 可以連結的另一家店（我也是那家店的老闆、同一個組織），和那家店班表上的人
class ShiftLinkStore {
  final String storeId;
  final String storeName;
  final List<ShiftPerson> people;
  const ShiftLinkStore({
    required this.storeId,
    required this.storeName,
    required this.people,
  });
}

/// 已經連到的另一家店的人
class ShiftLinkPeer {
  final String storeId;
  final String storeName;
  final ShiftPerson person;
  const ShiftLinkPeer(this.storeId, this.storeName, this.person);
}

/// 這個人在其他店連到誰（沒有連結＝空的）
List<ShiftLinkPeer> linkedPeers(ShiftPerson p, List<ShiftLinkStore> stores) {
  final link = p.linkId;
  if (link == null) return const [];
  return [
    for (final s in stores)
      for (final q in s.people)
        if (q.id != p.id && q.linkId == link)
          ShiftLinkPeer(s.storeId, s.storeName, q),
  ];
}

/// 還能連的店：這個人在那家店還沒有連到任何人（一家店只能有一個人跟他是同一個人）
List<ShiftLinkStore> linkableStores(
  ShiftPerson p,
  List<ShiftLinkStore> stores,
) {
  final peers = linkedPeers(p, stores).map((x) => x.storeId).toSet();
  return [
    for (final s in stores)
      if (!peers.contains(s.storeId)) s,
  ];
}

/// 另一家店的人能不能選：已經連到別人的不能選（要先在那邊解除，不然兩個連結群組會混在一起）
String? linkBlockReason(
  ShiftPerson candidate,
  List<ShiftPerson> myStorePeople,
) {
  final link = candidate.linkId;
  if (link == null) return null;
  final other = myStorePeople.where((x) => x.linkId == link).firstOrNull;
  return other == null ? '已經連到別家店的人，請先解除' : '已經連到「${other.label}」';
}

/// 另一家店的人排序：顯示中的在前、正職在前，再照名字
List<ShiftPerson> linkCandidates(ShiftLinkStore s) {
  final list = [...s.people];
  list.sort((a, b) {
    if (a.active != b.active) return a.active ? -1 : 1;
    if (a.isFull != b.isFull) return a.isFull ? -1 : 1;
    return a.label.compareTo(b.label);
  });
  return list;
}

/// 班表人員清單上的一句：「也在 小城外」
String? linkSummary(ShiftPerson p, List<ShiftLinkStore> stores) {
  final peers = linkedPeers(p, stores);
  if (peers.isEmpty) return null;
  return '也在${peers.map((x) => x.storeName).join('、')}';
}
