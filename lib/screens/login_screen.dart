import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/repository.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _signUp = false; // true：第一次使用，建立帳號

  Future<void> _submitSignUp() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showMessage(context, '請輸入 Email', error: true);
      return;
    }
    if (_password.text.length < 8) {
      showMessage(context, '密碼至少 8 個字', error: true);
      return;
    }
    if (_password.text != _password2.text) {
      showMessage(context, '兩次輸入的密碼不一樣', error: true);
      return;
    }
    if (code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length != 10) {
      showMessage(context, '請輸入老闆給你的 10 碼邀請碼', error: true);
      return;
    }
    final repo = AppScope.of(context).repo;
    setState(() => _busy = true);
    try {
      try {
        (await SharedPreferences.getInstance()).setString(AppState.pendingCodeKey, code.toUpperCase());
      } catch (_) {}
      final signedIn = await repo.signUp(email, _password.text);
      if (!signedIn && mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('請到信箱確認'),
            content: Text('確認信已寄到 $email。\n請點信裡的連結，再回到這裡用剛剛的 Email 和密碼登入，就會自動加入店家。'),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('知道了'))],
          ),
        );
        if (mounted) setState(() => _signUp = false);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      showMessage(context, '請輸入帳號與密碼', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await AppScope.of(context).repo.signIn(_email.text, _password.text);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.local_bar_rounded, size: 56, color: AppColors.primary),
                  const SizedBox(height: 12),
                  const Text('小城外', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                      AppConfig.demo
                          ? '示範模式：任意帳密即可登入（帳號含 staff 以員工身分登入）'
                          : _signUp
                              ? '第一次使用：用你的 Email 建立帳號，並輸入老闆給你的邀請碼'
                              : '以店家提供的帳號登入',
                      textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _signUp ? null : _submit(),
                    decoration: InputDecoration(
                        labelText: _signUp ? '設定密碼（至少 8 個字）' : '密碼', prefixIcon: const Icon(Icons.lock_outline)),
                  ),
                  if (_signUp) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password2,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '再輸入一次密碼', prefixIcon: Icon(Icons.lock_outline)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: '邀請碼', hintText: 'XXXXX-XXXXX', prefixIcon: Icon(Icons.key_outlined)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : (_signUp ? _submitSignUp : _submit),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_signUp ? '建立帳號並加入' : '登入', style: const TextStyle(fontSize: 16)),
                  ),
                  if (!AppConfig.demo) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                      child: Text(_signUp ? '已經有帳號？回到登入' : '第一次使用？用邀請碼建立帳號'),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
}
