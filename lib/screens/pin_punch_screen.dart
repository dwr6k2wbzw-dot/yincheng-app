import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';

/// 打卡用帳號的第一頁（ops 0112，老闆 2026-11-16）：員工輸入自己的 4 位數密碼打卡。
/// 時間一律是伺服器時間；打卡成功大字顯示姓名、上班／下班、時間，4 秒後回到鍵盤。
class PinPunchScreen extends StatefulWidget {
  const PinPunchScreen({super.key, required this.kiosk});
  final KioskMine kiosk;
  static const backAfter = Duration(seconds: 4);
  @override
  State<PinPunchScreen> createState() => _PinPunchScreenState();
}

class _PinPunchScreenState extends State<PinPunchScreen> {
  String _pin = '';
  bool _busy = false;
  PinPunchResult? _done; // 打卡成功：大字顯示，時間到回鍵盤
  String? _msg; // 密碼不對、連不上
  DateTime? _lockEnd; // 連錯 5 次：這台手機的時間，倒數用
  Timer? _back, _tick;

  @override
  void dispose() {
    _back?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  bool get _locked => _lockEnd != null && DateTime.now().isBefore(_lockEnd!);

  void _press(String d) {
    if (_busy || _locked || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _msg = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _clear() {
    if (_busy) return;
    setState(() => _pin = '');
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    PinPunchResult r;
    try {
      r = await AppScope.of(context).repo.pinPunch(_pin);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pin = '';
        _msg = friendlyError(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      if (r.ok) {
        _done = r;
        _msg = null;
      } else {
        _msg = r.message;
        if (r.locked) _startLock(r.lockedUntil);
      }
    });
    if (r.ok) {
      _back?.cancel();
      _back = Timer(PinPunchScreen.backAfter, _reset);
    }
  }

  /// 鎖定倒數：伺服器說鎖到幾點，換成這台手機的倒數（手機時間不準也不會超過 1 分鐘）
  void _startLock(DateTime? until) {
    var secs = until == null ? 60 : until.difference(DateTime.now()).inSeconds + 1;
    secs = secs.clamp(1, 60);
    _lockEnd = DateTime.now().add(Duration(seconds: secs));
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (!_locked) {
        t.cancel();
        setState(() {
          _lockEnd = null;
          _msg = null;
        });
      } else {
        setState(() {});
      }
    });
  }

  void _reset() {
    _back?.cancel();
    if (mounted) setState(() => _done = null);
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kiosk;
    if (k.error != null) {
      return _centered([
        Icon(Icons.lock_clock_outlined, size: 56, color: AppColors.muted),
        const SizedBox(height: 16),
        Text(k.error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: AppType.display, fontWeight: AppFont.heading)),
        const SizedBox(height: 8),
        Text('其他功能照常可以用（下方分頁）', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
      ]);
    }
    final done = _done;
    if (done != null) return _success(done);
    return _keypad(k);
  }

  Widget _centered(List<Widget> children) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      );

  Widget _success(PinPunchResult r) {
    final color = r.pending ? AppColors.warn : AppColors.good;
    final at = r.punchedAt;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _reset,
      child: _centered([
        Icon(r.pending ? Icons.error_outline : Icons.check_circle_outline, size: 64, color: color),
        const SizedBox(height: 12),
        Text(r.personName ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: AppType.hero, fontWeight: AppFont.heading)),
        const SizedBox(height: 4),
        Text(punchTypeLabel(r.punchType ?? 'in'),
            style: TextStyle(fontSize: AppType.display, fontWeight: AppFont.heading, color: color)),
        if (at != null)
          Text(DateFormat('HH:mm').format(toTaipei(at)),
              style: const TextStyle(fontSize: 72, fontWeight: AppFont.hero, fontFeatures: tabular)),
        Text('伺服器時間', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        if (r.pending) ...[
          const SizedBox(height: 12),
          Text(r.message.isNotEmpty ? r.message : '已記下，待店長確認：${r.flags.map(punchFlagLabel).join('、')}',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.warn)),
        ],
        const SizedBox(height: 24),
        Text('${PinPunchScreen.backAfter.inSeconds} 秒後回到鍵盤，點一下馬上回去',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      ]),
    );
  }

  Widget _keypad(KioskMine k) {
    final locked = _locked;
    final left = locked ? _lockEnd!.difference(DateTime.now()).inSeconds + 1 : 0;
    Widget key(String d) => _Key(onTap: locked || _busy ? null : () => _press(d), child: Text(d));
    return _centered([
      Text('${k.storeName}・打卡', style: const TextStyle(fontSize: AppType.display, fontWeight: AppFont.heading)),
      const SizedBox(height: 6),
      Text('輸入你的 4 位數打卡密碼', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 20),
      Semantics(
        label: '已輸入 ${_pin.length} 位',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length ? AppColors.primary : Colors.transparent,
                border: Border.all(color: i < _pin.length ? AppColors.primary : AppColors.muted, width: 1.5),
              ),
            ),
        ]),
      ),
      SizedBox(
        height: 64,
        child: Center(
          child: _busy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(
                  locked ? '密碼連錯 5 次，請 $left 秒後再試' : (_msg ?? ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.bad, fontSize: AppType.small),
                ),
        ),
      ),
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d)]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Key(onTap: locked || _busy ? null : _clear, child: const Text('清除', style: TextStyle(fontSize: AppType.title))),
        key('0'),
        _Key(
          onTap: locked || _busy ? null : _backspace,
          semanticLabel: '刪除一位',
          child: const Icon(Icons.backspace_outlined),
        ),
      ]),
      const SizedBox(height: 12),
      Text('還沒有打卡密碼的人，請找店長設定', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
    ]);
  }
}

