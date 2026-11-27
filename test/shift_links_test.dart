import 'package:flutter_test/flutter_test.dart';
import 'package:yincheng_ops/data/demo_repository.dart';
import 'package:yincheng_ops/data/models.dart';
import 'package:yincheng_ops/data/shift_links.dart';

ShiftPerson _p(String id, String name,
        {String? link, bool active = true, String kind = 'full'}) =>
    ShiftPerson(id: id, name: name, linkId: link, active: active, kind: kind);

void main() {
  group('兩家店同一個人（0098）', () {
    final xc = ShiftLinkStore(storeId: 'xc', storeName: '小城外', people: [
      _p('x1', 'Tim', link: 'L1'),
      _p('x2', 'David'),
      _p('x3', 'Vicky', link: 'L9'),
    ]);
    final third = ShiftLinkStore(
        storeId: 's3', storeName: '三店', people: [_p('t1', 'Tim', link: 'L1')]);
    final mine = [
      _p('y1', 'Tim', link: 'L1'),
      _p('y2', 'Kevin'),
      _p('y3', 'Vic', link: 'L9')
    ];

    test('連到哪幾家店的誰', () {
      final peers = linkedPeers(mine[0], [xc, third]);
      expect(peers.map((x) => '${x.storeName}:${x.person.name}'),
          ['小城外:Tim', '三店:Tim']);
      expect(linkedPeers(mine[1], [xc, third]), isEmpty);
      expect(linkSummary(mine[0], [xc, third]), '也在小城外、三店');
      expect(linkSummary(mine[1], [xc]), isNull);
    });

    test('已經連到人的店不能再連（一家店只能有一個人跟他是同一個人）', () {
      expect(linkableStores(mine[0], [xc, third]), isEmpty);
      expect(linkableStores(mine[1], [xc, third]).map((s) => s.storeId),
          ['xc', 's3']);
    });

    test('另一家店已經連到別人的不能選', () {
      expect(linkBlockReason(xc.people[1], mine), isNull);
      expect(linkBlockReason(xc.people[2], mine), '已經連到「Vic」');
      expect(linkBlockReason(_p('z', 'Z', link: 'L7'), mine), '已經連到別家店的人，請先解除');
    });

    test('候選人：顯示中、正職在前', () {
      final s = ShiftLinkStore(storeId: 'xc', storeName: '小城外', people: [
        _p('a', '丙', active: false),
        _p('b', '乙', kind: 'part'),
        _p('c', '甲'),
      ]);
      expect(linkCandidates(s).map((p) => p.id), ['c', 'b', 'a']);
    });
  });

  group('示範版', () {
    test('隱城老闆看得到小城外；小安已經連到陳怡安；可以連、可以解除', () async {
      final repo = DemoRepository();
      await repo.signIn('owner@demo', 'x');
      final stores = await repo.shiftLinkStores('yc');
      expect(stores.single.storeName, '小城外');
      var people = (await repo.shiftMonth('yc', DateTime.now())).people;
      final an = people.firstWhere((p) => p.id == 'f1');
      expect(linkSummary(an, stores), '也在小城外');

      await repo.linkShiftPeople('f2', 'xf0');
      people = (await repo.shiftMonth('yc', DateTime.now())).people;
      final zhe = people.firstWhere((p) => p.id == 'f2');
      expect(
          linkedPeers(zhe, await repo.shiftLinkStores('yc')).single.person.id,
          'xf0');

      await repo.unlinkShiftPerson('xf0');
      people = (await repo.shiftMonth('yc', DateTime.now())).people;
      expect(people.firstWhere((p) => p.id == 'f2').linkId, isNull,
          reason: '只剩一個人的連結一起清掉');
    });

    test('店長、正職沒有連結（看不到另一家店）', () async {
      final repo = DemoRepository();
      await repo.signIn('manager@demo', 'x');
      expect(await repo.shiftLinkStores('yc'), isEmpty);
      await expectLater(repo.linkShiftPeople('f2', 'xf0'), throwsException);
    });
  });
}
