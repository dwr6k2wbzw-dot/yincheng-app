import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/open_external.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 訂位管理（0050，老闆 2026-10-14）：老闆、店長、正職。客人在公開訂位頁訂位，這裡看清單、標到店／未到／取消、新增電話訂位。
class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key, required this.membership, this.initialDay});
  final Membership membership;
  final DateTime? initialDay; // 從小鈴鐺通知點進來：直接看那一天
  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  late DateTime _day = widget.initialDay ?? _today();
  bool _calOpen = false;
  late Future<(ReservationSettings?, List<Reservation>)> _future;
  bool _started = false;

  static DateTime _today() {
    // 營業日：凌晨 6 點前算前一天
    final n = DateTime.now().subtract(const Duration(hours: 6));
    return DateTime(n.year, n.month, n.day);
  }

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _future = _load();
    }
  }

  ReservationSpecialDay? _special; // 這天的特殊日期（0052）
  Map<String, GuestStats> _guests = {}; // 熟客紀錄（以電話數字對回）

  int _loadGen = 0; // 換日期很快時，舊的讀取晚回來不能蓋掉現在這天的資料（Codex 審查）

  Future<(ReservationSettings?, List<Reservation>)> _load() async {
    final gen = ++_loadGen;
    final day = _day;
    final r = await Future.wait<dynamic>([
      _repo.reservationSettings(_store),
      _repo.reservations(_store, day, day),
      _repo.specialDays(_store, day, day).then<List<ReservationSpecialDay>>((v) => v, onError: (_) => <ReservationSpecialDay>[]),
    ]);
    final list = r[1] as List<Reservation>;
    final special = (r[2] as List<ReservationSpecialDay>).firstOrNull;
    Map<String, GuestStats> guests;
    try {
      guests = await _repo.guestStats(_store, {for (final x in list) phoneDigitsOf(x.phone)});
    } catch (_) {
      guests = {}; // 讀不到熟客資料不影響訂位清單
    }
    if (gen == _loadGen) {
      _special = special;
      _guests = guests;
    }
    return (r[0] as ReservationSettings?, list);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (!mounted) return; // 已經離開這個畫面（Codex 審查）
      showMessage(context, ok);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _future,
        builder: (context, snap) {
          final settings = snap.data?.$1;
          return Scaffold(
            appBar: AppBar(
              title: Text('訂位・${widget.membership.storeName}'),
              actions: [
                if (settings != null && !AppConfig.demo) // 示範模式沒有可用的訂位頁（Codex 審查）
                  IconButton(
                    tooltip: '訂位頁連結',
                    icon: const Icon(Icons.link),
                    onPressed: () => _shareLink(settings),
                  ),
                if (settings != null && widget.membership.role == Role.owner)
                  IconButton(
                    tooltip: '訂位設定',
                    icon: const Icon(Icons.tune),
                    onPressed: () async {
                      final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                        builder: (_) => ReservationSettingsScreen(membership: widget.membership, settings: settings),
                      ));
                      if (changed == true) _reload();
                    },
                  ),
              ],
            ),
            floatingActionButton: settings == null
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => _add(settings),
                    icon: const Icon(Icons.add),
                    label: const Text('電話訂位'),
                  ),
            body: _body(snap),
          );
        },
      );

  Widget _body(AsyncSnapshot<(ReservationSettings?, List<Reservation>)> snap) {
    if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final (settings, list) = snap.data!;
    if (settings == null) {
      return Center(child: Text('這家店還沒有訂位設定', style: TextStyle(color: AppColors.muted)));
    }
    final active = list.where((r) => r.active).toList();
    final guests = active.fold<int>(0, (t, r) => t + r.party);
    final byTime = <String, List<Reservation>>{};
    for (final r in list) {
      byTime.putIfAbsent(r.time, () => []).add(r);
    }
    final times = byTime.keys.toList()..sort();
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        // 日期：點了在下面展開月曆（老闆 2026-10-17：跟客人訂位頁同一種樣式）
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _calOpen = !_calOpen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _calOpen ? AppColors.primary : AppColors.line, width: 1.2),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                    '${_day.month}月${_day.day}日 ${DateFormat('E', 'zh_TW').format(_day)}${_day == _today() ? '（今日）' : ''}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFeatures: tabular)),
              ),
              Icon(_calOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.muted),
            ]),
          ),
        ),
        if (_calOpen)
          ReservationMonthCalendar(
            membership: widget.membership,
            selected: _day,
            today: _today(),
            onPick: (d) {
              _calOpen = false;
              _day = d;
              _reload();
            },
          ),
        const SizedBox(height: 12),
        if (!settings.enabled)
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('線上訂位目前暫停中（老闆可在右上角設定開啟）', style: TextStyle(color: AppColors.warn, fontSize: 13)),
          ),
        () {
          // 每天名額（0052）：組數、人數、大桌
          final lim = settings.limitsFor(_day, _special);
          final large = active.where((r) => r.party >= lim.largeSize).length;
          String cap(int used, int? max) => max == null ? '$used' : '$used/$max';
          return SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.event_seat_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('${active.length} 組・$guests 位', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                if (!lim.closed)
                  Text('上限 ${lim.maxGroups ?? '不限'} 組／${lim.maxGuests ?? '不限'} 位',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              if (lim.closed)
                Text('這天不開放線上訂位${lim.note == null ? '' : '（${lim.note}）'}',
                    style: TextStyle(color: AppColors.warn, fontSize: 13))
              else
                Text('${lim.largeSize} 位以上：${cap(large, lim.maxLarge)} 組${_special != null ? '・今天是特殊日期' : ''}',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          );
        }(),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 48),
            child: Text('這天還沒有訂位', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ),
        for (final t in times) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Row(children: [
              Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${byTime[t]!.where((r) => r.active).fold<int>(0, (s, r) => s + r.party)} 位',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(children: [for (final r in byTime[t]!) _tile(r)]),
          ),
        ],
      ]),
    );
  }

  Widget _tile(Reservation r) {
    final color = switch (r.status) {
      'arrived' => AppColors.good,
      'no_show' => AppColors.bad,
      'cancelled' => AppColors.muted,
      _ => AppColors.primary,
    };
    final dim = r.status == 'cancelled';
    return ListTile(
      onTap: () => _actions(r),
      title: Text('${r.name}・${r.party} 位',
          style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: dim ? TextDecoration.lineThrough : null,
              color: dim ? AppColors.muted : null)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          [
            r.phone,
            r.source == 'web' ? '網路訂位' : '電話訂位',
            if ((r.note ?? '').isNotEmpty) '備註：${r.note}',
            if (r.emailError != null) '確認信寄送失敗',
          ].join('・'),
          style: const TextStyle(fontSize: 12),
        ),
        // 0055 客人申請改人數（待店家確認）
        if (r.partyPending)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.warn.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
              child: Text('客人申請改為 ${r.requestedParty} 位・點一下處理',
                  style: TextStyle(fontSize: 12, color: AppColors.warn, fontWeight: FontWeight.w600)),
            ),
          ),
        // 熟客辨識（0052）：來過幾次、未到幾次、標籤、備註
        if (_guestBadges(r).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 4, children: _guestBadges(r)),
          ),
      ]),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Text(reservationStatusLabel[r.status] ?? r.status, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }

  List<Widget> _guestBadges(Reservation r) {
    final g = _guests[phoneDigitsOf(r.phone)];
    if (g == null) return const [];
    Widget badge(String t, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
          child: Text(t, style: TextStyle(fontSize: 11, color: c)),
        );
    return [
      if (g.visits > 0) badge('來過 ${g.visits} 次', AppColors.good),
      if (g.noShows > 0) badge('未到 ${g.noShows} 次', AppColors.bad),
      for (final t in g.profile?.tags ?? const <String>[]) badge(t, AppColors.primary),
      if ((g.profile?.note ?? '').isNotEmpty) badge(g.profile!.note!, AppColors.muted),
    ];
  }

  /// 熟客資料：標籤、備註；未到達到門檻時可以「解除」（之後可以再線上訂位）
  Future<void> _editGuest(Reservation r, ReservationSettings s) async {
    final digits = phoneDigitsOf(r.phone);
    final g = _guests[digits];
    final tags = {...?g?.profile?.tags};
    final note = TextEditingController(text: g?.profile?.note ?? '');
    final custom = TextEditingController();
    var reset = false;
    final blocked = s.noshowBlockCount > 0 && (g?.noShows ?? 0) >= s.noshowBlockCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('熟客資料・${r.name}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('電話 ${r.phone}・來過 ${g?.visits ?? 0} 次・未到 ${g?.noShows ?? 0} 次',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in {...guestTagPresets, ...tags})
                  FilterChip(
                    label: Text(t),
                    selected: tags.contains(t),
                    onSelected: (v) => setD(() => v ? tags.add(t) : tags.remove(t)),
                  ),
              ]),
              Row(children: [
                Expanded(child: TextField(controller: custom, maxLength: 10, decoration: const InputDecoration(hintText: '自訂標籤', counterText: ''))),
                IconButton(
                  tooltip: '加入標籤',
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final t = custom.text.trim();
                    if (t.isEmpty || tags.length >= 10) return;
                    setD(() {
                      tags.add(t);
                      custom.clear();
                    });
                  },
                ),
              ]),
              const SizedBox(height: 8),
              TextField(controller: note, maxLength: 200, maxLines: 2, decoration: const InputDecoration(labelText: '熟客備註（例如：不吃香菜）')),
              if (blocked)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: reset,
                  onChanged: (v) => setD(() => reset = v ?? false),
                  title: const Text('解除未到紀錄'),
                  subtitle: Text('未到 ${s.noshowBlockCount} 次以上目前不能線上訂位；解除後可以再線上訂',
                      style: const TextStyle(fontSize: 12)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('儲存')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (digits.length < 8) {
      showMessage(context, '電話不完整，不能存熟客資料', error: true);
      return;
    }
    await _run(
        () => _repo.saveGuestProfile(_store, GuestProfile(phoneDigits: digits, tags: tags.toList(), note: note.text),
            resetNoshow: reset),
        reset ? '已儲存並解除未到紀錄' : '已儲存熟客資料');
  }

  Future<void> _actions(Reservation r) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('${r.name}・${r.party} 位・${r.time}', style: const TextStyle(fontWeight: FontWeight.w700))),
          if (r.partyPending) ...[
            ListTile(
                leading: Icon(Icons.check, color: AppColors.good),
                title: Text('同意改為 ${r.requestedParty} 位'),
                subtitle: const Text('會寄信通知客人'),
                onTap: () => Navigator.pop(c, 'party_yes')),
            ListTile(
                leading: Icon(Icons.close, color: AppColors.bad),
                title: Text('不同意（維持 ${r.party} 位）'),
                subtitle: const Text('會寄信通知客人'),
                onTap: () => Navigator.pop(c, 'party_no')),
            const Divider(height: 1),
          ],
          ListTile(leading: const Icon(Icons.call), title: Text('打電話 ${r.phone}'), onTap: () => Navigator.pop(c, 'call')),
          if (r.status != 'arrived')
            ListTile(leading: const Icon(Icons.check_circle_outline), title: const Text('已到店'), onTap: () => Navigator.pop(c, 'arrived')),
          if (r.status != 'no_show')
            ListTile(leading: const Icon(Icons.person_off_outlined), title: const Text('未到（no-show）'), onTap: () => Navigator.pop(c, 'no_show')),
          if (r.status != 'confirmed')
            ListTile(leading: const Icon(Icons.undo), title: const Text('改回已確認'), onTap: () => Navigator.pop(c, 'confirmed')),
          if (r.status != 'cancelled')
            ListTile(
                leading: Icon(Icons.cancel_outlined, color: AppColors.bad),
                title: Text('取消訂位', style: TextStyle(color: AppColors.bad)),
                onTap: () => Navigator.pop(c, 'cancelled')),
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改訂位內容'),
              subtitle: const Text('日期、時間、人數、姓名、電話、Email、備註'),
              onTap: () => Navigator.pop(c, 'edit')),
          ListTile(
              leading: const Icon(Icons.loyalty_outlined),
              title: const Text('熟客資料'),
              subtitle: const Text('標籤、備註、解除未到紀錄'),
              onTap: () => Navigator.pop(c, 'guest')),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'call') {
      openExternal('tel:${r.phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
      return;
    }
    if (v == 'party_yes' || v == 'party_no') {
      final yes = v == 'party_yes';
      if (yes) {
        // 加人：先看這天名額夠不夠（只提醒，店家可以決定照收）
        try {
          final settings = await _repo.reservationSettings(_store);
          final same = await _repo.reservations(_store, r.date, r.date);
          final sp = (await _repo.specialDays(_store, r.date, r.date)).firstOrNull;
          final over = settings == null
              ? const <String>[]
              : settings.limitsFor(r.date, sp).overBy(same.where((x) => x.id != r.id).toList(), r.requestedParty ?? r.party);
          if (over.isNotEmpty && mounted) {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('超過這天的名額'),
                content: Text('${over.join('\n')}\n還是要同意嗎？'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('不要')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('還是同意')),
                ],
              ),
            );
            if (ok != true) return;
          }
        } catch (e) {
          if (mounted) showMessage(context, friendlyError(e), error: true);
          return;
        }
      }
      if (!mounted) return;
      await _run(() => _repo.decidePartyRequest(r.id, yes, r.requestedParty!), yes ? '已同意，改為 ${r.requestedParty} 位' : '已回覆不同意');
      return;
    }
    if (v == 'guest') {
      final s = (await _future).$1;
      if (s != null && mounted) await _editGuest(r, s);
      return;
    }
    if (v == 'edit') {
      final s = (await _future).$1;
      if (s == null || !mounted) return;
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _AddReservationScreen(membership: widget.membership, settings: s, day: r.date, existing: r),
      ));
      if (saved == true) _reload();
      return;
    }
    if (v.startsWith('t:')) {
      final name = withTitle(stripTitle(r.name), v.substring(2));
      await _run(() => _repo.updateReservation(r.id, {'guest_name': name}), '已改成 $name');
      return;
    }
    if (v == 'note') {
      final ctrl = TextEditingController(text: r.note ?? '');
      final note = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('備註'),
          content: TextField(controller: ctrl, maxLength: 200, maxLines: 3, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('儲存')),
          ],
        ),
      );
      if (note == null) return;
      await _run(() => _repo.updateReservation(r.id, {'note': note.isEmpty ? null : note}), '已更新備註');
      return;
    }
    if (v == 'cancelled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('取消這筆訂位？'),
          content: Text('${r.name}・${r.party} 位・${r.time}\n取消後名額會釋出（不會自動通知客人）。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('不要')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('取消訂位')),
          ],
        ),
      );
      if (ok != true) return;
    }
    // 從「取消／未到」改回有效：先檢查那個時段還有沒有名額（Codex 審查）
    if (!r.active && (v == 'confirmed' || v == 'arrived')) {
      try {
        final settings = await _repo.reservationSettings(_store);
        final same = await _repo.reservations(_store, r.date, r.date);
        final sp = (await _repo.specialDays(_store, r.date, r.date)).firstOrNull;
        final over = settings == null
            ? const <String>[]
            : settings.limitsFor(r.date, sp).overBy(same.where((x) => x.id != r.id).toList(), r.party);
        if (over.isNotEmpty && mounted) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('超過這天的名額'),
              content: Text('${over.join('\n')}\n還是要改嗎？'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('不要')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('還是要改')),
              ],
            ),
          );
          if (ok != true) return;
        }
      } catch (e) {
        if (mounted) showMessage(context, friendlyError(e), error: true);
        return;
      }
    }
    if (!mounted) return;
    await _run(() => _repo.updateReservation(r.id, {'status': v}), '已改成「${reservationStatusLabel[v]}」');
  }

  void _shareLink(ReservationSettings s) {
    final url = reservationPageUrl(s.slug);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('客人訂位頁'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('把這個網址放在 IG、Google 商家、LINE 官方帳號，客人就能直接訂位：', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          SelectableText(url, style: TextStyle(fontSize: 13, color: AppColors.primary)),
        ]),
        actions: [
          TextButton(onPressed: () => openExternal(url), child: const Text('打開看看')),
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(c);
              showMessage(context, '已複製訂位頁網址');
            },
            child: const Text('複製網址'),
          ),
        ],
      ),
    );
  }

  Future<void> _add(ReservationSettings s) async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _AddReservationScreen(membership: widget.membership, settings: s, day: _day),
    ));
    if (added == true) _reload();
  }
}

