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
  const ReservationsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  late DateTime _day = _today();
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

  Future<(ReservationSettings?, List<Reservation>)> _load() async {
    final r = await Future.wait<dynamic>([_repo.reservationSettings(_store), _repo.reservations(_store, _day, _day)]);
    return (r[0] as ReservationSettings?, r[1] as List<Reservation>);
  }

  void _reload() => setState(() => _future = _load());

  void _shift(int d) {
    _day = DateTime(_day.year, _day.month, _day.day + d);
    _reload();
  }

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
        Row(children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(DateFormat('M/d（E）', 'zh_TW').format(_day) + (_day == _today() ? '・今天' : ''),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ),
          IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
        if (!settings.enabled)
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('線上訂位目前暫停中（老闆可在右上角設定開啟）', style: TextStyle(color: AppColors.warn, fontSize: 13)),
          ),
        SectionCard(
          child: Row(children: [
            Icon(Icons.event_seat_outlined, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(child: Text('${active.length} 組・$guests 位', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            Text('每時段上限 ${settings.maxGuestsPerSlot} 位', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
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
              Text(
                  '${byTime[t]!.where((r) => r.active).fold<int>(0, (s, r) => s + r.party)} / ${settings.maxGuestsPerSlot} 位',
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
      subtitle: Text(
        [
          r.phone,
          r.source == 'web' ? '網路訂位' : '電話訂位',
          if ((r.note ?? '').isNotEmpty) '備註：${r.note}',
          if (r.emailError != null) '確認信寄送失敗',
        ].join('・'),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Text(reservationStatusLabel[r.status] ?? r.status, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }

  Future<void> _actions(Reservation r) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('${r.name}・${r.party} 位・${r.time}', style: const TextStyle(fontWeight: FontWeight.w700))),
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
          ListTile(leading: const Icon(Icons.edit_note), title: const Text('修改備註'), onTap: () => Navigator.pop(c, 'note')),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'call') {
      openExternal('tel:${r.phone.replaceAll(RegExp(r'[^0-9+]'), '')}');
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
        final booked = same.where((x) => x.active && x.time == r.time && x.id != r.id).fold<int>(0, (t, x) => t + x.party);
        final max = settings?.maxGuestsPerSlot ?? 0;
        if (settings != null && booked + r.party > max && mounted) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('超過時段上限'),
              content: Text('${r.time} 已訂 $booked 位，改回這筆 ${r.party} 位會超過上限 $max 位。還是要改嗎？'),
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

/// 電話訂位（員工代客人輸入；不受線上訂位的天數、截止時間、每組人數限制，但會提醒超過時段上限）
class _AddReservationScreen extends StatefulWidget {
  const _AddReservationScreen({required this.membership, required this.settings, required this.day});
  final Membership membership;
  final ReservationSettings settings;
  final DateTime day;
  @override
  State<_AddReservationScreen> createState() => _AddReservationScreenState();
}

class _AddReservationScreenState extends State<_AddReservationScreen> {
  late DateTime _date = widget.day;
  String? _time;
  int _party = 2;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    // 先把表單內容固定下來，檢查名額期間就算有人改欄位，也不會混用新舊值（Codex 審查）
    final date = _date;
    final time = _time;
    final party = _party;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    final note = _note.text.trim();
    if (time == null) {
      showMessage(context, '請選時段', error: true);
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
      // 超過時段上限先確認（電話訂位可以超收，由店家決定）
      final same = await repo.reservations(widget.membership.storeId, date, date);
      if (!mounted) return; // 已離開表單：不要在沒確認的情況下新增（Codex 審查）
      final booked = same.where((r) => r.active && r.time == time).fold<int>(0, (t, r) => t + r.party);
      if (booked + party > widget.settings.maxGuestsPerSlot) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('超過時段上限'),
            content: Text('$time 已訂 $booked 位，再加 $party 位會超過上限 ${widget.settings.maxGuestsPerSlot} 位。還是要新增嗎？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('不要')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('還是新增')),
            ],
          ),
        );
        if (ok != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        if (!mounted) return;
      }
      await repo.addReservation(widget.membership.storeId,
          date: date, time: time, party: party, name: name, phone: phone, email: email, note: note);
      if (mounted) {
        showMessage(context, '已新增訂位');
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
        appBar: AppBar(title: const Text('電話訂位')),
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
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Text('人數', style: TextStyle(color: AppColors.muted)),
            const Spacer(),
            IconButton(onPressed: _party > 1 ? () => setState(() => _party--) : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('$_party', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            IconButton(onPressed: _party < 50 ? () => setState(() => _party++) : null, icon: const Icon(Icons.add_circle_outline)),
          ]),
          TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(labelText: '姓名', counterText: '')),
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
              decoration: const InputDecoration(labelText: 'Email（選填，電話訂位不會寄確認信）', counterText: '')),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLength: 200, maxLines: 2, decoration: const InputDecoration(labelText: '備註（選填）')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('新增訂位'),
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
  late String _first = widget.settings.firstSlot;
  late String _last = widget.settings.lastSlot;
  late String _cutoff = widget.settings.sameDayCutoff;
  late final _name = TextEditingController(text: widget.settings.displayName);
  late final _max = TextEditingController(text: '${widget.settings.maxGuestsPerSlot}');
  late final _party = TextEditingController(text: '${widget.settings.maxParty}');
  late final _days = TextEditingController(text: '${widget.settings.daysAhead}');
  late final _contact = TextEditingController(text: widget.settings.contactNote ?? '');
  bool _saving = false;

  Future<void> _pick(String current, void Function(String) set) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutesOf(current) ~/ 60, minute: minutesOf(current) % 60),
    );
    if (t != null) setState(() => set('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'));
  }

  Future<void> _save() async {
    final max = int.tryParse(_max.text.trim());
    final party = int.tryParse(_party.text.trim());
    final days = int.tryParse(_days.text.trim());
    if (_name.text.trim().isEmpty) {
      showMessage(context, '請填店名', error: true);
      return;
    }
    if (max == null || max < 1 || max > 500) {
      showMessage(context, '每時段上限請填 1～500', error: true);
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
    if (minutesOf(_first) > minutesOf(_last)) {
      showMessage(context, '第一個時段要早於最後一個時段', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).repo.saveReservationSettings(widget.membership.storeId, {
        'enabled': _enabled,
        'display_name': _name.text.trim(),
        'first_slot': _first,
        'last_slot': _last,
        'same_day_cutoff': _cutoff,
        'max_guests_per_slot': max,
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
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('第一個時段'),
              trailing: Text(_first, style: const TextStyle(fontSize: 16)),
              onTap: () => _pick(_first, (v) => _first = v)),
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('最後一個時段'),
              subtitle: Text('每 ${widget.settings.slotMinutes} 分鐘一個時段', style: const TextStyle(fontSize: 12)),
              trailing: Text(_last, style: const TextStyle(fontSize: 16)),
              onTap: () => _pick(_last, (v) => _last = v)),
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('當天訂位截止'),
              subtitle: const Text('這個時間以後不接受當天的線上訂位', style: TextStyle(fontSize: 12)),
              trailing: Text(_cutoff, style: const TextStyle(fontSize: 16)),
              onTap: () => _pick(_cutoff, (v) => _cutoff = v)),
          TextField(controller: _max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '每個時段最多幾位')),
          const SizedBox(height: 12),
          TextField(controller: _party, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '線上訂位一組最多幾位')),
          const SizedBox(height: 12),
          TextField(controller: _days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '可以訂幾天內（含今天）')),
          const SizedBox(height: 12),
          TextField(
              controller: _contact,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '店家資訊（地址、電話等，會顯示在訂位頁和確認信）')),
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
