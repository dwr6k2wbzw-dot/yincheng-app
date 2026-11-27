import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// AI 設定（ops 0157，公版；只有老闆）：接上自己的 Claude／OpenAI／Gemini。
/// 金鑰先實際測過才存，存進加密保管庫；之後畫面上只看得到末 4 碼。
/// 接了之後，訂位助理、排班助理、送貨單辨識、班表照片辨識都改用店家的 AI，不受平台每天次數限制。
class StoreAiScreen extends StatefulWidget {
  const StoreAiScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<StoreAiScreen> createState() => _StoreAiScreenState();
}

class _StoreAiScreenState extends State<StoreAiScreen> {
  StoreAiSetting? _current;
  bool _loaded = false;
  String? _loadError;
  bool _started = false;

  StoreAiProvider _provider = StoreAiProvider.anthropic;
  final _model = TextEditingController(
    text: storeAiProviders.first.models.first,
  );
  final _key = TextEditingController();
  bool _showKey = false;
  bool _busy = false;
  String? _formError;
  String? _testNote; // 測試已存金鑰的結果

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

  @override
  void dispose() {
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.storeAiSetting(_store);
      if (!mounted) return;
      setState(() {
        _current = s;
        _loaded = true;
        _loadError = null;
        if (s != null) {
          _provider = s.provider;
          _model.text = s.model;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = friendlyError(e));
    }
  }

  void _pickProvider(StoreAiProvider p) {
    if (p == _provider) return;
    setState(() {
      _provider = p;
      _model.text = storeAiInfo(p).models.first;
      _formError = null;
    });
  }

  Future<void> _save() async {
    final problem =
        storeAiModelProblem(_model.text) ?? storeAiKeyProblem(_key.text);
    if (problem != null) {
      setState(() => _formError = problem);
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    // 斷線等例外也要放開按鈕、把原因顯示在表單上（Codex P2：原本會一直卡在處理中）
    try {
      final r = await _repo.saveStoreAi(
        _store,
        _provider,
        _model.text,
        _key.text,
      );
      if (!mounted) return;
      if (!r.ok) {
        setState(() => _formError = r.error);
        return;
      }
      _key.clear();
      setState(() {
        _showKey = false;
        _testNote = null;
      });
    } catch (e) {
      if (mounted) setState(() => _formError = friendlyError(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) {
      showMessage(context, '測試成功，已經改用你自己的 ${storeAiInfo(_provider).label}');
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _testNote = null;
    });
    var ok = false;
    try {
      final r = await _repo.testStoreAi(_store);
      if (!mounted) return;
      ok = r.ok;
      setState(() => _testNote = r.ok ? null : r.error);
    } catch (e) {
      if (mounted) setState(() => _testNote = friendlyError(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted && ok) showMessage(context, '連線正常');
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('改回平台內建的 AI？'),
        content: const Text('存著的金鑰會刪掉。之後 AI 功能改用平台的，每天有次數限制。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('刪掉金鑰'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _repo.clearStoreAi(_store);
      if (!mounted) return;
      setState(() => _testNote = null);
    } catch (e) {
      if (mounted) {
        setState(() => _testNote = friendlyError(e));
        showMessage(context, friendlyError(e), error: true);
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) showMessage(context, '已經改回平台內建的 AI');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 設定')),
      body: !_loaded
          ? (_loadError != null
                ? ErrorView(message: _loadError!, onRetry: _load)
                : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _StatusCard(
                  current: _current,
                  busy: _busy,
                  testNote: _testNote,
                  onTest: _test,
                  onClear: _clear,
                ),
                const SizedBox(height: 12),
                _form(),
              ],
            ),
    );
  }

  Widget _form() {
    final info = storeAiInfo(_provider);
    final replacing = _current != null;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replacing ? '換一把金鑰' : '接上你自己的 AI',
            style: const TextStyle(
              fontSize: AppType.title,
              fontWeight: AppFont.heading,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '接上之後，訂位助理、排班助理、送貨單辨識、班表照片辨識都改用你的 AI，'
            '費用算在你自己的 AI 帳上；沒設定就用平台內建的 AI（有每天次數）。',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: AppType.small,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '哪一家',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<StoreAiProvider>(
              showSelectedIcon: false,
              segments: [
                for (final p in storeAiProviders)
                  ButtonSegment(value: p.provider, label: Text(p.label)),
              ],
              selected: {_provider},
              onSelectionChanged: _busy ? null : (s) => _pickProvider(s.first),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _model,
            enabled: !_busy,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '模型'),
            onChanged: (_) => setState(() => _formError = null),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in info.models)
                SelectChip(
                  label: Text(m),
                  selected: _model.text.trim() == m,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _model.text = m),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '要選看得懂照片的模型（送貨單、班表照片辨識會傳照片）。',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: AppType.caption,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _key,
            enabled: !_busy,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            autofillHints: const <String>[],
            decoration: InputDecoration(
              labelText: 'API 金鑰',
              hintText: info.keyHint,
              suffixIcon: IconButton(
                tooltip: _showKey ? '遮住金鑰' : '顯示金鑰',
                icon: Icon(
                  _showKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
            onChanged: (_) => setState(() => _formError = null),
          ),
          const SizedBox(height: 6),
          Text(
            '${info.whereToGet}。存好之後這裡只會顯示最後 4 碼，誰都看不到完整的金鑰。',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: AppType.caption,
              height: 1.5,
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 14),
            _ErrorLine(text: _formError!),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('測試並儲存'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '會先用這把金鑰問 AI 一句話，成功才存。',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: AppType.caption,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.current,
    required this.busy,
    required this.testNote,
    required this.onTest,
    required this.onClear,
  });
  final StoreAiSetting? current;
  final bool busy;
  final String? testNote;
  final VoidCallback onTest;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = current;
    if (c == null) {
      return SectionCard(
        child: Row(
          children: [
            Icon(Icons.auto_awesome_outlined, color: AppColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '目前用平台內建的 AI',
                    style: TextStyle(
                      fontSize: AppType.title,
                      fontWeight: AppFont.heading,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '每個 AI 功能每天有次數限制。',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: AppType.small,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final info = storeAiInfo(c.provider);
    final error = testNote ?? c.lastError;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                error == null
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: error == null ? AppColors.good : AppColors.bad,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '目前用你自己的 ${info.label}',
                  style: const TextStyle(
                    fontSize: AppType.title,
                    fontWeight: AppFont.heading,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _kv('模型', c.model),
          _kv('金鑰', '•••• ${c.keyLast4}'),
          _kv(
            '上次驗證',
            c.verifiedAt == null
                ? '還沒驗證'
                : DateFormat('M/d HH:mm').format(toTaipei(c.verifiedAt!)),
          ),
          _kv('每天次數', '不限（費用算在你的 ${info.label} 帳上）'),
          if (error != null) ...[
            const SizedBox(height: 10),
            _ErrorLine(text: error),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onTest,
                    icon: const Icon(Icons.wifi_tethering, size: 18),
                    label: const Text('測試連線'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextButton(
                    onPressed: busy ? null : onClear,
                    child: Text(
                      '改回平台的 AI',
                      style: TextStyle(color: AppColors.bad),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            k,
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
          ),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontSize: AppType.small)),
        ),
      ],
    ),
  );
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.bad.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: AppColors.bad),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.bad,
              fontSize: AppType.small,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