/// 電話訂位（員工代客人輸入；不受線上訂位的天數、截止時間、每組人數限制，但會提醒超過這天的名額）
class _AddReservationScreen extends StatefulWidget {
  const _AddReservationScreen({required this.membership, required this.settings, required this.day, this.existing});
  final Membership membership;
  final ReservationSettings settings;
  final DateTime day;
  final Reservation? existing; // 有值＝修改這筆訂位（老闆 2026-10-15）
  @override
  State<_AddReservationScreen> createState() => _AddReservationScreenState();
}

class _AddReservationScreenState extends State<_AddReservationScreen> {
  late DateTime _date = widget.existing?.date ?? widget.day;
  late String? _time = widget.existing?.time;
  late int _party = widget.existing?.party ?? 2;
  late final _name = TextEditingController(text: widget.existing == null ? '' : stripTitle(widget.existing!.name));
  // 先生／小姐（老闆 2026-10-15），存檔時接在姓名後面
  late String? _title = reservationTitles.where((t) => (widget.existing?.name ?? '').trim().endsWith(t)).firstOrNull;
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool get _editing => widget.existing != null;
  bool _saving = false;

  Future<void> _pickCustomTime() async {
    TimeOfDay initial = const TimeOfDay(hour: 19, minute: 0);
    final cur = _time;
    if (cur != null && cur.length == 5) {
      initial = TimeOfDay(hour: int.tryParse(cur.substring(0, 2)) ?? 19, minute: int.tryParse(cur.substring(3)) ?? 0);
    }
    final t = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '選擇訂位時間',
      initialEntryMode: TimePickerEntryMode.input,
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null || !mounted) return;
    setState(() => _time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _save() async {
    // 先把表單內容固定下來，檢查名額期間就算有人改欄位，也不會混用新舊值（Codex 審查）
    final date = _date;
    final time = _time;
    final party = _party;
    final raw = _name.text.trim();
    final title = _title;
    final name = withTitle(raw, title);
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    final note = _note.text.trim();
    if (time == null) {
      showMessage(context, '請選時段', error: true);
      return;
    }
    if (raw.isNotEmpty && title == null && !hasTitle(raw)) {
      showMessage(context, '請選先生或小姐', error: true);
      return;
    }
    if (name.isEmpty) {
      showMessage(context, '請填姓名', error: true);
      return;
    }
    if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      showMessage(context, '請填正確的電話', error: true);
      return;
    }
    setState(() => _saving = true);
    final repo = AppScope.of(context).repo;
    try {
      // 超過這天的名額先確認（電話訂位可以超收，由店家決定；0052 改成每天計算）
      final same = await repo.reservations(widget.membership.storeId, date, date);
      final sp = (await repo.specialDays(widget.membership.storeId, date, date)).firstOrNull;
      if (!mounted) return; // 已離開表單：不要在沒確認的情況下新增（Codex 審查）
      // 修改時不算自己原本那筆
      final over = widget.settings
          .limitsFor(date, sp)
          .overBy(same.where((r) => r.id != widget.existing?.id).toList(), party);
      if (over.isNotEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('超過這天的名額'),
            content: Text('${over.join('\n')}\n電話訂位可以超收，還是要${_editing ? '儲存' : '新增'}嗎？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('不要')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(_editing ? '還是儲存' : '還是新增')),
            ],
          ),
        );
        if (ok != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        if (!mounted) return;
      }
      final ex = widget.existing;
      if (ex != null) {
        await repo.updateReservation(ex.id, {
          'slot_date': DateFormat('yyyy-MM-dd').format(date),
          'slot_time': time,
          'party_size': party,
          'guest_name': name,
          'phone': phone,
          'email': email.isEmpty ? null : email,
          'note': note.isEmpty ? null : note,
        });
      } else {
        await repo.addReservation(widget.membership.storeId,
            date: date, time: time, party: party, name: name, phone: phone, email: email, note: note);
      }
      if (mounted) {
        showMessage(context, _editing ? '已儲存修改' : '已新增訂位');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, friendlyError(e), error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_editing ? '修改訂位' : '電話訂位')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('日期'),
            trailing: Text(DateFormat('M/d（E）', 'zh_TW').format(_date), style: const TextStyle(fontSize: 16)),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2025),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          const SizedBox(height: 8),
          Text('時段', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in widget.settings.slots)
              ChoiceChip(label: Text(t), selected: _time == t, onSelected: (_) => setState(() => _time = t)),
            // 自己選的時間（不在固定時段裡）
            if (_time != null && !widget.settings.slots.contains(_time))
              ChoiceChip(label: Text(_time!), selected: true, onSelected: (_) => _pickCustomTime()),
            // 電話訂位可訂任何時間（老闆 2026-10-15）
            ActionChip(
              avatar: Icon(Icons.add, size: 18, color: AppColors.primary),
              label: const Text('其他時間'),
              onPressed: _pickCustomTime,
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Text('人數', style: TextStyle(color: AppColors.muted)),
            const Spacer(),
            IconButton(onPressed: _party > 1 ? () => setState(() => _party--) : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('$_party', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            IconButton(onPressed: _party < 50 ? () => setState(() => _party++) : null, icon: const Icon(Icons.add_circle_outline)),
          ]),
          TextField(
            controller: _name,
            maxLength: 36,
            decoration: InputDecoration(
              labelText: '姓名',
              counterText: '',
              // 點一下選先生／小姐，再點一次取消
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final t in const ['先生', '小姐'])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(t),
                        selected: _title == t,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (v) => setState(() => _title = v ? t : null),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _phone,
              maxLength: 20,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '電話', counterText: '')),
          const SizedBox(height: 12),
          TextField(
              controller: _email,
              maxLength: 120,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  labelText: _editing ? 'Email（選填；修改不會另外寄信）' : 'Email（選填；不寄確認信，會寄當天下午的提醒信）', counterText: '')),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLength: 200, maxLines: 2, decoration: const InputDecoration(labelText: '備註（選填）')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_editing ? '儲存修改' : '新增訂位'),
          ),
        ]),
      );
}

