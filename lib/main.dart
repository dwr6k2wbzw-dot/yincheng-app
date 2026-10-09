import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'config.dart';
import 'data/demo_repository.dart';
import 'data/repository.dart';
import 'data/supabase_repository.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

/// 啟動進度（顯示在網頁的錯誤畫面上，方便診斷）
@JS('ycStage')
external set _ycStage(String v);

Future<void> main() async {
  _ycStage = 'Dart 已啟動';
  WidgetsFlutterBinding.ensureInitialized();
  // 畫面元件出錯時顯示錯誤文字（預設是一片灰），方便截圖回報
  ErrorWidget.builder = (d) => Material(
        color: AppColors.bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('畫面發生錯誤（請截圖給 Claude）\n\n${d.exceptionAsString()}',
                style: const TextStyle(color: AppColors.bad, fontSize: 14)),
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
    _ycStage = 'Supabase 完成，開始畫畫面';
    runApp(YinchengApp(state: AppState(repo)));
  } catch (e) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('啟動失敗（請截圖給 Claude）\n\n$e', style: const TextStyle(color: AppColors.bad, fontSize: 14)),
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
        child: MaterialApp(
          title: '小城外',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          locale: const Locale('zh', 'TW'),
          supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AuthGate(),
        ),
      );
}

/// 依登入狀態切換：未登入 → 登入頁；已登入 → 主畫面
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _signedIn;

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
  Widget build(BuildContext context) => (_signedIn ?? false) ? const HomeShell() : const LoginScreen();
}
