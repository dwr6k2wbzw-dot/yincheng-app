import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';

/// 打卡用帳號的第一頁（ops 0112、0125）：先點自己的名字，再輸入自己的 4 位數密碼。
/// 時間一律是伺服器時間；打卡成功大字顯示姓名、上班／下班、時間，4 秒後回到名單。
class PinPunchScreen extends StatefulWidget {
  const PinPunchScreen({super.key, required this.kiosk});
  final KioskMine kiosk;
  static const backAfter = Duration(seconds: 4);

  /// 點了名字之後多久沒動作就回到名單（免得下一個人在別人的名字下面輸入）
  static const idleBack = Duration(seconds: 30);
  @override
  State<PinPunchScreen> createState() => _PinPunchScreenState();
}

class _PinPunchScreenState extends State<PinPunchScreen> {
  List<KioskPerson>? _people;
  String? _loadError;
  KioskPerson? _who; // 點了誰的名字
  String _pin = '';
  bool _busy = false;
  PinPunchResult? _done; // 打卡成功：大字顯示，時間到回名單
  String? _msg; // 密碼不對、連不上
  DateTime? _lockEnd; // 連錯 5 次：這台手機的時間，倒數用
  bool _longLock = false; // 一小時內錯太多次：鎖到整點，顯示伺服器的「找店長補登」
  Timer? _back, _tick, _idle;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (widget.kiosk.error == null) _loadPeople();
    }
  }

  @override
  void dispose() {
    _back?.cancel();
    _tick?.cancel();
    _idle?.cancel();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    try {
      final p = await AppScope.of(context).repo.kioskPeople();
      if (mounted) {
        setState(() {
          _people = p;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = friendlyError(e));
    }
  }

  bool get _locked => _lockEnd != null && DateTime.now().isBefore(_lockEnd!);

  void _touch() {
    _idle?.cancel();
    if (_who != null) _idle = Timer(PinPunchScreen.idleBack, _toNames);
  }

  Future<void> _pick(KioskPerson p) async {
    if (!p.hasPin) {
      // 名單是剛打開時讀的：他可能剛剛才在自己的 App 設好密碼（Codex P2），先重新讀一次再決定
      await _loadPeople();
      if (!mounted) return;
      final now = _people?.where((x) => x.personId == p.personId).firstOrNull;
      if (now == null || !now.hasPin) {
        setState(() => _msg = '「${p.name}」還沒有打卡密碼：請在自己的 App 班表頁設定，或找店長幫你設');
        return;
      }
      p = now;
    }
    setState(() {
      _who = p;
      _pin = '';
      _msg = null;
    });
    _touch();
  }

  void _toNames() {
    _idle?.cancel();
    if (!mounted || _busy) return;
    setState(() {
      _who = null;
      _pin = '';
      if (!_locked) _msg = null;
    });
  }

  void _press(String d) {
    if (_busy || _locked || _pin.length >= 4) return;
    _touch();
    setState(() {
      _pin += d;
      _msg = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    _touch();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _clear() {
    if (_busy) return;
    _touch();
    setState(() => _pin = '');
  }

  Future<void> _submit() async {
    final who = _who;
    if (who == null) return;
    setState(() => _busy = true);
    PinPunchResult r;
    try {
      r = await AppScope.of(context).repo.pinPunch(who.personId, _pin);
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
        _who = null;
        _msg = null;
      } else {
        _msg = r.message;
        if (r.locked) _startLock(r.lockedUntil);
        if (r.result == 'no_pin') _who = null; // 密碼剛被清掉：回名單
      }
    });
    if (r.ok) {
      _idle?.cancel();
      _back?.cancel();
      _back = Timer(PinPunchScreen.backAfter, _reset);
    } else {
      _touch();
      if (r.result == 'no_pin') _loadPeople();
    }
  }

  /// 鎖定倒數：伺服器說鎖到幾點，換成這台手機的倒數（手機時間不準也不會超過 1 小時；提早解開的話伺服器照樣擋）
  void _startLock(DateTime? until) {
    var secs = until == null ? 60 : until.difference(DateTime.now()).inSeconds + 1;
    secs = secs.clamp(1, 3600);
    _longLock = secs > 60;
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
    _loadPeople(); // 名單可能變了（新的人、剛設好密碼）
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
    final who = _who;
    return who == null ? _names(k) : _keypad(k, who);
  }

  Widget _centered(List<Widget> children, {double maxWidth = 380}) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
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
        Text('${PinPunchScreen.backAfter.inSeconds} 秒後回到名單，點一下馬上回去',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      ]),
    );
  }

  /// 第一步：點自己的名字
  Widget _names(KioskMine k) {
    final people = _people;
    return _centered(maxWidth: 560, [
      Text('${k.storeName}・打卡', style: const TextStyle(fontSize: AppType.display, fontWeight: AppFont.heading)),
      const SizedBox(height: 6),
      Text('先點你的名字，再輸入 4 位數打卡密碼', style: TextStyle(color: AppColors.muted)),
      SizedBox(
        height: 48,
        child: Center(
          child: Text(
              _locked && !_longLock ? '密碼連錯 5 次，請 ${_lockEnd!.difference(DateTime.now()).inSeconds + 1} 秒後再試' : (_msg ?? ''),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.bad, fontSize: AppType.small)),
        ),
      ),
      if (_loadError != null) ...[
        Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.bad)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _loadPeople, child: const Text('再試一次')),
      ] else if (people == null)
        const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())
      else if (people.isEmpty)
        Text('班表上還沒有人，請店長到「班表人員」新增', style: TextStyle(color: AppColors.muted))
      else
        Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
          for (final p in people)
            SizedBox(
              width: 164,
              height: 64,
              child: OutlinedButton(
                onPressed: _locked ? null : () => _pick(p),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: p.hasPin ? null : AppColors.muted,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
                  if (!p.hasPin) Text('還沒設密碼', style: TextStyle(fontSize: AppType.caption, color: AppColors.muted)),
                ]),
              ),
            ),
        ]),
      const SizedBox(height: 16),
      Text('還沒有打卡密碼的人：在自己的 App 班表頁設定。忘記密碼請找店長重設',
          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
    ]);
  }

  /// 第二步：輸入密碼
  Widget _keypad(KioskMine k, KioskPerson who) {
    final locked = _locked;
    final left = locked ? _lockEnd!.difference(DateTime.now()).inSeconds + 1 : 0;
    Widget key(String d) => _Key(onTap: locked || _busy ? null : () => _press(d), child: Text(d));
    return _centered([
      Text(who.name,
          textAlign: TextAlign.center, style: const TextStyle(fontSize: AppType.display, fontWeight: AppFont.heading)),
      const SizedBox(height: 2),
      TextButton.icon(
          onPressed: _busy ? null : _toNames, icon: const Icon(Icons.arrow_back, size: 18), label: const Text('不是我，換人')),
      Text('輸入你的 4 位數打卡密碼', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 16),
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
                  locked && !_longLock ? '密碼連錯 5 次，請 $left 秒後再試' : (_msg ?? ''),
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
      Text('忘記密碼請找店長重設', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
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

/// 設定／重設打卡密碼（老闆、店長在員工資料；員工在班表的打卡卡片設自己的）。
/// 自己輸入要打兩次確認，也可以隨機產生。規則（4 位數、不能太好猜）在輸入的地方就寫出來；
/// 不用跟別人不一樣（ops 0125：打卡先點名字再輸入密碼）。本人只能在還沒有密碼時自己設，之後由店長重設。
/// 密碼只存雜湊：設好之後誰都看不到；隨機產生的只在這次顯示。有改到回 true
Future<bool> editPunchPin(BuildContext context,
    {required String personId, required String name, required bool hasPin, bool canClear = false, bool self = false}) async {
  final repo = AppScope.of(context).repo;
  final c = TextEditingController();
  final c2 = TextEditingController();
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
        if (pin != null) {
          if (!RegExp(r'^[0-9]{4}$').hasMatch(pin)) return '打卡密碼要是 4 位數字';
          if (pin != c2.text.trim()) return '兩次輸入的不一樣，請再輸入一次';
          if (isWeakPunchPin(pin)) return '四個相同數字或連號（像 1111、1234、4321）太好猜，請換一組';
        }
        final r = await repo.pinSet(personId, pin);
        if (!r.ok) return r.message;
        shown = r.pin; // 隨機產生的才有
        return null;
      }

      if (shown != null) {
        return AlertDialog(
          scrollable: true,
          title: Text('新的打卡密碼・$name'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(shown!, style: const TextStyle(fontSize: AppType.hero, fontWeight: AppFont.heading, fontFeatures: tabular, letterSpacing: 8)),
            const SizedBox(height: 8),
            Text('只顯示這一次，關掉就看不到了。請記下來${self ? '' : '，再告訴本人'}。', textAlign: TextAlign.center),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('記下了'))],
        );
      }
      void submit() => run(() => save(c.text.trim()));
      // 手機鍵盤跳出來時空間不夠，整個對話框要能捲（程式審查 P2：390×780、鍵盤 300 會超出）
      return AlertDialog(
        scrollable: true,
        title: Text('${hasPin ? '重設' : '設定'}打卡密碼・$name'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              self
                  ? '規則：4 位數字；不能四個數字都一樣，也不能是連號（像 1111、1234、4321）。'
                      '設好之後誰都看不到；之後忘記或想換，請找店長重設。不想自己想可以按「隨機產生」。'
                  : '規則：4 位數字；不能四個數字都一樣，也不能是連號（像 1111、1234、4321）。'
                      '設好之後誰都看不到密碼；員工忘記了，由店長在這裡重設。',
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          TextField(
            controller: c,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '新的打卡密碼'),
          ),
          TextField(
            controller: c2,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: '再輸入一次', errorText: err, errorMaxLines: 3),
            onSubmitted: busy ? null : (_) => submit(),
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
          FilledButton(onPressed: busy ? null : submit, child: const Text('儲存')),
        ],
      );
    }),
  );
  // 不在這裡 dispose：對話框關閉動畫還會用到輸入框（跟其他對話框一樣交給回收）
  return changed ?? false;
}
