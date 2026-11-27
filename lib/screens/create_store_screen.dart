import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../data/shift_templates.dart';
import '../data/signup.dart';
import '../theme.dart';
import 'shift_template_picker.dart';

/// 自助註冊第二步（公版，ops 0119）：登入了、還沒有任何店 → 幫自己的店取名字。
/// 建好之後自己就是這家店的老闆；功能之後一樣一樣開。
/// ops 0152：同一頁選店的類型，排班先帶入那一類店常見的人力、班別（之後在排班條件裡改）。
class CreateStoreView extends StatefulWidget {
  const CreateStoreView({super.key, required this.onEnterCode});
  final VoidCallback onEnterCode;
  @override
  State<CreateStoreView> createState() => _CreateStoreViewState();
}

class _CreateStoreViewState extends State<CreateStoreView> {
  final _store = TextEditingController();
  final _me = TextEditingController();
  bool _busy = false;
  String _kind = defaultShiftTemplate;
  String? _storeErr, _meErr, _err;

  @override
  void dispose() {
    _store.dispose();
    _me.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final se = signupNameError(_store.text, '店名');
    final me = signupNameError(_me.text, '你的名字');
    setState(() {
      _storeErr = se;
      _meErr = me;
      _err = null;
    });
    if (se != null || me != null) return;
    final state = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await state.repo.signupCreateStore(_store.text.trim(), _me.text.trim(), kind: _kind);
      await state.loadMemberships();
    } catch (e) {
      final raw = e.toString();
      final msg = friendlyError(e);
      if (!mounted) return;
      setState(() {
        // 店名的問題標在店名那一格，其他的放在按鈕上面
        if (raw.contains('SIGNUP_TAKEN')) {
          _storeErr = msg;
        } else {
          _err = msg;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.storefront_outlined, color: AppColors.primary, size: 44),
              const SizedBox(height: 16),
              const Text('幫你的店取個名字', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('建好之後你就是這家店的老闆，可以再邀同事進來。', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 28),
              TextField(
                controller: _store,
                autofocus: true,
                enabled: !_busy,
                maxLength: 40,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _storeErr == null ? null : setState(() => _storeErr = null),
                decoration: InputDecoration(
                    labelText: '店名', hintText: '例如：巷口小酒館', counterText: '',
                    prefixIcon: const Icon(Icons.storefront_outlined), errorText: _storeErr, errorMaxLines: 3),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _me,
                enabled: !_busy,
                maxLength: 40,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _submit(),
                onChanged: (_) => _meErr == null ? null : setState(() => _meErr = null),
                decoration: InputDecoration(
                    labelText: '你的名字', hintText: '同事會看到的稱呼', counterText: '',
                    prefixIcon: const Icon(Icons.person_outline), errorText: _meErr, errorMaxLines: 3),
              ),
              const SizedBox(height: 28),
              const Text('你的店比較像哪一種？', style: TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
              const SizedBox(height: 4),
              Text('排班會先帶入這類店常見的人數和班別，之後隨時可以改。', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              const SizedBox(height: 12),
              ShiftTemplatePicker(selected: _kind, enabled: !_busy, onChanged: (k) => setState(() => _kind = k)),
              if (_err != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.error_outline, color: AppColors.bad, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_err!, style: TextStyle(color: AppColors.bad))),
                  ]),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('建立我的店', style: TextStyle(fontSize: AppType.title)),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _busy ? null : widget.onEnterCode,
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('我是員工，老闆有給我邀請碼'),
              ),
              TextButton(
                onPressed: _busy ? null : state.repo.signOut,
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: AppColors.muted),
                child: const Text('登出'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
