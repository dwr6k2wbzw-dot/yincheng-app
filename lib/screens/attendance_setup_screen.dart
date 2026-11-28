import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/attendance_setup.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'attendance_check_screen.dart' show editShiftMarkTimes;
import 'members_screen.dart';
import 'pin_punch_screen.dart' show editPunchPin;

/// 打卡設定（ops 0164，公版階段 4；老闆、店長）。新店從零開始用打卡，一步一步做完：
/// 打開打卡 → 打卡用帳號（店裡的平板）→ 員工對應帳號（建議）→ 打卡密碼 → 班的時間 → 試打一次卡。
/// 每一步做完了沒都從資料庫算（`attendance_setup_status`），點進去就能做。
class AttendanceSetupScreen extends StatefulWidget {
  const AttendanceSetupScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<AttendanceSetupScreen> createState() => _AttendanceSetupScreenState();
}

class _AttendanceSetupScreenState extends State<AttendanceSetupScreen> {
  AttendanceSetupStatus? _s;
  String? _loadError;
  bool _started = false;
  bool _busy = false;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final s = await _repo.attendanceSetupStatus(_store);
      if (mounted) {
        setState(() {
          _s = s;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = friendlyError(e));
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _enable() => _run(() async {
        await _repo.attendanceSetupEnable(_store);
        if (mounted) showMessage(context, '打卡打開了');
      });

  Future<void> _kioskInvite() async {
    String code;
    setState(() => _busy = true);
    try {
      code = await _repo.attendanceKioskInvite(_store);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => _KioskInviteDialog(code: code),
    );
    await _load();
  }

  Future<void> _assign(SetupPerson p) async {
    List<ShiftAccountCandidate> accounts;
    try {
      accounts = await _repo.shiftAccountCandidates(_store);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    final isOwner = _s?.canOwner ?? false;
    final me = _repo.currentUserId;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(c).size.height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '「${p.name}」是哪一個 App 帳號？',
                style: const TextStyle(
                  fontSize: AppType.title,
                  fontWeight: AppFont.heading,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '指定好就生效：那個人登入後直接是自己，可以看自己的出勤和薪資單。',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              if (accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '還沒有可以選的帳號。先到「成員管理」邀請員工加入，他用邀請碼建立帳號後就會出現在這裡。',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: AppType.small,
                      height: 1.5,
                    ),
                  ),
                ),
              for (final a in accounts)
                Builder(
                  builder: (_) {
                    final elsewhere = a.personId != null && a.personId != p.id;
                    final block = isOwner
                        ? null
                        : a.userId == me
                            ? '自己的帳號要請老闆對應'
                            : elsewhere && a.verified
                                ? '已經對應到「${a.personName ?? ''}」，要改請找老闆'
                                : null;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      minTileHeight: 56,
                      enabled: block == null,
                      title: Text(a.name.isEmpty ? '（沒有名字）' : a.name),
                      subtitle: Text(
                        [
                          roleLabel(roleFrom(a.role)),
                          if (block != null) block,
                          if (block == null && elsewhere)
                            '目前是「${a.personName ?? ''}」，改指定會解除那邊',
                        ].join('・'),
                        style: const TextStyle(fontSize: AppType.small),
                      ),
                      onTap: () => Navigator.pop(c, a.userId),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _run(() async {
      await _repo.assignShiftAccount(p.id, picked);
      if (mounted) showMessage(context, '對應好了，「${p.name}」登入後就是自己');
    });
  }

  Future<void> _pin(SetupPerson p) async {
    final changed = await editPunchPin(
      context,
      personId: p.id,
      name: p.name,
      hasPin: false,
    );
    if (changed) await _load();
  }

  Future<void> _times() async {
    final changed = await editShiftMarkTimes(context, _store);
    if (changed) await _load();
  }

  void _members() => Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (_) => MembersScreen(membership: widget.membership),
        ),
      )
      .then((_) => _load());

  // 已經有進度、重新整理失敗時（例如設完密碼、產生邀請碼之後）：照樣顯示上一次的進度，
  // 上面標出「這不是最新的」和重試（Codex：原本這種失敗看不到）
  Widget _staleBanner(String message) => Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('setup_stale_banner'),
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
            color: AppColors.bad.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.bad.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: AppColors.bad),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '沒有更新到最新的進度：$message',
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _load,
                style: TextButton.styleFrom(minimumSize: const Size(64, 44)),
                child: const Text('重試'),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('打卡開始使用')),
      body: s == null
          ? (_loadError != null
              ? ErrorView(message: _loadError!, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_loadError != null) ...[
                    _staleBanner(_loadError!),
                    const SizedBox(height: 12),
                  ],
                  _progress(s),
                  const SizedBox(height: 12),
                  _step(
                    s,
                    SetupStep.enable,
                    1,
                    '打開打卡',
                    '打開之後，店裡的平板才能打卡，出勤管理也會出現打卡紀錄。',
                    _enableBody(s),
                  ),
                  _step(
                    s,
                    SetupStep.kiosk,
                    2,
                    '打卡用帳號（店裡的平板）',
                    '店裡放一台平板，用一個專門的帳號登入，第一頁就是打卡鍵盤。',
                    _kioskBody(s),
                  ),
                  _step(
                    s,
                    SetupStep.accounts,
                    3,
                    '員工對應 App 帳號（建議）',
                    '對應好之後，員工用自己的手機就看得到自己的出勤、薪資單。不對應也能打卡。',
                    _accountsBody(s),
                  ),
                  _step(
                    s,
                    SetupStep.pins,
                    4,
                    '打卡密碼',
                    '每個人一組 4 位數密碼，打卡時在平板輸入。',
                    _pinsBody(s),
                  ),
                  _step(
                    s,
                    SetupStep.times,
                    5,
                    '班的時間',
                    '設好每種班幾點到幾點，才能跟打卡比對遲到、早退、加班。',
                    _timesBody(s),
                  ),
                  _step(
                    s,
                    SetupStep.test,
                    6,
                    '試打一次卡',
                    '在平板輸入一位員工的密碼，確認打得進來。',
                    _testBody(s),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _progress(AttendanceSetupStatus s) {
    final n = s.requiredDone, total = AttendanceSetupStatus.required.length;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                s.ready ? Icons.check_circle_outline : Icons.fingerprint,
                color: s.ready ? AppColors.good : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.ready ? '打卡設定好了' : '還差 ${total - n} 項就能開始打卡',
                  style: const TextStyle(
                    fontSize: AppType.title,
                    fontWeight: AppFont.heading,
                  ),
                ),
              ),
              Text(
                '$n／$total',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : n / total,
              minHeight: 6,
              backgroundColor: AppColors.cardHigh,
              color: s.ready ? AppColors.good : AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.ready
                ? '員工可以在店裡的平板輸入密碼打卡了。遲到、早退、漏打會列在出勤管理的「異常」。'
                : '照順序做，每一步點進去就能完成；第 3 步是建議，不做也能打卡。',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: AppType.small,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(
    AttendanceSetupStatus s,
    SetupStep step,
    int no,
    String title,
    String desc,
    Widget body,
  ) {
    final done = s.done(step);
    final optional = !AttendanceSetupStatus.required.contains(step);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _badge(no, done, optional),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: AppType.title,
                          fontWeight: AppFont.heading,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: AppType.small,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    );
  }

  Widget _badge(int no, bool done, bool optional) => Semantics(
        label: done ? '已完成' : (optional ? '建議' : '還沒完成'),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? AppColors.good : Colors.transparent,
            border: done ? null : Border.all(color: AppColors.muted),
          ),
          child: done
              ? Icon(Icons.check, size: 18, color: AppColors.bg)
              : Text(
                  '$no',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: AppType.small),
                ),
        ),
      );

  Widget _doneLine(String text) => Row(
        children: [
          Icon(Icons.check, size: 18, color: AppColors.good),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: AppType.small, height: 1.5),
            ),
          ),
        ],
      );

  Widget _note(String text, {bool warn = false}) => Text(
        text,
        style: TextStyle(
          color: warn ? AppColors.warn : AppColors.muted,
          fontSize: AppType.small,
          height: 1.5,
        ),
      );

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool tonal = false,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 48,
        child: tonal
            ? FilledButton.tonalIcon(
                onPressed: _busy ? null : onPressed,
                icon: Icon(icon, size: 20),
                label: Text(label),
              )
            : FilledButton.icon(
                onPressed: _busy ? null : onPressed,
                icon: Icon(icon, size: 20),
                label: Text(label),
              ),
      );

  Widget _enableBody(AttendanceSetupStatus s) {
    if (s.enabled) return _doneLine('已經打開');
    if (!s.canOwner) return _note('要請老闆打開。');
    return _button('打開打卡', Icons.toggle_on_outlined, _enable);
  }

  Widget _kioskBody(AttendanceSetupStatus s) {
    if (s.kioskName != null) return _doneLine('平板帳號：${s.kioskName}');
    if (!s.canOwner) return _note('打卡用帳號只有老闆能設定。');
    final until = s.kioskInviteUntil;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (until != null) ...[
          _note(
            '已經產生一組邀請碼，${DateFormat('M/d').format(toTaipei(until))} 前在平板上輸入有效。忘記代碼就重新產生（舊的會作廢）。',
          ),
          const SizedBox(height: 10),
        ],
        _button(
          until == null ? '產生平板用的邀請碼' : '重新產生邀請碼',
          Icons.tablet_mac_outlined,
          _kioskInvite,
          tonal: until != null,
        ),
      ],
    );
  }

  Widget _accountsBody(AttendanceSetupStatus s) {
    if (s.people == 0) return _note('班表上還沒有人。先到「班表」新增班表人員。');
    if (s.unbound.isEmpty) return _doneLine('${s.people} 個人都對應好了');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _note('還沒對應（${s.unbound.length} 人），點名字選他的帳號：'),
        const SizedBox(height: 8),
        _names(s.unbound, _assign),
        const SizedBox(height: 10),
        _button('邀請員工加入', Icons.person_add_alt_outlined, _members, tonal: true),
      ],
    );
  }

  Widget _pinsBody(AttendanceSetupStatus s) {
    if (s.people == 0) return _note('班表上還沒有人。先到「班表」新增班表人員。');
    if (s.noPin.isEmpty) return _doneLine('${s.people} 個人都設好了');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _note('還沒設（${s.noPin.length} 人）。點名字幫他設；對應好帳號的員工，也可以在自己手機的班表頁自己設。'),
        const SizedBox(height: 8),
        _names(s.noPin, _pin),
      ],
    );
  }

  Widget _timesBody(AttendanceSetupStatus s) {
    final parts = <Widget>[];
    if (s.done(SetupStep.times)) {
      parts.add(_doneLine(s.shiftCodes ? '每個班別都有時間' : '班的時間設好了'));
    } else if (s.untimed.isNotEmpty) {
      parts.add(_note('班表上排了「${s.untimed.join('、')}」，還不知道是幾點到幾點。', warn: true));
    } else if (!s.hasTime) {
      parts.add(_note(s.shiftCodes ? '還沒有任何班別。' : '還沒設「V」（上班）是幾點到幾點。'));
    }
    if (s.shiftCodes) {
      if (!s.done(SetupStep.times)) {
        parts
          ..add(const SizedBox(height: 8))
          ..add(_note('到「班表」頁按「班別／時段」，替每個班別填上時段。'));
      }
    } else {
      parts
        ..add(const SizedBox(height: 10))
        ..add(
          _button(
            s.done(SetupStep.times) ? '修改班的時間' : '設定班的時間',
            Icons.schedule_outlined,
            _times,
            tonal: s.done(SetupStep.times),
          ),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts,
    );
  }

  Widget _testBody(AttendanceSetupStatus s) {
    final last = s.lastPinPunch;
    if (last != null) {
      return _doneLine(
        '最近一次密碼打卡：${DateFormat('M/d HH:mm').format(toTaipei(last))}',
      );
    }
    final ready = s.enabled && s.kioskName != null && s.noPin.length < s.people;
    return _note(
      ready
          ? '在店裡的平板上，請一位員工輸入自己的密碼。打進來之後這一步就會打勾；試打的那筆可以到出勤管理按「不採用」。'
          : '前面的步驟（打開打卡、平板帳號、至少一個人的密碼）做好之後，在平板上試打一次。',
    );
  }

  Widget _names(
    List<SetupPerson> people,
    Future<void> Function(SetupPerson) onTap,
  ) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in people)
            ActionChip(
              label: Text(p.name.isEmpty ? '（沒有名字）' : p.name),
              onPressed: _busy ? null : () => onTap(p),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
        ],
      );
}

/// 平板用的邀請碼：只顯示這一次，附上在平板上要做的步驟
class _KioskInviteDialog extends StatelessWidget {
  const _KioskInviteDialog({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    const steps = [
      '在店裡的平板打開這個 App 的網址（建議加到主畫面）。',
      '登入頁選「我有邀請碼」，用一個新的 Email 建立帳號（例如店裡共用的信箱，不要用員工自己的）。',
      '輸入下面這組邀請碼。完成後平板的第一頁就是打卡鍵盤。',
    ];
    return AlertDialog(
      title: const Text('平板用的邀請碼'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${i + 1}. ${steps[i]}',
                  style: const TextStyle(fontSize: AppType.small, height: 1.5),
                ),
              ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.cardHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontSize: AppType.display,
                  fontWeight: AppFont.figure,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '14 天內有效、只能用一次；這組代碼現在才看得到，關掉後忘了就重新產生。這個帳號只有兼職的權限，不能連到員工資料。',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: AppType.small,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            showMessage(context, '邀請碼已複製');
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('複製'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('好了'),
        ),
      ],
    );
  }
}