/// 訂位設定（只有老闆）
class ReservationSettingsScreen extends StatefulWidget {
  const ReservationSettingsScreen({super.key, required this.membership, required this.settings});
  final Membership membership;
  final ReservationSettings settings;
  @override
  State<ReservationSettingsScreen> createState() => _ReservationSettingsScreenState();
}

class _ReservationSettingsScreenState extends State<ReservationSettingsScreen> {
  late bool _enabled = widget.settings.enabled;
  // 0054 時段自由增刪（老闆 2026-10-16）
  late final List<String> _slots = [...widget.settings.slots];
  late final _address = TextEditingController(text: widget.settings.address ?? '');
  late final _phone = TextEditingController(text: widget.settings.phone ?? '');
  late String _cutoff = widget.settings.sameDayCutoff;
  late final _name = TextEditingController(text: widget.settings.displayName);
  // 0052 每天名額（空白＝不限）、大桌、每週公休、未到擋線上訂位
  late final _groups = TextEditingController(text: widget.settings.maxGroupsPerDay?.toString() ?? '');
  late final _guestsDay = TextEditingController(text: widget.settings.maxGuestsPerDay?.toString() ?? '');
  late final _largeSize = TextEditingController(text: '${widget.settings.largePartySize}');
  late final _largeMax = TextEditingController(text: widget.settings.maxLargePerDay?.toString() ?? '');
  late final _noshow = TextEditingController(text: '${widget.settings.noshowBlockCount}');
  late final Set<int> _closedDays = {...widget.settings.closedWeekdays};
  late final _party = TextEditingController(text: '${widget.settings.maxParty}');
  late final _days = TextEditingController(text: '${widget.settings.daysAhead}');
  late final _contact = TextEditingController(text: widget.settings.contactNote ?? '');
  bool _saving = false;

