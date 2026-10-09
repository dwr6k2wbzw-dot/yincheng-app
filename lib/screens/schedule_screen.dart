import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/slip_scan.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 班表（隱城、小城外）：一週一張表；最下面是每天人力。
/// 隱城：記號 V／休／指休／O，正職看「本週休」、兼職看「本週上班」。
/// 小城外：班別代碼 B／BH／RBK、休、指休；兼職填時段；以時數統計。
/// 老闆／店長可點格子改班、點日期加備註、管理人員、填統計數字、上傳原始班表照片。
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

const _offColor = Color(0xFFE0A34A);
const _assignedColor = Color(0xFFE5735F);

Color? _markBg(String? m) => switch (m) {
      '休' => _offColor.withValues(alpha: 0.85),
      '指休' => _assignedColor.withValues(alpha: 0.85),
      'O' => AppColors.primary.withValues(alpha: 0.35),
      'B' => const Color(0xFF4F8FD9).withValues(alpha: 0.45),
      'BH' => const Color(0xFF8A6FD1).withValues(alpha: 0.5),
      'RBK' => const Color(0xFF3FA97A).withValues(alpha: 0.5),
      _ when m != null && ShiftMonth.isRange(m) => AppColors.primary.withValues(alpha: 0.22),
      _ => null,
    };

const _markLabel = {'V': '上班', '休': '休假', '指休': '指定休', 'O': 'O', 'B': 'B 班', 'BH': 'BH 班', 'RBK': 'RBK 班'};
final _rangeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d-([01]\d|2[0-3]):[0-5]\d$');

