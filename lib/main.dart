import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'config.dart';
import 'data/demo_repository.dart';
import 'data/repository.dart';
import 'data/row_cache.dart';
import 'data/supabase_repository.dart';
import 'screens/attendance_screen.dart';
import 'screens/home_shell.dart';
import 'screens/kiosk_screen.dart';
import 'screens/login_screen.dart';
import 'services/load_timing.dart';
import 'services/missed_punch.dart';
import 'theme.dart';
import 'widgets/content_width_limit.dart';

/// 啟動進度（顯示在網頁的錯誤畫面上，方便診斷）
@JS('ycStage')
external set _ycStage(String v);

Future<void> main() async {
  _ycStage = 'Dart 已啟動';
  markLoad('程式下載完、開始執行');
  WidgetsFlutterBinding.ensureInitialized();
  // 畫面元件出錯時顯示錯誤文字（預設是一片灰），方便截圖回報
  ErrorWidget.builder = (d) => Material(
        color: AppColors.bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('畫面發生錯誤（請截圖回報後臺）\n\n${d.exceptionAsString()}',
                style: TextStyle(color: AppColors.bad, fontSize: AppType.body)),
          ),
        ),
      );
  try {
    await initializeDateFormatting('zh_TW');
    _ycStage = '日期格式完成，連線 Supabase 中';
    final Repository repo;
    if (AppConfig.demo) {
      repo = DemoRepository();
    } else {
      await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseKey)
          .timeout(const Duration(seconds: 20));
      repo = SupabaseRepository();
    }
    await RowCache.load(); // 上次讀到的資料（先顯示、背景更新）
    _ycStage = 'Supabase 完成，開始畫畫面';
    markLoad('連上資料庫');
    // 員工用手機相機掃打卡機的 QR → 開 App 網址 #/punch?…：登入後自動打卡
    pendingPunch = PunchLink.parse(Uri.base.toString());
    if (pendingPunch != null && !repo.isSignedIn) {
      try {
        await markPunchStarted(); // 如果他去收信再登入，這次會沒打到：登入後要提醒重掃
      } catch (_) {}
    }
    runApp(YinchengApp(state: AppState(repo)));
  } catch (e) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('啟動失敗（請截圖回報後臺）\n\n$e', style: TextStyle(color: AppColors.bad, fontSize: AppType.body)),
          ),
        ),
      ),
    ));
  }
}

class YinchengApp extends StatelessWidget {
  const YinchengApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        // 每家店一套配色（老闆 2026-10-14）：切換店家時換顏色
        child: ListenableBuilder(listenable: state, builder: (context, _) {
          final palette = StorePalette.forStore(state.current?.storeName);
          AppColors.p = palette;
          return MaterialApp(
          title: '小城外',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(palette),
          builder: (context, child) => ContentWidthLimit(child: child!),
          locale: const Locale('zh', 'TW'),
          supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // #/kiosk＝打卡機畫面（不用登入，重新整理也留在打卡機）；其他網址（含 #/punch?…）都回主畫面
          // （有 onGenerateInitialRoutes 就不能再給 home，'/' 由 onGenerateRoute 產生）
          onGenerateInitialRoutes: (name) => [_route(name.startsWith('/kiosk') ? '/kiosk' : '/')],
          onGenerateRoute: appRoute,
        );
        }),
      );
}

Route<void>? appRoute(RouteSettings s) => s.name == '/kiosk' || s.name == '/' ? _route(s.name!) : null;

Route<void> _route(String name) => MaterialPageRoute(
    settings: RouteSettings(name: name), builder: (_) => name == '/kiosk' ? const KioskScreen() : const AuthGate());

/// 依登入狀態切換：未登入 → 登入頁；已登入 → 主畫面
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _signedIn;
  bool _missedChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_signedIn != null) return;
    final state = AppScope.of(context);
    _signedIn = state.repo.isSignedIn;
    if (_signedIn!) state.loadMemberships();
    state.repo.signedInChanges.listen((v) {
      if (!mounted || v == _signedIn) return;
      setState(() => _signedIn = v);
      if (v) {
        state.loadMemberships();
      } else {
        state.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final link = pendingPunch;
    if ((_signedIn ?? false) && link != null) {
      pendingPunch = null;
      _missedChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await clearPunchStarted();
        } catch (_) {}
        if (mounted) punchAndShow(context, link);
      });
    } else if ((_signedIn ?? false) && !_missedChecked) {
      // 掃碼後去收信再登入（新頁面沒有那次的碼）：明確說沒打到
      _missedChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final missed = await takeMissedPunch().catchError((_) => false);
        if (missed && mounted) showMissedPunch(context);
      });
    }
    return (_signedIn ?? false) ? const HomeShell() : const LoginScreen();
  }
}
