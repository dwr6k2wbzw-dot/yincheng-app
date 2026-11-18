import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';

/// 打卡用帳號的第一頁（ops 0112；0131 起只輸入自己的 4 位數密碼就打卡，不用點名字，同店密碼不會重複）。
/// 時間一律是伺服器時間；打卡成功大字顯示姓名、上班／下班、時間，4 秒後回到鍵盤。
/// 平板上公用帳號是滿版（老闆 2026-11-18），鍵盤跟字照螢幕大小放大。
class PinPunchScreen extends StatefulWidget {
  const PinPunchScreen({super.key, required this.kiosk});
  final KioskMine kiosk;
  static const backAfter = Duration(seconds: 4);

  /// 輸入到一半多久沒動作就清掉（免得下一個人接著別人輸入一半的密碼）
  static const idleClear = Duration(seconds: 30);
  @override
  State<PinPunchScreen> createState() => _PinPunchScreenState();
}

class _PinPunchScreenState extends State<PinPunchScreen> {
  String _pin = '';
  bool _busy = false;
  PinPunchResult? _done; // 打卡成功：大字顯示，時間到回鍵盤
  String? _msg; // 密碼不對、連不上
  DateTime? _lockEnd; // 連錯 5 次：這台手機的時間，倒數用
  bool _longLock = false; // 一小時內錯太多次：鎖到整點，顯示伺服器的「找店長補登」
  Timer? _back, _tick, _idle;

  @override
  void dispose() {
    _back?.cancel();
    _tick?.cancel();
    _idle?.cancel();
    super.dispose();
  }

  bool get _locked => _lockEnd != null && DateTime.now().isBefore(_lockEnd!);

  void _touch() {
    _idle?.cancel();
    if (_pin.isNotEmpty) {
      _idle = Timer(PinPunchScreen.idleClear, () {
        if (mounted && !_busy) setState(() => _pin = '');
      });
    }
  }

  void _press(String d) {
    if (_busy || _locked || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _msg = null;
    });
    _touch();
    if (_pin.length == 4) _submit();
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
    _touch();
  }

  void _clear() {
    if (_busy) return;
    setState(() => _pin = '');
    _touch();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    _idle?.cancel();
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
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kiosk;
    // 平板（滿版）上整體放大：寬 600 以下照手機尺寸，最多放大到 1.5 倍；高度不夠時不放大
    final size = MediaQuery.sizeOf(context);
    final scale = (size.width / 600).clamp(1.0, 1.5).toDouble();
    final fit = ((size.height - 160) / 620).clamp(0.85, 1.5).toDouble();
    final z = scale < fit ? scale : fit;
    if (k.error != null) {
      return _centered(z, [
        Icon(Icons.lock_clock_outlined, size: 56 * z, color: AppColors.muted),
        SizedBox(height: 16 * z),
        Text(k.error!, textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.display * z, fontWeight: AppFont.heading)),
        const SizedBox(height: 8),
        Text('其他功能照常可以用（下方分頁）', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
      ]);
    }
    final done = _done;
    return done != null ? _success(z, done) : _keypad(z, k);
  }

  Widget _centered(double z, List<Widget> children) => Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24 * z),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420 * z),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      );

  Widget _success(double z, PinPunchResult r) {
    final color = r.pending ? AppColors.warn : AppColors.good;
    final at = r.punchedAt;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _reset,
      child: _centered(z, [
        Icon(r.pending ? Icons.error_outline : Icons.check_circle_outline, size: 64 * z, color: color),
        SizedBox(height: 12 * z),
        Text(r.personName ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: AppType.hero * z, fontWeight: AppFont.heading)),
        SizedBox(height: 4 * z),
        Text(punchTypeLabel(r.punchType ?? 'in'),
            style: TextStyle(fontSize: AppType.display * z, fontWeight: AppFont.heading, color: color)),
        if (at != null)
          Text(DateFormat('HH:mm').format(toTaipei(at)),
              style: TextStyle(fontSize: 72 * z, fontWeight: AppFont.hero, fontFeatures: tabular)),
        Text('伺服器時間', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        if (r.pending) ...[
          SizedBox(height: 12 * z),
          Text(r.message.isNotEmpty ? r.message : '已記下，待店長確認：${r.flags.map(punchFlagLabel).join('、')}',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.warn)),
        ],
        SizedBox(height: 24 * z),
        Text('${PinPunchScreen.backAfter.inSeconds} 秒後回到打卡畫面，點一下馬上回去',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      ]),
    );
  }

  /// 輸入自己的密碼就打卡
  Widget _keypad(double z, KioskMine k) {
    final locked = _locked;
    final left = locked ? _lockEnd!.difference(DateTime.now()).inSeconds + 1 : 0;
    Widget key(String d) => _Key(z: z, onTap: locked || _busy ? null : () => _press(d), child: Text(d));
    return _centered(z, [
      Text('${k.storeName}・打卡', style: TextStyle(fontSize: AppType.display * z, fontWeight: AppFont.heading)),
      SizedBox(height: 6 * z),
      Text('輸入你的 4 位數打卡密碼', style: TextStyle(color: AppColors.muted, fontSize: AppType.body * z)),
      SizedBox(height: 20 * z),
      Semantics(
        label: '已輸入 ${_pin.length} 位',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 18 * z,
              height: 18 * z,
              margin: EdgeInsets.symmetric(horizontal: 10 * z),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length ? AppColors.primary : Colors.transparent,
                border: Border.all(color: i < _pin.length ? AppColors.primary : AppColors.muted, width: 1.5),
              ),
            ),
        ]),
      ),
      SizedBox(
        height: 64 * z,
        child: Center(
          child: _busy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(
                  locked && !_longLock ? '密碼連錯 5 次，請 $left 秒後再試' : (_msg ?? ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.bad, fontSize: AppType.small * z),
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
        _Key(z: z, onTap: locked || _busy ? null : _clear, child: Text('清除', style: TextStyle(fontSize: AppType.title * z))),
        key('0'),
        _Key(
          z: z,
          onTap: locked || _busy ? null : _backspace,
          semanticLabel: '刪除一位',
          child: Icon(Icons.backspace_outlined, size: 24 * z),
        ),
      ]),
      SizedBox(height: 16 * z),
      Text('還沒有打卡密碼：在自己的 App 班表頁設定\n忘記密碼請找店長重設',
          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: AppType.small * z)),
    ]);
  }
}

/// 鍵盤的一個鍵：大顆、好按（吧台昏暗、手可能是濕的）；z＝平板上放大的倍數
class _Key extends StatelessWidget {
  const _Key({required this.onTap, required this.child, this.semanticLabel, this.z = 1});
  final VoidCallback? onTap;
  final Widget child;
  final String? semanticLabel;
  final double z;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(6 * z),
        child: SizedBox(
          width: 84 * z,
          height: 68 * z,
          child: Semantics(
            label: semanticLabel,
            button: true,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                textStyle: TextStyle(fontSize: AppType.display * z, fontWeight: AppFont.figure, fontFeatures: tabular),
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
/// 同店不能跟別人一樣（ops 0131：打卡只輸入密碼，靠密碼認人；撞到時伺服器只回「這組密碼不能用」）。
/// 本人只能在還沒有密碼時自己設，之後由店長重設。
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
          if (isWeakPunchPin(pin)) return '不能相同或連號（如 1111、1234），請換一組';
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
              // 老闆 2026-11-18 指定的說明文字
              self ? '4 位數字，不能相同或連號（如 1111、1234）。忘記請找店長重設。' : '4 位數字，不能相同或連號（如 1111、1234）。',
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