  Future<void> _addSlot() async {
    final last = _slots.isEmpty ? '19:00' : _slots.last;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutesOf(last) ~/ 60, minute: minutesOf(last) % 60),
      helpText: '新增訂位時段',
    );
    if (t == null || !mounted) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (_slots.contains(v)) {
      showMessage(context, '已經有 $v 這個時段');
      return;
    }
    if (_slots.length >= 48) {
      showMessage(context, '時段最多 48 個', error: true);
      return;
    }
    setState(() => _slots
      ..add(v)
      ..sort());
  }

  Future<void> _pick(String current, void Function(String) set) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutesOf(current) ~/ 60, minute: minutesOf(current) % 60),
    );
    if (t != null) setState(() => set('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'));
  }

  Future<void> _save() async {
    int? opt(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    bool bad(TextEditingController c, int lo, int hi) {
      if (c.text.trim().isEmpty) return false;
      final v = int.tryParse(c.text.trim());
      return v == null || v < lo || v > hi;
    }
    final party = int.tryParse(_party.text.trim());
    final days = int.tryParse(_days.text.trim());
    if (_name.text.trim().isEmpty) {
      showMessage(context, '請填店名', error: true);
      return;
    }
    if (bad(_groups, 1, 500) || bad(_guestsDay, 1, 2000) || bad(_largeMax, 0, 500)) {
      showMessage(context, '每天名額請填數字（空白＝不限）', error: true);
      return;
    }
    final largeSize = int.tryParse(_largeSize.text.trim());
    final noshow = int.tryParse(_noshow.text.trim());
    if (largeSize == null || largeSize < 2 || largeSize > 50) {
      showMessage(context, '大桌人數請填 2～50', error: true);
      return;
    }
    if (noshow == null || noshow < 0 || noshow > 20) {
      showMessage(context, '未到次數請填 0～20（0＝不擋）', error: true);
      return;
    }
    if (party == null || party < 1 || party > 50) {
      showMessage(context, '一組最多人數請填 1～50', error: true);
      return;
    }
    if (days == null || days < 1 || days > 60) {
      showMessage(context, '可訂天數請填 1～60', error: true);
      return;
    }
    if (_slots.isEmpty) {
      showMessage(context, '至少要有一個訂位時段', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).repo.saveReservationSettings(widget.membership.storeId, {
        'enabled': _enabled,
        'display_name': _name.text.trim(),
        'slot_times': _slots,
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'same_day_cutoff': _cutoff,
        'max_groups_per_day': opt(_groups),
        'max_guests_per_day': opt(_guestsDay),
        'large_party_size': largeSize,
        'max_large_groups_per_day': opt(_largeMax),
        'closed_weekdays': (_closedDays.toList()..sort()),
        'noshow_block_count': noshow,
        'max_party': party,
        'days_ahead': days,
        'contact_note': _contact.text.trim().isEmpty ? null : _contact.text.trim(),
      });
      if (mounted) {
        showMessage(context, '已儲存訂位設定');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, friendlyError(e), error: true);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('訂位設定')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('開放線上訂位'),
            subtitle: const Text('關閉後訂位頁會顯示「暫停線上訂位」', style: TextStyle(fontSize: 12)),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(labelText: '訂位頁顯示的店名', counterText: '')),
          const SizedBox(height: 8),
          TextField(controller: _address, maxLength: 200, maxLines: 2, minLines: 1,
              decoration: const InputDecoration(labelText: '地址（訂位頁、確認信顯示，可點開地圖）', counterText: '')),
          const SizedBox(height: 8),
          TextField(controller: _phone, maxLength: 30, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '電話（訂位頁可直接撥打）', counterText: '')),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('訂位時段（點 ✕ 刪除）', style: TextStyle(color: AppColors.muted, fontSize: 13))),
            TextButton.icon(onPressed: _addSlot, icon: const Icon(Icons.add, size: 18), label: const Text('新增時段')),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in _slots)
              InputChip(
                label: Text(t),
                onDeleted: () => setState(() => _slots.remove(t)),
                deleteButtonTooltipMessage: '刪除 $t',
              ),
          ]),
          if (_slots.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('至少要有一個時段', style: TextStyle(color: AppColors.bad, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('當天訂位截止'),
              subtitle: const Text('這個時間以後不接受當天的線上訂位', style: TextStyle(fontSize: 12)),
              trailing: Text(_cutoff, style: const TextStyle(fontSize: 16)),
              onTap: () => _pick(_cutoff, (v) => _cutoff = v)),
          const SizedBox(height: 8),
          Text('每天名額（不限用餐時間；空白＝不限；電話訂位可超收）', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _groups, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '每天最多幾組'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _guestsDay, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '每天最多幾位'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _largeSize, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '幾位以上算大桌'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _largeMax, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '大桌每天最多幾組'))),
          ]),
          const SizedBox(height: 16),
          Text('每週固定公休（不開放線上訂位）', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 1; i <= 7; i++)
              FilterChip(
                label: Text('週${const ['一', '二', '三', '四', '五', '六', '日'][i - 1]}'),
                selected: _closedDays.contains(i),
                onSelected: (v) => setState(() => v ? _closedDays.add(i) : _closedDays.remove(i)),
              ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SpecialDaysScreen(membership: widget.membership))),
            icon: const Icon(Icons.event_busy_outlined),
            label: const Text('特殊日期（公休、包場、改名額）'),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _noshow,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '同一支電話未到幾次就不能線上訂位（0＝不擋）')),
          const SizedBox(height: 12),
          TextField(controller: _party, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '線上訂位一組最多幾位')),
          const SizedBox(height: 12),
          TextField(controller: _days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '可以訂幾天內（含今天）')),
          const SizedBox(height: 12),
          TextField(
              controller: _contact,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '其他店家資訊（例如注意事項，會顯示在訂位頁和確認信）')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('儲存'),
          ),
        ]),
      );
}


