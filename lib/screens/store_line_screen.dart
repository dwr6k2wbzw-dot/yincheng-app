import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/clock.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/line_bind_dialog.dart';

/// 接上自己的 LINE 官方帳號（ops 0160，公版；只有老闆）。
/// channel secret、access token 先用 LINE 驗證過才存，存進加密保管庫；之後畫面上只看得到末 4 碼。
/// 接上之後，透過這個官方帳號綁的群組，重要交接用你的帳號發（則數算你的）；群組裡 @機器人 也用這個帳號回覆。
class StoreLineScreen extends StatefulWidget {
  const StoreLineScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<StoreLineScreen> createState() => _StoreLineScreenState();
}

class _StoreLineScreenState extends State<StoreLineScreen> {
  StoreLineStatus? _status;
  String? _loadError;
  bool _started = false;

  final _secret = TextEditingController();
  final _token = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _formError;
  String? _note; // 驗證已存金鑰的結果

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
    _secret.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.storeLineStatus(_store);
      if (mounted) {
        setState(() {
          _status = s;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = friendlyError(e));
    }
  }

  Future<void> _save() async {
    final problem = storeLineSecretProblem(_secret.text) ??
        storeLineTokenProblem(_token.text);
    if (problem != null) {
      setState(() => _formError = problem);
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    StoreLineResult r;
    try {
      r = await _repo.saveStoreLine(_store, _secret.text, _token.text);
    } catch (e) {
      if (mounted) setState(() => _formError = friendlyError(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _formError = r.error);
      return;
    }
    _secret.clear();
    _token.clear();
    setState(() {
      _show = false;
      _note = null;
    });
    await _load();
    if (!mounted) return;
    if (r.verified) {
      showMessage(context, '接上了！下一步把官方帳號拉進工作群組、產生綁定代碼');
    } else {
      await _afterSaveDialog(r);
    }
  }

  // 存好了但還有事要處理（Webhook 沒填好、Use webhook 沒開、secret 不對）
  Future<void> _afterSaveDialog(StoreLineResult r) async {
    final url = r.webhookUrl ?? _status?.webhookUrl(AppConfig.supabaseUrl);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('還差一步'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.warning ?? 'LINE 的 Webhook 測試沒有通過。',
                  style: TextStyle(
                      color: AppColors.bad,
                      fontSize: AppType.small,
                      height: 1.5)),
              if (url != null) ...[
                const SizedBox(height: 12),
                Text(
                    r.webhookSet
                        ? '網址已經幫你填進 LINE Developers；請確認「Use webhook」有打開：'
                        : '請把這個網址貼到 LINE Developers 的「Webhook URL」，再打開「Use webhook」：',
                    style: TextStyle(
                        color: AppColors.muted,
                        fontSize: AppType.small,
                        height: 1.5)),
                const SizedBox(height: 8),
                _UrlBox(url: url),
              ],
              const SizedBox(height: 10),
              Text('改好之後回來按「驗證一次」。',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: AppType.small)),
            ]),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('知道了'))
        ],
      ),
    );
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    StoreLineResult? res;
    try {
      res = await _repo.testStoreLine(_store);
      final r = res;
      if (mounted) setState(() => _note = r.ok ? null : r.error);
    } catch (e) {
      if (mounted) setState(() => _note = friendlyError(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (!mounted || !res.ok) return;
    if (res.verified) {
      showMessage(context, 'LINE 連線正常');
    } else {
      // token 可以用、但 Webhook 測試沒過：跟存金鑰那條路一樣提示，不說「正常」（Codex P2）
      await _afterSaveDialog(res);
    }
  }

  Future<void> _clear() async {
    final viaStore = _status?.groupViaStore ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('解除這個 LINE 官方帳號？'),
        content: Text(viaStore
            ? '存著的金鑰會刪掉，透過這個帳號綁的工作群組也會一起解除，之後重要交接不會再發到 LINE。'
            : '存著的金鑰會刪掉，之後不會再用這個帳號發訊息。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('解除')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _repo.clearStoreLine(_store);
    } catch (e) {
      if (mounted) {
        setState(() => _note = friendlyError(e));
        showMessage(context, friendlyError(e), error: true);
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
    if (mounted) showMessage(context, '已經解除這個 LINE 官方帳號');
  }

  Future<void> _bindCode() async {
    LineBindCode first;
    try {
      first = await _repo.createLineGroupBindCode(_store);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => LineBindDialog(
        storeName: widget.membership.storeName,
        first: first,
        regenerate: () => _repo.createLineGroupBindCode(_store),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('LINE 官方帳號')),
      body: s == null
          ? (_loadError != null
              ? ErrorView(message: _loadError!, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _statusCard(s),
                  const SizedBox(height: 12),
                  _stepsCard(s),
                  const SizedBox(height: 12),
                  _form(s),
                ],
              ),
            ),
    );
  }

  Widget _statusCard(StoreLineStatus s) {
    if (!s.connected) {
      return SectionCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.forum_outlined, color: AppColors.muted)),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('還沒接上自己的 LINE 官方帳號',
                  style: TextStyle(
                      fontSize: AppType.title, fontWeight: AppFont.heading)),
              const SizedBox(height: 4),
              Text('接上之後，重要交接用你的官方帳號發到工作群組，訊息則數算你自己的；在群組 @機器人 也能問店裡的事。',
                  style: TextStyle(
                      color: AppColors.muted,
                      fontSize: AppType.small,
                      height: 1.5)),
            ]),
          ),
        ]),
      );
    }
    final error = _note ?? s.lastError;
    final url = s.webhookUrl(AppConfig.supabaseUrl);
    final group = !s.groupBound
        ? '還沒綁定'
        : s.groupViaStore
            ? '已綁定（透過這個官方帳號）'
            : '已綁定（透過平台的帳號；要改用這個帳號，先在群組打「解除綁定」再重新綁）';
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(error == null ? Icons.check_circle_outline : Icons.error_outline,
              color: error == null ? AppColors.good : AppColors.bad),
          const SizedBox(width: 10),
          Expanded(
            child: Text('已接上：${s.botName ?? 'LINE 官方帳號'}',
                style: const TextStyle(
                    fontSize: AppType.title, fontWeight: AppFont.heading)),
          ),
        ]),
        const SizedBox(height: 12),
        if (s.basicId != null) _kv('帳號 ID', s.basicId!),
        _kv('Channel secret', '•••• ${s.secretLast4 ?? ''}'),
        _kv('Access token', '•••• ${s.tokenLast4 ?? ''}'),
        _kv(
            '上次驗證',
            s.verifiedAt == null
                ? '還沒驗證成功'
                : DateFormat('M/d HH:mm').format(toTaipei(s.verifiedAt!))),
        _kv('工作群組', group),
        if (url != null) ...[
          const SizedBox(height: 10),
          Text('Webhook URL（貼到 LINE Developers）',
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          const SizedBox(height: 6),
          _UrlBox(url: url),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          _ErrorLine(text: error),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.tonalIcon(
            onPressed: _busy ? null : _bindCode,
            icon: const Icon(Icons.group_add_outlined, size: 20),
            label: const Text('產生群組綁定代碼'),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _test,
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('驗證一次'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextButton(
                onPressed: _busy ? null : _clear,
                child: Text('解除這個帳號', style: TextStyle(color: AppColors.bad)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _stepsCard(StoreLineStatus s) {
    final steps =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < storeLineSteps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.line)),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      fontSize: AppType.small, fontWeight: AppFont.label)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(storeLineSteps[i].$1,
                        style: const TextStyle(
                            fontSize: AppType.body,
                            fontWeight: AppFont.heading)),
                    const SizedBox(height: 2),
                    Text(storeLineSteps[i].$2,
                        style: TextStyle(
                            color: AppColors.muted,
                            fontSize: AppType.small,
                            height: 1.5)),
                  ]),
            ),
          ]),
        ),
    ]);
    return SectionCard(
      // ListTile 要畫在自己的 Material 上，不然卡片的底色會蓋掉點按的效果
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 4),
            initiallyExpanded: !s.connected,
            title: const Text('怎麼接（一步一步）',
                style: TextStyle(
                    fontSize: AppType.title, fontWeight: AppFont.heading)),
            children: [steps],
          ),
        ),
      ),
    );
  }

  Widget _form(StoreLineStatus s) {
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.connected ? '換一組金鑰' : '貼上金鑰',
            style: const TextStyle(
                fontSize: AppType.title, fontWeight: AppFont.heading)),
        const SizedBox(height: 6),
        Text('兩組都在 LINE Developers 你的 channel 裡。存好之後這裡只會顯示最後 4 碼，誰都看不到完整的。',
            style: TextStyle(
                color: AppColors.muted, fontSize: AppType.small, height: 1.5)),
        const SizedBox(height: 16),
        TextField(
          controller: _secret,
          enabled: !_busy,
          obscureText: !_show,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const <String>[],
          decoration: const InputDecoration(
              labelText: 'Channel secret', hintText: '32 個英數字（Basic settings）'),
          onChanged: (_) => setState(() => _formError = null),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _token,
          enabled: !_busy,
          obscureText: !_show,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const <String>[],
          decoration: InputDecoration(
            labelText: 'Channel access token',
            hintText: 'Messaging API 分頁最下面（long-lived）',
            suffixIcon: IconButton(
              tooltip: _show ? '遮住' : '顯示',
              icon: Icon(_show
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
          onChanged: (_) => setState(() => _formError = null),
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
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('驗證並接上'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('會先用 token 跟 LINE 確認這個官方帳號，成功才存。',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        ),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 104,
              child: Text(k,
                  style: TextStyle(
                      color: AppColors.muted, fontSize: AppType.small))),
          Expanded(
              child: Text(v,
                  style:
                      const TextStyle(fontSize: AppType.small, height: 1.4))),
        ]),
      );
}

/// Webhook 網址＋複製
class _UrlBox extends StatelessWidget {
  const _UrlBox({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.line)),
        child: Row(children: [
          Expanded(
              child: SelectableText(url,
                  style:
                      const TextStyle(fontSize: AppType.caption, height: 1.4))),
          IconButton(
            tooltip: '複製網址',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) showMessage(context, '已複製 Webhook 網址');
            },
          ),
        ]),
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
            borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, size: 18, color: AppColors.bad),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: AppColors.bad,
                      fontSize: AppType.small,
                      height: 1.4))),
        ]),
      );
}
