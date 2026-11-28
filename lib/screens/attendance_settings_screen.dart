import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 打卡設定（ops 0163，公版；只有老闆能改）：開不開放打卡、跟班表差幾分鐘算異常、
/// 異常從哪天起列、補登幾次後要老闆核准、店長看不看得到薪資。改了會記在出勤異動紀錄。
class AttendanceSettingsScreen extends StatefulWidget {
  const AttendanceSettingsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<AttendanceSettingsScreen> createState() =>
      _AttendanceSettingsScreenState();
}

class _AttendanceSettingsScreenState extends State<AttendanceSettingsScreen> {
  AttendanceSettings? _saved; // 資料庫裡的
  AttendanceSettings? _draft; // 畫面上改到一半的
  String? _loadError;
  bool _started = false;
  bool _busy = false;
  String? _formError;
  final _grace = TextEditingController();
  final _amend = TextEditingController();
  bool _amendUnlimited = false;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;
  bool get _canEdit =>
      (_saved?.canEdit ?? false) && widget.membership.role == Role.owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _grace.dispose();
    _amend.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final s = await _repo.attendanceSettings(_store);
      if (!mounted) return;
      setState(() {
        _saved = s;
        _draft = s;
        _grace.text = '${s.graceMin}';
        _amendUnlimited = s.amendOwnerAfter == null;
        _amend.text = '${s.amendOwnerAfter ?? 3}';
        _formError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = friendlyError(e));
    }
  }

  /// 畫面上的值組成一份設定；打錯就回 null 並把原因寫在表單上
  AttendanceSettings? _collect({bool showError = true}) {
    final d = _draft!;
    final gp = attendanceGraceProblem(_grace.text);
    final ap = _amendUnlimited ? null : attendanceAmendProblem(_amend.text);
    final problem = gp ?? ap;
    if (problem != null) {
      if (showError) setState(() => _formError = problem);
      return null;
    }
    return d.copyWith(
      graceMin: int.parse(_grace.text.trim()),
      amendOwnerAfter: () =>
          _amendUnlimited ? null : int.parse(_amend.text.trim()),
    );
  }

  bool get _dirty {
    final s = _saved;
    if (s == null || _draft == null) return false;
    final c = _collect(showError: false);
    return c == null || c.changesFrom(s).isNotEmpty;
  }

  Future<void> _save() async {
    final next = _collect();
    final before = _saved;
    if (next == null || before == null) return;
    final changes = next.changesFrom(before);
    if (changes.isEmpty) return;
    if (before.enabled && !next.enabled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('關掉打卡？'),
          content: const Text('關掉之後員工不能打卡、不能申請補登；已經打的卡和紀錄都會留著。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('關掉')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      await _repo.saveAttendanceSettings(_store, changes);
      notifyAttendanceSettingsSaved(_store);
    } catch (e) {
      if (mounted) setState(() => _formError = friendlyError(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) showMessage(context, '打卡設定已儲存');
  }

  Future<void> _pickCheckFrom() async {
    final d = _draft!;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: d.checkFrom ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: '異常從哪天起列',
    );
    if (picked != null) {
      setState(() => _draft = d.copyWith(checkFrom: () => picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return Scaffold(
      appBar: AppBar(title: const Text('打卡設定')),
      body: d == null
          ? (_loadError != null
              ? ErrorView(message: _loadError!, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                InfoLine(
                  icon: Icons.info_outline,
                  text: _canEdit ? '只有老闆能改，改了會記在出勤異動紀錄' : '只有老闆能改，你看得到目前的設定',
                  detail:
                      '打卡紀錄本身不能改也不能刪（勞基法要保存 5 年）。這裡改的是規則：之後的異常清單、比對班表、補登核准照新的規則算。',
                ),
                _section(
                  icon: Icons.fingerprint,
                  title: '打卡',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: d.enabled,
                      onChanged: _canEdit && !_busy
                          ? (v) =>
                              setState(() => _draft = d.copyWith(enabled: v))
                          : null,
                      title: const Text('開放打卡'),
                      subtitle: Text(
                          d.enabled
                              ? '員工用店裡的打卡平板輸入自己的密碼打卡'
                              : '還沒開放：員工資料、薪資照常可以用',
                          style: const TextStyle(fontSize: AppType.small)),
                    ),
                  ],
                ),
                _section(
                  icon: Icons.rule,
                  title: '跟班表比對',
                  children: [
                    TextField(
                      controller: _grace,
                      enabled: _canEdit && !_busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() => _formError = null),
                      decoration: const InputDecoration(
                        labelText: '差幾分鐘以上算異常',
                        suffixText: '分鐘',
                        helperText: '早到、遲到、早退、晚走都照這個算（5～180）',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('異常從哪天起列'),
                              const SizedBox(height: 2),
                              Text(
                                  d.checkFrom == null
                                      ? '不限（全部都列）'
                                      : DateFormat('yyyy/M/d')
                                          .format(d.checkFrom!),
                                  style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: AppType.small)),
                            ]),
                      ),
                      if (_canEdit && d.checkFrom != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() =>
                                  _draft = d.copyWith(checkFrom: () => null)),
                          child: const Text('清除'),
                        ),
                      if (_canEdit)
                        OutlinedButton(
                            onPressed: _busy ? null : _pickCheckFrom,
                            child: const Text('選日期')),
                    ]),
                  ],
                ),
                _section(
                  icon: Icons.edit_calendar_outlined,
                  title: '補登',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _amendUnlimited,
                      onChanged: _canEdit && !_busy
                          ? (v) => setState(() {
                                _amendUnlimited = v;
                                _formError = null;
                              })
                          : null,
                      title: const Text('補登店長都能核准'),
                      subtitle: const Text('關掉＝同一個人一個月補登太多次，要老闆才能核准',
                          style: TextStyle(fontSize: AppType.small)),
                    ),
                    if (!_amendUnlimited)
                      TextField(
                        controller: _amend,
                        enabled: _canEdit && !_busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onChanged: (_) => setState(() => _formError = null),
                        decoration: InputDecoration(
                          labelText: '一個月核准幾次以後要老闆核准',
                          suffixText: '次',
                          helperText: _amendHelper(),
                        ),
                      ),
                  ],
                ),
                _section(
                  icon: Icons.payments_outlined,
                  title: '薪資',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: d.managerPayroll,
                      onChanged: _canEdit && !_busy
                          ? (v) => setState(
                              () => _draft = d.copyWith(managerPayroll: v))
                          : null,
                      title: const Text('店長看得到薪資'),
                      subtitle: const Text('開著＝店長能看、能算別人的薪資（看不到自己的）；關掉＝只有老闆',
                          style: TextStyle(fontSize: AppType.small)),
                    ),
                  ],
                ),
                if (_formError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(_formError!,
                        style: TextStyle(
                            color: AppColors.bad, fontWeight: AppFont.label)),
                  ),
                if (_canEdit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _busy || !_dirty ? null : _save,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('儲存'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  String _amendHelper() {
    final n = int.tryParse(_amend.text.trim());
    if (n == null || n < 0 || n > 31) return '0～31；0＝每一筆都要老闆核准';
    if (n == 0) return '每一筆補登都要老闆核准';
    return '第 ${n + 1} 次補登起只有老闆能核准';
  }

  Widget _section(
          {required IconData icon,
          required String title,
          required List<Widget> children}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SectionCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: AppType.title, fontWeight: AppFont.heading)),
            ]),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );
}