/// 總覽上的「今日訂位」卡片：點了進訂位管理
class ReservationSummaryCard extends StatefulWidget {
  const ReservationSummaryCard({super.key, required this.membership, this.compact = false});
  final Membership membership;
  final bool compact; // 隱城（C 版）：放在 2×2 小格裡
  @override
  State<ReservationSummaryCard> createState() => _ReservationSummaryCardState();
}

class _ReservationSummaryCardState extends State<ReservationSummaryCard> {
  Future<List<Reservation>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Reservation>> _load() {
    final d = _ReservationsScreenState._today();
    return AppScope.of(context).repo.reservations(widget.membership.storeId, d, d);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Reservation>>(
        future: _future,
        builder: (context, snap) {
          final list = (snap.data ?? const <Reservation>[]).where((r) => r.active).toList();
          final guests = list.fold<int>(0, (t, r) => t + r.party);
          final sub = snap.hasError
              ? '讀取失敗，點進去重新整理'
              : !snap.hasData
                  ? '讀取中…'
                  : list.isEmpty
                      ? '今天還沒有訂位'
                      : '今天 ${list.length} 組・$guests 位';
          // 下一組：還沒到店的最早時段
          final waiting = list.where((r) => r.status == 'confirmed').map((r) => r.time).toList()..sort();
          Future<void> open() async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReservationsScreen(membership: widget.membership),
            ));
            if (mounted) setState(() => _future = _load());
          }