/// 格子裡顯示的字：時段拆成兩行
String _cellText(String? m) => m == null ? '' : (ShiftMonth.isRange(m) ? m.replaceFirst('-', '\n') : m);

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _week = 0; // 第幾週（0 起算，以週日為一週開始）
  late Future<ShiftMonth> _future;
  ShiftMonth? _data;
  bool _started = false;

  bool get _canEdit => widget.membership.isManager;
  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  String get _storeName => widget.membership.storeName;
  List<String> get _marks => AppConfig.shiftMarks[_storeName] ?? const ['V', '休', '指休', 'O'];
  /// 以時數統計（小城外）：null 表示看天數（隱城）
  Map<String, double>? get _codeHours => AppConfig.shiftHours[_storeName];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _week = _weekOf(DateTime.now());
      _future = _load();
    }
  }

  Future<ShiftMonth> _load() async {
    final d = await _repo.shiftMonth(_store, _month);
    _data = d;
    return d;
  }

  void _reload() => setState(() => _future = _load());

  /// 本月各週的日期範圍（週日～週六）
  List<(int, int)> _weeks() {
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final out = <(int, int)>[];
    var start = 1;
    while (start <= days) {
      final wd = DateTime(_month.year, _month.month, start).weekday % 7; // 週日＝0
      final end = (start + (6 - wd)).clamp(1, days);
      out.add((start, end));
      start = end + 1;
    }
    return out;
  }

  int _weekOf(DateTime d) {
    if (d.year != _month.year || d.month != _month.month) return 0;
    final w = _weeks();
    return w.indexWhere((x) => d.day >= x.$1 && d.day <= x.$2).clamp(0, w.length - 1);
  }

  void _shiftMonth(int n) {
    _month = DateTime(_month.year, _month.month + n);
    _week = _weekOf(DateTime.now());
    _reload();
  }

  // ---------------- 編輯 ----------------
  Future<void> _editCell(ShiftPerson p, int day, String? current) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${p.name}・${DateFormat('M/d（E）', 'zh_TW').format(DateTime(_month.year, _month.month, day))}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final m in _marks)
                ChoiceChip(
                  label: Text(m == 'V' ? 'V 上班' : m),
                  selected: m == current,
                  selectedColor: _markBg(m) ?? AppColors.cardHigh,
                  onSelected: (_) => Navigator.pop(c, m),
                ),
              ActionChip(label: const Text('清除'), onPressed: () => Navigator.pop(c, '')),
            ]),
            if (_codeHours != null) ...[
              const SizedBox(height: 16),
              const Text('兼職時段', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in AppConfig.shiftQuickRanges)
                  ChoiceChip(
                    label: Text(r),
                    selected: r == current,
                    onSelected: (_) => Navigator.pop(c, r),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('其他時段'),
                  onPressed: () async {
                    final v = await _askRange(c, current);
                    if (v != null && c.mounted) Navigator.pop(c, v);
                  },
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
    if (picked == null || picked == current || (picked.isEmpty && current == null)) return;
    final mark = picked.isEmpty ? null : picked;
    // 先改畫面，再存資料庫；失敗就重新載入
    setState(() {
      final m = _data!.marks.putIfAbsent(p.id, () => {});
      if (mark == null) {
        m.remove(day);
      } else {
        m[day] = mark;
      }
    });
    try {
      await _repo.setShift(_store, p.id, DateTime(_month.year, _month.month, day), mark);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      _reload();
    }
  }

  Future<String?> _askRange(BuildContext ctx, String? current) async {
    final t = TextEditingController(text: ShiftMonth.isRange(current) ? current! : '');
    String? err;
    return showDialog<String>(
      context: ctx,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('輸入時段'),
          content: TextField(
            controller: t,
            autofocus: true,
            decoration: InputDecoration(hintText: '例：18:00-00:30', errorText: err),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final v = t.text.trim().replaceAll('：', ':').replaceAll(RegExp(r'\s'), '').replaceAll(RegExp('[~～－—–]'), '-');
                if (!_rangeRe.hasMatch(v)) {
                  set(() => err = '格式：開始-結束，例 18:00-00:30');
                  return;
                }
                Navigator.pop(d, v);
              },
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(int day, String? current) async {
    final c = TextEditingController(text: current ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${_month.month}/$day 備註'),
        content: TextField(controller: c, autofocus: true, maxLength: 20, decoration: const InputDecoration(hintText: '例：月會日、國慶日')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
          if (current != null) TextButton(onPressed: () => Navigator.pop(d, ''), child: const Text('刪除')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('儲存')),
        ],
      ),
    );
    if (v == null) return;
    try {
      await _repo.setShiftNote(_store, DateTime(_month.year, _month.month, day), v.isEmpty ? null : v);
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editStats(ShiftPerson p, ShiftMonth d) async {
    final st = d.stats[p.id] ?? const ShiftStats();
    final hoursMode = _codeHours != null;
    String f(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
    final s = TextEditingController(text: f(hoursMode ? st.compUnused : st.shouldOff));
    final u = TextEditingController(text: f(hoursMode ? st.specialTotal : st.prevUnused));
    DateTime? hire = p.hireDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${p.name}・${_month.month} 月'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: s, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: hoursMode ? '未休／補休（天）' : '本月應休（天）')),
            TextField(controller: u, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: hoursMode ? '累計特休（天）' : '原未休特休（天）')),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('報到日'),
              trailing: Text(hire == null ? '未填' : DateFormat('yyyy/M/d').format(hire!)),
              onTap: () async {
                final x = await showDatePicker(
                    context: c, initialDate: hire ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2035));
                if (x != null) set(() => hire = x);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('儲存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final a = double.tryParse(s.text), b = double.tryParse(u.text);
      await _repo.saveShiftStats(
          _store,
          p.id,
          _month,
          hoursMode
              ? ShiftStats(shouldOff: st.shouldOff, prevUnused: st.prevUnused, compUnused: a, specialTotal: b)
              : ShiftStats(shouldOff: a, prevUnused: b, compUnused: st.compUnused, specialTotal: st.specialTotal));
      if (hire != p.hireDate) {
        await _repo.saveShiftPerson(_store, ShiftPerson(id: p.id, name: p.name, kind: p.kind, sortOrder: p.sortOrder, hireDate: hire, active: p.active, roleCode: p.roleCode));
      }
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _managePeople(ShiftMonth d) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PeopleScreen(storeId: _store, people: d.people)));
    _reload();
  }

  Future<void> _uploadPhoto() async {
    String? photo;
    try {
      photo = await pickSlipImage();
    } catch (e) {
      if (mounted) showMessage(context, '照片讀取失敗：$e', error: true);
      return;
    }
    if (photo == null) return;
    try {
      await _repo.uploadShiftPhoto(_store, _month, dataUrlBytes(photo));
      if (mounted) showMessage(context, '已上傳 ${_month.month} 月班表照片');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _showPhoto(String path) async {
    try {
      final url = await _repo.shiftPhotoUrl(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          insetPadding: const EdgeInsets.all(8),
          child: InteractiveViewer(maxScale: 5, child: Image.network(url, fit: BoxFit.contain)),
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  // ---------------- 畫面 ----------------
  @override
  Widget build(BuildContext context) => FutureBuilder<ShiftMonth>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
          if (!snap.hasData && _data == null) return const Center(child: CircularProgressIndicator());
          final d = _data ?? snap.data!;
          final weeks = _weeks();
          final wk = weeks[_week.clamp(0, weeks.length - 1)];
          final full = d.people.where((p) => p.active && p.isFull).toList();
          final part = d.people.where((p) => p.active && !p.isFull).toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
              Row(children: [
                IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(DateFormat('yyyy 年 M 月', 'zh_TW').format(_month),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                ),
                IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
              ]),
              _todayCard(d),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (i, w) in weeks.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(w.$1 == w.$2 ? '${_month.month}/${w.$1}' : '${_month.month}/${w.$1}–${w.$2}'),
                        selected: i == _week,
                        onSelected: (_) => setState(() => _week = i),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              if (d.people.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('這個月還沒有班表', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                )
              else
                SectionCard(padding: const EdgeInsets.fromLTRB(8, 10, 8, 10), child: _weekGrid(d, wk, full, part)),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 4, children: [
                for (final m in _marks) _legend(m, _markBg(m), _markLabel[m] ?? m),
                if (_codeHours != null) _legend('時段', _markBg('18:00-00:30'), '兼職時段'),
              ]),
              if (_codeHours != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      '時數：${_codeHours!.entries.map((e) => '${e.key} ${_num(e.value)} 小時').join('、')}；時段照實際時間算（未驗證：班別時數是依 10 月總時數反推）',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ),
              const SizedBox(height: 16),
              if (_codeHours != null)
                _hoursSummary(d, [...full, ...part])
              else if (full.isNotEmpty)
                _monthSummary(d, full),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (d.photoPath != null)
                  OutlinedButton.icon(
                    onPressed: () => _showPhoto(d.photoPath!),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('原始班表照片'),
                  ),
                if (_canEdit) ...[
                  OutlinedButton.icon(
                    onPressed: _uploadPhoto,
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(d.photoPath == null ? '上傳班表照片' : '更換班表照片'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _managePeople(d),
                    icon: const Icon(Icons.people_outline),
                    label: const Text('班表人員'),
                  ),
                ],
              ]),
              if (_canEdit)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(_codeHours != null ? '點格子改班（兼職可選時段）、點日期加備註、點下方統計填未休／補休與特休。' : '點格子改班、點日期加備註、點下方統計填應休與特休。',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
            ]),
          );
        },
      );

  Widget _legend(String m, Color? bg, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: bg ?? Colors.transparent,
              border: bg == null ? Border.all(color: AppColors.cardHigh) : null,
              borderRadius: BorderRadius.circular(4)),
          child: Text(m, style: const TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ]);

  Widget _todayCard(ShiftMonth d) {
    final now = DateTime.now();
    if (now.year != _month.year || now.month != _month.month) return const SizedBox.shrink();
    final on = d.people.where((p) => p.active && ShiftMonth.isOn(d.mark(p.id, now.day))).map((p) => p.name).toList();
    final off = d.people.where((p) => p.active && p.isFull && ShiftMonth.isOff(d.mark(p.id, now.day))).map((p) => p.name).toList();
    final note = d.notes[now.day];
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('今天 ${DateFormat('M/d（E）', 'zh_TW').format(now)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('人力 ${on.length}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
        ]),
        if (note != null) Text(note, style: const TextStyle(color: AppColors.warn, fontSize: 12)),
        const SizedBox(height: 6),
        Text('上班：${on.isEmpty ? '—' : on.join('、')}', style: const TextStyle(fontSize: 13)),
        if (off.isNotEmpty) Text('休：${off.join('、')}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      ]),
    );
  }

  Widget _weekGrid(ShiftMonth d, (int, int) wk, List<ShiftPerson> full, List<ShiftPerson> part) {
    // 一週固定 7 欄（月初、月底不足的日子留空），寬度依螢幕平分
    final firstWd = DateTime(_month.year, _month.month, wk.$1).weekday % 7;
    final cols = List<int?>.generate(7, (i) {
      final day = wk.$1 + (i - firstWd);
      return (day >= wk.$1 && day <= wk.$2) ? day : null;
    });
    const wd = ['日', '一', '二', '三', '四', '五', '六'];
    final today = DateTime.now();
    return LayoutBuilder(builder: (context, box) {
      const nameW = 48.0, sumW = 30.0;
      final cellW = ((box.maxWidth - nameW - sumW) / 7).clamp(34.0, 60.0);
      Widget cell(Widget child, {Color? bg, VoidCallback? onTap, double h = 30, Border? border}) => GestureDetector(
            onTap: onTap,
            child: Container(
              width: cellW,
              height: h,
              margin: const EdgeInsets.all(1),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5), border: border),
              child: child,
            ),
          );
      Widget name(String t, {bool bold = false, Color? color}) => SizedBox(
            width: nameW,
            child: Text(t,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
          );
      Widget sum(String t, {Color? color}) => SizedBox(
            width: sumW,
            child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: color ?? AppColors.muted)),
          );
      Widget personRow(ShiftPerson p) {
        final ch = _codeHours;
        final String total;
        if (ch != null && !p.isFull) {
          total = _num(cols.whereType<int>().fold(0.0, (a, day) => a + ShiftMonth.hoursOf(d.mark(p.id, day), ch)));
        } else {
          total = '${cols.whereType<int>().where((day) {
            final m = d.mark(p.id, day);
            return p.isFull ? ShiftMonth.isOff(m) : ShiftMonth.isOn(m);
          }).length}';
        }
        return Row(children: [
          name(p.roleCode == null ? p.name : '${p.name}\n${p.roleCode}'),
          for (final day in cols)
            if (day == null)
              cell(const SizedBox.shrink())
            else
              cell(
                Text(_cellText(d.mark(p.id, day)),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: ShiftMonth.isRange(d.mark(p.id, day)) ? 9 : 12,
                        height: 1.1,
                        fontWeight: FontWeight.w600)),
                h: _codeHours != null ? 34 : 30,
                bg: _markBg(d.mark(p.id, day)),
                border: _markBg(d.mark(p.id, day)) == null ? Border.all(color: AppColors.cardHigh) : null,
                onTap: _canEdit ? () => _editCell(p, day, d.mark(p.id, day)) : null,
              ),
          sum(total),
        ]);
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 標題：星期、日期、備註
          Row(children: [
            name(''),
            for (final (i, day) in cols.indexed)
              cell(
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(wd[i], style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                  Text(day == null ? '' : '$day',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: day != null && today.year == _month.year && today.month == _month.month && today.day == day
                              ? AppColors.primary
                              : null)),
                ]),
                h: 36,
                onTap: day != null && _canEdit ? () => _editNote(day, d.notes[day]) : null,
              ),
            sum(''),
          ]),
          if (cols.any((day) => day != null && d.notes[day] != null))
            Row(children: [
              name(''),
              for (final day in cols)
                cell(
                  Text(day == null ? '' : (d.notes[day] ?? ''),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: Colors.black)),
                  bg: day != null && d.notes[day] != null ? const Color(0xFF7CC6F2) : null,
                  h: 26,
                  onTap: day != null && _canEdit ? () => _editNote(day, d.notes[day]) : null,
                ),
              sum(''),
            ]),
          const SizedBox(height: 4),
          Row(children: [name('正職', color: AppColors.muted), const Spacer(), sum('休', color: AppColors.muted)]),
          for (final p in full) personRow(p),
          if (part.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: nameW + sumW + (cellW + 2) * 7,
              child: Row(children: [name('兼職', color: AppColors.muted), const Spacer(), sum(_codeHours != null ? '時' : '班', color: AppColors.muted)]),
            ),
            for (final p in part) personRow(p),
          ],
          const SizedBox(height: 4),
          Row(children: [
            name('人力', bold: true, color: AppColors.primary),
            for (final day in cols)
              cell(
                Text(day == null ? '' : '${d.staffing(day)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
              ),
            sum(''),
          ]),
        ]),
      );
    });
  }

  Widget _monthSummary(ShiftMonth d, List<ShiftPerson> full) {
    String n(double? v) => v == null ? '—' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));
    TableRow row(List<String> cells, {bool head = false, VoidCallback? onTap}) => TableRow(children: [
          for (final (i, c) in cells.indexed)
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Text(c,
                    textAlign: i == 0 ? TextAlign.left : TextAlign.center,
                    style: TextStyle(
                        fontSize: head ? 11 : 13,
                        color: head ? AppColors.muted : null,
                        fontWeight: i == 0 && !head ? FontWeight.w600 : null)),
              ),
            ),
        ]);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_month.month} 月休假統計（正職）', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 6),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3)},
          children: [
            row(['', '應休', '已休', '原未休\n特休', '剩餘未休\n特休', '報到日'], head: true),
            for (final p in full)
              () {
                final st = d.stats[p.id] ?? const ShiftStats();
                final should = st.shouldOff, prev = st.prevUnused;
                final taken = d.offDays(p.id).toDouble();
                final remain = (should != null && prev != null) ? prev - (taken - should) : null;
                return row([
                  p.name,
                  n(should),
                  n(taken),
                  n(prev),
                  n(remain),
                  p.hireDate == null ? '—' : DateFormat('yy/M/d').format(p.hireDate!),
                ], onTap: _canEdit ? () => _editStats(p, d) : null);
              }(),
          ],
        ),
        const SizedBox(height: 6),
        const Text('已休＝休＋指休；剩餘未休特休＝原未休特休 −（已休 − 應休）',
            style: TextStyle(color: AppColors.muted, fontSize: 11)),
      ]),
    );
  }

  /// 小城外：總時數（自動算）、月休（自動算）、未休／補休、累計特休（手動）
  Widget _hoursSummary(ShiftMonth d, List<ShiftPerson> people) {
    final ch = _codeHours!;
    String n(double? v) => v == null ? '—' : _num(v);
    TableRow row(List<String> cells, {bool head = false, VoidCallback? onTap}) => TableRow(children: [
          for (final (i, c) in cells.indexed)
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Text(c,
                    textAlign: i == 0 ? TextAlign.left : TextAlign.center,
                    style: TextStyle(
                        fontSize: head ? 11 : 13,
                        color: head ? AppColors.muted : null,
                        fontWeight: i == 0 && !head ? FontWeight.w600 : null)),
              ),
            ),
        ]);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_month.month} 月統計', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 6),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.3)},
          children: [
            row(['', '總時數', '上班\n天數', '月休', '未休\n補休', '累計\n特休'], head: true),
            for (final p in people)
              () {
                final st = d.stats[p.id] ?? const ShiftStats();
                return row([
                  p.isFull ? p.name : '${p.name}（兼）',
                  _num(d.hours(p.id, ch)),
                  '${d.workDays(p.id)}',
                  p.isFull ? '${d.offDays(p.id)}' : '—',
                  p.isFull ? n(st.compUnused) : '—',
                  p.isFull ? n(st.specialTotal) : '—',
                ], onTap: _canEdit && p.isFull ? () => _editStats(p, d) : null);
              }(),
          ],
        ),
        const SizedBox(height: 6),
        const Text('總時數＝整個月（含月底最後一天）；月休＝休＋指休；未休／補休、累計特休由老闆或店長填。',
            style: TextStyle(color: AppColors.muted, fontSize: 11)),
      ]),
    );
  }
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// 班表人員：新增、改名、正職／兼職、排序、隱藏
class _PeopleScreen extends StatefulWidget {
  const _PeopleScreen({required this.storeId, required this.people});
  final String storeId;
  final List<ShiftPerson> people;
  @override
  State<_PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<_PeopleScreen> {
  late List<ShiftPerson> _people = [...widget.people];

  Future<void> _edit(ShiftPerson? p) async {
    final name = TextEditingController(text: p?.name ?? '');
    final order = TextEditingController(text: '${p?.sortOrder ?? (_people.length + 1) * 10}');
    var kind = p?.kind ?? 'full';
    final role = TextEditingController(text: p?.roleCode ?? '');
    var active = p?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(p == null ? '新增人員' : '修改 ${p.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, maxLength: 20, decoration: const InputDecoration(labelText: '名字')),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'full', label: Text('正職')), ButtonSegment(value: 'part', label: Text('兼職'))],
              selected: {kind},
              onSelectionChanged: (v) => set(() => kind = v.first),
            ),
            TextField(controller: role, maxLength: 10, decoration: const InputDecoration(labelText: '職務／班別（選填，例 B/R）')),
            TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '排序（數字小的在上面）')),
            if (p != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('顯示在班表'),
                value: active,
                onChanged: (v) => set(() => active = v),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('儲存')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    final repo = AppScope.of(context).repo;
    final np = ShiftPerson(
        id: p?.id ?? '',
        name: name.text.trim(),
        kind: kind,
        sortOrder: int.tryParse(order.text) ?? 0,
        hireDate: p?.hireDate,
        active: active,
        roleCode: role.text.trim().isEmpty ? null : role.text.trim());
    try {
      await repo.saveShiftPerson(widget.storeId, np, isNew: p == null);
      final d = await repo.shiftMonth(widget.storeId, DateTime.now());
      if (mounted) setState(() => _people = d.people);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('班表人員')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('新增人員'),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          for (final p in _people)
            ListTile(
              title: Text(p.name, style: TextStyle(color: p.active ? null : AppColors.muted)),
              subtitle: Text('${p.isFull ? '正職' : '兼職'}${p.roleCode == null ? '' : '・${p.roleCode}'}・排序 ${p.sortOrder}${p.active ? '' : '・已隱藏'}',
                  style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _edit(p),
            ),
          const SizedBox(height: 8),
          const Text('人員不會被刪除（避免舊班表對不上）；不用了就關掉「顯示在班表」。',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );
}
