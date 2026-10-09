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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_TW');
  final Repository repo;
  if (AppConfig.demo) {
    repo = DemoRepository();
  } else {
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseKey);
    repo = SupabaseRepository();
  }
  runApp(YinchengApp(state: AppState(repo)));
}

class YinchengApp extends StatelessWidget {
  const YinchengApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: '隱城營運',
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