          final ready = snap.hasData && !snap.hasError;
          if (widget.compact) {
            return Material(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('今日訂位', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 6),
                    if (ready && list.isNotEmpty)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${list.length}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                          TextSpan(text: ' 組 · $guests 位', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                        ])),
                      )
                    else
                      Text(ready ? '還沒有訂位' : sub, style: TextStyle(fontSize: 14, color: AppColors.muted)),
                    if (waiting.isNotEmpty)
                      Text('下一組 ${waiting.first}', style: TextStyle(fontSize: 11, color: AppColors.muted, fontFeatures: tabular)),
                  ]),
                ),
              ),
            );
          }
          return SectionCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.event_seat_outlined, size: 20, color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('今日訂位', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Text(ready && list.isNotEmpty ? '${list.length} 組 · $guests 位' : sub,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, fontFeatures: tabular)),
                    ]),
                  ),
                  if (waiting.isNotEmpty)
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('下一組', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      Text(waiting.first, style: const TextStyle(fontSize: 14, fontFeatures: tabular)),
                    ])
                  else
                    Icon(Icons.chevron_right, color: AppColors.muted),
                ]),
              ),
            ),
          );
        },
      );
}

/// 訂位月曆（老闆 2026-10-14：像 iPhone 行事曆那樣一次看好幾個月、點日期跳過去）
/// 前 2 個月到後 4 個月；有訂位的日期底下畫一條線、數字＝組數；今天實心圓、選中的日期外框。
/// 訂位管理頁內嵌月曆（老闆 2026-10-17）：一次一個月、‹ › 換月；選中＝金底、今天上方一條短線、有訂位的日子下方顯示組數
class ReservationMonthCalendar extends StatefulWidget {
  const ReservationMonthCalendar(
      {super.key, required this.membership, required this.selected, required this.today, required this.onPick});
  final Membership membership;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onPick;
  @override
  State<ReservationMonthCalendar> createState() => _ReservationMonthCalendarState();
}

