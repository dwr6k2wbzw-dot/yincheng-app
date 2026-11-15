import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../theme.dart';

/// 這台打卡機的代號、密語（「出勤管理 → 打卡機」設定時存下）
const kioskIdPref = 'attendance_kiosk_id';
const kioskSecretPref = 'attendance_kiosk_secret';

/// 打卡機畫面（不用登入）：每 30 秒向伺服器拿一個新碼，畫成 QR；員工用自己的手機掃。
/// 碼由伺服器產生、伺服器驗證；這台只存打卡機代號和密語（在「出勤管理 → 打卡機」設定）。
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});
  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  String? _id, _secret;
  KioskCode? _code;
  Duration _offset = Duration.zero; // 伺服器時間 − 這台時間
  String? _error;
  bool _loading = false, _noSetup = false;
  bool _halted = false; // 密鑰錯、嘗試太多次：不自動重試（重試會一直累積失敗次數），等人按「重試」
  Timer? _tick;

  Repository get _repo => AppScope.of(context).repo;
  DateTime get _serverNow => DateTime.now().toUtc().add(_offset);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // 打卡機一律不留登入：老闆、店長設定完、或有人直接開 #/kiosk，都先登出，
    // 這台放在吧台誰都碰得到，按返回、重新整理只會回到登入頁，進不了管理後台。
    if (_repo.isSignedIn) {
      try {
        await _repo.signOut();
      } catch (_) {}
    }
    _id = prefs.getString(kioskIdPref);
    _secret = prefs.getString(kioskSecretPref);
    if (_id == null || _secret == null) {
      if (mounted) setState(() => _noSetup = true);
      return;
    }
    await _fetch();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final c = _code;
      // 碼到期就換；拿不到（斷線）時每 5 秒重試
      if (!_loading && !_halted && (c == null ? DateTime.now().second % 5 == 0 : !_serverNow.isBefore(c.validUntil))) {
        _fetch();
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _fetch() async {
    _loading = true;
    final sent = DateTime.now().toUtc();
    try {
      final c = await _repo.kioskCode(_id!, _secret!);
      final back = DateTime.now().toUtc();
      // 用來回時間的中點估伺服器時差
      _offset = c.serverTime.difference(sent.add(back.difference(sent) ~/ 2));
      if (mounted) {
        setState(() {
          _code = c;
          _error = null;
        });
      }
    } on KioskCodeError catch (e) {
      if (mounted) {
        setState(() {
          _code = null;
          _halted = true;
          _error = '!${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _code = null;
          _error = friendlyError(e);
        });
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _code;
    final left = c == null ? 0 : c.validUntil.difference(_serverNow).inSeconds.clamp(0, 30);
    final base = '${Uri.base.origin}${Uri.base.path}';
    final side = (MediaQuery.sizeOf(context).shortestSide * 0.62).clamp(200.0, 520.0);
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_noSetup) ...[
                  const Text('這台還沒設成打卡機', style: TextStyle(fontSize: AppType.heading, fontWeight: AppFont.heading)),
                  const SizedBox(height: 8),
                  Text('請老闆或店長登入後，到「班表 → 出勤管理 → 打卡機」按「把這台設成打卡機」。',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ] else ...[
                  Text(c?.storeName ?? '　', style: const TextStyle(fontSize: AppType.hero, fontWeight: AppFont.hero)),
                  const SizedBox(height: 4),
                  Text('掃碼打卡', style: TextStyle(fontSize: AppType.title, color: AppColors.muted)),
                  const SizedBox(height: 20),
                  Container(
                    width: side,
                    height: side,
                    color: Colors.white,
                    alignment: Alignment.center,
                    child: c == null
                        ? const CircularProgressIndicator(color: Colors.black54)
                        : QrImageView(
                            data: PunchLink(_id!, c.window, c.code).toUrl(base),
                            size: side,
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.all(16),
                            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                          ),
                  ),
                  const SizedBox(height: 16),
                  if (c != null)
                    Text('$left 秒後換碼・${c.kioskName}',
                        style: TextStyle(color: AppColors.muted, fontSize: AppType.small, fontFeatures: tabular)),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!.startsWith('!') ? _error!.substring(1) : '連不上伺服器，重試中：$_error', textAlign: TextAlign.center, style: TextStyle(color: AppColors.bad)),
                    if (_halted)
                      TextButton(
                          onPressed: () {
                            setState(() => _halted = false);
                            _fetch();
                          },
                          child: const Text('重試')),
                  ],
                  const SizedBox(height: 8),
                  Text('用手機相機掃，或在 App「班表」按「掃碼打卡」', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                ],
              ]),
            ),
          ),
          // 離開打卡機＝回登入頁（已經登出，要重新登入才進得了後台）
          Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                  tooltip: '離開打卡機（回登入頁）',
                  onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
                  icon: const Icon(Icons.close))),
        ]),
      ),
    );
  }
}