/// 鍵盤的一個鍵：大顆、好按（吧台昏暗、手可能是濕的）
class _Key extends StatelessWidget {
  const _Key({required this.onTap, required this.child, this.semanticLabel});
  final VoidCallback? onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          width: 84,
          height: 68,
          child: Semantics(
            label: semanticLabel,
            button: true,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(fontSize: AppType.display, fontWeight: AppFont.figure, fontFeatures: tabular),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
              child: child,
            ),
          ),
        ),
      );
}

/// 設定／重設打卡密碼（老闆、店長在員工資料；員工在班表的打卡卡片改自己的）。
/// 密碼只存雜湊：設好之後誰都看不到；隨機產生的只在這次顯示。有改到回 true
Future<bool> editPunchPin(BuildContext context,
    {required String personId, required String name, required bool hasPin, bool canClear = false, bool self = false}) async {
  final repo = AppScope.of(context).repo;
  final c = TextEditingController();
  String? err, shown;
  var busy = false;
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (d) => StatefulBuilder(builder: (d, set) {
      Future<void> run(Future<String?> Function() action) async {
        set(() {
          busy = true;
          err = null;
        });
        try {
          final e = await action();
          if (!d.mounted) return;
          if (e != null) {
            set(() {
              busy = false;
              err = e;
            });
          } else if (shown == null) {
            Navigator.pop(d, true);
          } else {
            set(() => busy = false);
          }
        } catch (e) {
          if (d.mounted) {
            set(() {
              busy = false;
              err = friendlyError(e);
            });
          }
        }
      }

      Future<String?> save(String? pin) async {
        if (pin != null && !RegExp(r'^[0-9]{4}$').hasMatch(pin)) return '打卡密碼要是 4 位數字';
        final r = await repo.pinSet(personId, pin);
        if (!r.ok) return r.message;
        shown = r.pin; // 隨機產生的才有
        return null;
      }

      if (shown != null) {
        return AlertDialog(
          title: Text('新的打卡密碼・$name'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(shown!, style: const TextStyle(fontSize: AppType.hero, fontWeight: AppFont.heading, fontFeatures: tabular, letterSpacing: 8)),
            const SizedBox(height: 8),
            Text('只顯示這一次，關掉就看不到了。請記下來${self ? '' : '，再告訴本人'}。', textAlign: TextAlign.center),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('記下了'))],
        );
      }
      // 自己改只能隨機產生（ops 0112）：自己挑的話，「這組不能用」等於知道那是別人的密碼
      if (self) {
        return AlertDialog(
          title: Text('${hasPin ? '重設' : '設定'}打卡密碼・$name'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('自己改只能隨機產生一組 4 位數，不會跟店裡別人一樣。產生後只顯示一次，忘了就再產生一組。',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err!, style: TextStyle(color: AppColors.bad)),
            ],
          ]),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(d, false), child: const Text('取消')),
            FilledButton(onPressed: busy ? null : () => run(() => save(null)), child: const Text('隨機產生')),
          ],
        );
      }
      return AlertDialog(
        title: Text('${hasPin ? '重設' : '設定'}打卡密碼・$name'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('4 位數字，同一家店不能跟別人一樣。設好之後誰都看不到密碼，忘了就重設。',
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          TextField(
            controller: c,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: '新的打卡密碼', errorText: err, errorMaxLines: 3),
            onSubmitted: busy ? null : (_) => run(() => save(c.text.trim())),
          ),
        ]),
        actions: [
          if (canClear && hasPin)
            TextButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                          await repo.pinClear(personId);
                          return null;
                        }),
                child: const Text('清除密碼')),
          TextButton(onPressed: busy ? null : () => Navigator.pop(d, false), child: const Text('取消')),
          OutlinedButton(onPressed: busy ? null : () => run(() => save(null)), child: const Text('隨機產生')),
          FilledButton(onPressed: busy ? null : () => run(() => save(c.text.trim())), child: const Text('儲存')),
        ],
      );
    }),
  );
  // 不在這裡 dispose：對話框關閉動畫還會用到輸入框（跟其他對話框一樣交給回收）
  return changed ?? false;
}