class _ReservationMonthCalendarState extends State<ReservationMonthCalendar> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);
  Map<DateTime, int> _groups = const {};
  int _loadGen = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    final from = _month, to = DateTime(_month.year, _month.month + 1, 0);
    try {
      final list = await AppScope.of(context).repo.reservations(widget.membership.storeId, from, to);
      final m = <DateTime, int>{};
      for (final r in list.where((r) => r.active)) {
        final d = DateTime(r.date.year, r.date.month, r.date.day);
        m[d] = (m[d] ?? 0) + 1;
      }
      if (mounted && gen == _loadGen) setState(() => _groups = m);
    } catch (_) {
      // 讀不到組數也能選日期
    }
  }

  void _go(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _groups = const {};
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = DateTime(_month.year, _month.month, 1).weekday % 7; // 週日開頭
    final sel = DateTime(widget.selected.year, widget.selected.month, widget.selected.day);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(children: [
        Row(children: [
          IconButton(onPressed: () => _go(-1), icon: Icon(Icons.chevron_left, color: AppColors.primary)),
          Expanded(
            child: Text('${_month.year}年${_month.month}月',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          IconButton(onPressed: () => _go(1), icon: Icon(Icons.chevron_right, color: AppColors.primary)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
            Expanded(child: Text(w, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted))),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++) _cell(DateTime(_month.year, _month.month, d), sel),
          ],
        ),
        TextButton(onPressed: () => widget.onPick(widget.today), child: const Text('回到今天')),
      ]),
    );
  }

  Widget _cell(DateTime d, DateTime sel) {
    final isSel = d == sel;
    final isToday = d == widget.today;
    final past = d.isBefore(widget.today);
    final n = _groups[d] ?? 0;
    final fg = isSel ? AppColors.onPrimary : (past ? AppColors.muted : AppColors.text);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => widget.onPick(d),
      child: Container(
        decoration: BoxDecoration(
          color: isSel ? AppColors.primary : AppColors.cardHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSel ? AppColors.primary : AppColors.line),
        ),
        child: Stack(alignment: Alignment.center, children: [
          if (isToday)
            Positioned(
              top: 5,
              child: Container(width: 10, height: 2, color: isSel ? AppColors.onPrimary : AppColors.primary),
            ),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${d.day}',
                style: TextStyle(fontSize: 16, fontWeight: isSel ? FontWeight.w700 : FontWeight.w500, color: fg, fontFeatures: tabular)),
            if (n > 0)
              Text('$n 組',
                  style: TextStyle(fontSize: 9, height: 1.1, color: isSel ? AppColors.onPrimary : AppColors.primary, fontFeatures: tabular)),
          ]),
        ]),
      ),
    );
  }
}

class ReservationCalendarScreen extends StatefulWidget {
  const ReservationCalendarScreen({super.key, required this.membership, required this.selected, required this.today});
  final Membership membership;
  final DateTime selected;
  final DateTime today;
  @override
  State<ReservationCalendarScreen> createState() => _ReservationCalendarScreenState();
}

class _ReservationCalendarScreenState extends State<ReservationCalendarScreen> {
  late final DateTime _from = DateTime(widget.today.year, widget.today.month - 2, 1);
  late final DateTime _to = DateTime(widget.today.year, widget.today.month + 5, 0);
  Map<DateTime, int> _groups = const {};
  final _selectedKey = GlobalKey();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
    // 打開時捲到選中的那個月
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _selectedKey.currentContext;
      if (c != null) Scrollable.ensureVisible(c, alignment: 0.05);
    });
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.of(context).repo.reservations(widget.membership.storeId, _from, _to);
      final m = <DateTime, int>{};
      for (final r in list.where((r) => r.active)) {
        final d = DateTime(r.date.year, r.date.month, r.date.day);
        m[d] = (m[d] ?? 0) + 1;
      }
      if (mounted) setState(() => _groups = m);
    } catch (_) {
      // 讀不到訂位數也能選日期
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = [for (var m = DateTime(_from.year, _from.month); !m.isAfter(_to); m = DateTime(m.year, m.month + 1)) m];
    final sel = DateTime(widget.selected.year, widget.selected.month, widget.selected.day);
    return Scaffold(
      appBar: AppBar(
        title: const Text('選擇日期'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, widget.today), child: const Text('今天')),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('底線＝當天有訂位（數字是組數）', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 8),
          for (final m in months)
            Container(
              key: m.year == sel.year && m.month == sel.month ? _selectedKey : null,
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: _month(m, sel),
            ),
        ]),
      ),
    );
  }

  Widget _month(DateTime m, DateTime sel) {
    final isThisMonth = m.year == widget.today.year && m.month == widget.today.month;
    final days = DateTime(m.year, m.month + 1, 0).day;
    final lead = DateTime(m.year, m.month, 1).weekday - 1; // 週一開頭
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++) _dayCell(DateTime(m.year, m.month, d), sel),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${m.year == widget.today.year ? '' : '${m.year} 年 '}${m.month} 月',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: isThisMonth ? AppColors.primary : AppColors.text)),
      const SizedBox(height: 10),
      Row(children: [
        for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
          Expanded(child: Text(w, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted))),
      ]),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.95,
        children: cells,
      ),
    ]);
  }

  Widget _dayCell(DateTime d, DateTime sel) {
    final isToday = d == widget.today;
    final isSel = d == sel;
    final n = _groups[d] ?? 0;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => Navigator.pop(context, d),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isToday ? AppColors.primary : null,
            border: isSel && !isToday ? Border.all(color: AppColors.primary, width: 1.5) : null,
          ),
          child: Text('${d.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: isToday || isSel ? FontWeight.w700 : FontWeight.w500,
                color: isToday ? AppColors.onPrimary : AppColors.text,
                fontFeatures: tabular,
              )),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 14,
          child: n == 0
              ? null
              : Column(children: [
                  Container(width: 18, height: 2, color: AppColors.primary),
                  Text('$n', style: TextStyle(fontSize: 9, height: 1.2, color: AppColors.primary, fontFeatures: tabular)),
                ]),
        ),
      ]),
    );
  }
}

/// 稱謂（老闆 2026-10-15）：訂位姓名後面接「先生」或「小姐」
const reservationTitles = ['先生', '小姐'];
bool hasTitle(String name) => reservationTitles.any((t) => name.trim().endsWith(t));
String stripTitle(String name) {
  var n = name.trim();
  for (final t in reservationTitles) {
    if (n.endsWith(t)) n = n.substring(0, n.length - t.length).trim();
  }
  return n.isEmpty ? name.trim() : n;
}

String withTitle(String raw, String? title) {
  final n = raw.trim();
  if (n.isEmpty || title == null || n.endsWith(title)) return n;
  final base = stripTitle(n);
  final out = '$base $title';
  return out.length > 40 ? out.substring(0, 40) : out;
}

/// 特殊日期（0052，只有老闆）：整天不開放（公休／包場，可寫說明給客人看），或這天改名額
class SpecialDaysScreen extends StatefulWidget {
  const SpecialDaysScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<SpecialDaysScreen> createState() => _SpecialDaysScreenState();
}

class _SpecialDaysScreenState extends State<SpecialDaysScreen> {
  Future<List<ReservationSpecialDay>>? _future;
  final _from = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  Repository get _repo => AppScope.of(context).repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<ReservationSpecialDay>> _load() =>
      _repo.specialDays(widget.membership.storeId, _from, _from.add(const Duration(days: 365)));

  Future<void> _edit(ReservationSpecialDay? d) async {
    var day = d?.day;
    if (day == null) {
      day = await showDatePicker(context: context, initialDate: _from, firstDate: _from, lastDate: _from.add(const Duration(days: 365)));
      if (day == null || !mounted) return;
    }
    var closed = d?.closed ?? true;
    final note = TextEditingController(text: d?.note ?? '');
    final groups = TextEditingController(text: d?.maxGroups?.toString() ?? '');
    final guests = TextEditingController(text: d?.maxGuests?.toString() ?? '');
    final large = TextEditingController(text: d?.maxLarge?.toString() ?? '');
    final pickedDay = day;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(DateFormat('M/d（E）', 'zh_TW').format(pickedDay)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('整天不開放線上訂位'),
                subtitle: const Text('公休、包場', style: TextStyle(fontSize: 12)),
                value: closed,
                onChanged: (v) => setD(() => closed = v),
              ),
              TextField(controller: note, maxLength: 100, decoration: const InputDecoration(labelText: '說明（會顯示在訂位頁，例如：包場）')),
              if (!closed) ...[
                const SizedBox(height: 8),
                Text('這天改名額（空白＝照平常）', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                TextField(controller: groups, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '最多幾組')),
                TextField(controller: guests, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '最多幾位')),
                TextField(controller: large, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '大桌最多幾組')),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('儲存')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    int? opt(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    // 有填就一定要是 0～999 的整數；打錯不能默默當成「照平常」（Codex 審查）
    if (!closed) {
      for (final (c, label) in [(groups, '最多幾組'), (guests, '最多幾位'), (large, '大桌最多幾組')]) {
        final t = c.text.trim();
        final v = int.tryParse(t);
        if (t.isNotEmpty && (v == null || v < 0 || v > 999)) {
          showMessage(context, '「$label」請填 0～999 的整數，或留空白', error: true);
          return;
        }
      }
    }
    try {
      await _repo.saveSpecialDay(
          widget.membership.storeId,
          ReservationSpecialDay(
            day: pickedDay,
            closed: closed,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
            maxGroups: closed ? null : opt(groups),
            maxGuests: closed ? null : opt(guests),
            maxLarge: closed ? null : opt(large),
          ));
      if (!mounted) return;
      showMessage(context, '已儲存');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(ReservationSpecialDay d) async {
    try {
      await _repo.deleteSpecialDay(widget.membership.storeId, d.day);
      if (!mounted) return;
      showMessage(context, '已刪除，這天照平常開放');
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('特殊日期')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add),
          label: const Text('新增日期'),
        ),
        body: FutureBuilder<List<ReservationSpecialDay>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            if (list.isEmpty) {
              return Center(
                  child: Text('還沒有特殊日期\n按右下角新增公休、包場或改名額的日子',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.6)));
            }
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              for (final d in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      title: Text(DateFormat('M/d（E）', 'zh_TW').format(d.day)),
                      subtitle: Text(
                        d.closed
                            ? '不開放線上訂位${d.note == null ? '' : '・${d.note}'}'
                            : [
                                if (d.maxGroups != null) '最多 ${d.maxGroups} 組',
                                if (d.maxGuests != null) '最多 ${d.maxGuests} 位',
                                if (d.maxLarge != null) '大桌 ${d.maxLarge} 組',
                                if (d.note != null) d.note!,
                              ].join('・'),
                        style: TextStyle(color: d.closed ? AppColors.warn : AppColors.muted, fontSize: 12),
                      ),
                      onTap: () => _edit(d),
                      trailing: IconButton(
                        tooltip: '刪除',
                        icon: Icon(Icons.delete_outline, color: AppColors.muted),
                        onPressed: () => _delete(d),
                      ),
                    ),
                  ),
                ),
            ]);
          },
        ),
      );
}
