import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 廠商資料（0076，老闆 2026-10-29）：進貨分頁的廠商通訊錄。
/// 分「月結廠商」「其他廠商」兩類；只有老闆、店長看得到、能新增修改刪除（資料庫 RLS 也只允許這兩種角色）。
class VendorContactsScreen extends StatefulWidget {
  const VendorContactsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<VendorContactsScreen> createState() => _VendorContactsScreenState();
}

class _VendorContactsScreenState extends State<VendorContactsScreen> {
  late Future<List<VendorContact>> _future;
  String _kind = 'monthly';
  String _q = '';
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  Future<List<VendorContact>> _load() => AppScope.of(context).repo.vendorContacts(widget.membership.storeId);
  void _reload() => setState(() => _future = _load());

  Future<void> _edit(VendorContact? v) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VendorContactFormScreen(membership: widget.membership, vendor: v, kind: _kind),
      ),
    );
    if (saved == true) _reload();
  }

  bool _match(VendorContact v) {
    final q = _q.trim();
    if (q.isEmpty) return true;
    return [v.name, v.items, v.contact, v.note].any((t) => t.contains(q));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('廠商資料')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add),
          label: const Text('新增廠商'),
        ),
        body: FutureBuilder<List<VendorContact>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final all = snap.data!;
            final count = {for (final k in VendorContact.kinds.keys) k: all.where((v) => v.kind == k).length};
            final shown = all.where((v) => v.kind == _kind && _match(v)).toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                Row(children: [
                  for (final e in VendorContact.kinds.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SelectChip(
                        label: Text('${e.value} ${count[e.key]}'),
                        selected: _kind == e.key,
                        onSelected: (_) => setState(() => _kind = e.key),
                      ),
                    ),
                ]),
                if (all.length > 6) ...[
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '搜尋廠商、品項',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ],
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Text(
                      _q.trim().isNotEmpty
                          ? '找不到「${_q.trim()}」'
                          : '還沒有${VendorContact.kinds[_kind]}\n按右下角「新增廠商」加第一筆',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, height: 1.6),
                    ),
                  )
                else
                  for (final v in shown) ...[_VendorCard(v: v, onTap: () => _edit(v)), const SizedBox(height: 10)],
                const SizedBox(height: 8),
                Text('只有老闆、店長看得到這一頁（含匯款帳號）。',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
              ]),
            );
          },
        ),
      );
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.v, required this.onTap});
  final VendorContact v;
  final VoidCallback onTap;

  Future<void> _copy(BuildContext context, String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showMessage(context, '已複製$what');
  }

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(color: AppColors.muted, fontSize: AppType.small);
    Widget fact(String k, String val, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 72, child: Text(k, style: label)),
            Expanded(child: Text(val, style: const TextStyle(fontSize: AppType.small, height: 1.45))),
            if (trailing != null) trailing,
          ]),
        );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 廠商名稱後面接品項，品項用金色、字大一點（老闆 2026-10-29）；結帳日移到下面一行
            Text.rich(
              TextSpan(children: [
                TextSpan(text: v.name, style: const TextStyle(fontSize: AppType.title, fontWeight: AppFont.heading)),
                if (v.items.trim().isNotEmpty) ...[
                  const TextSpan(text: '   '),
                  TextSpan(
                    text: v.items.trim(),
                    style: TextStyle(fontSize: AppType.body, fontWeight: AppFont.label, color: AppColors.primary),
                  ),
                ],
              ]),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (v.billingDay.trim().isNotEmpty) fact('結帳', v.billingDay.trim()),
            if (v.contact.trim().isNotEmpty) fact('聯絡', v.contact.trim()),
            // 匯款：銀行、帳號分兩行（老闆 2026-10-29），帳號那行可以複製
            if (v.bank.trim().isNotEmpty) fact('匯款銀行', v.bank.trim()),
            if (v.account.trim().isNotEmpty)
              fact(
                '匯款帳號',
                v.account.trim(),
                trailing: SizedBox(
                  height: 28,
                  child: IconButton(
                    tooltip: '複製帳號',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: Icon(Icons.copy_outlined, color: AppColors.muted),
                    onPressed: () => _copy(context, v.account.trim(), '帳號'),
                  ),
                ),
              ),
            if (v.note.trim().isNotEmpty) fact('備註', v.note.trim()),
          ]),
        ),
      ),
    );
  }
}

/// 新增／修改一筆廠商資料
class VendorContactFormScreen extends StatefulWidget {
  const VendorContactFormScreen({super.key, required this.membership, this.vendor, required this.kind});
  final Membership membership;
  final VendorContact? vendor;
  final String kind; // 新增時預設的類別（目前在看的那一類）
  @override
  State<VendorContactFormScreen> createState() => _VendorContactFormScreenState();
}

class _VendorContactFormScreenState extends State<VendorContactFormScreen> {
  late String _kind;
  late final _name = TextEditingController(text: widget.vendor?.name ?? '');
  late final _items = TextEditingController(text: widget.vendor?.items ?? '');
  late final _contact = TextEditingController(text: widget.vendor?.contact ?? '');
  late final _bank = TextEditingController(text: widget.vendor?.bank ?? '');
  late final _account = TextEditingController(text: widget.vendor?.account ?? '');
  late final _billing = TextEditingController(text: widget.vendor?.billingDay ?? '');
  late final _note = TextEditingController(text: widget.vendor?.note ?? '');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.vendor?.kind ?? widget.kind;
  }

  @override
  void dispose() {
    for (final c in [_name, _items, _contact, _bank, _account, _billing, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showMessage(context, '請填廠商名稱', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).repo.saveVendorContact(
            widget.membership.storeId,
            VendorContact(
              id: widget.vendor?.id,
              kind: _kind,
              name: _name.text,
              items: _items.text,
              contact: _contact.text,
              bank: _bank.text,
              account: _account.text,
              note: _note.text,
              billingDay: _billing.text,
            ),
          );
      if (!mounted) return;
      showMessage(context, '已儲存');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyError(e);
      showMessage(context, msg.contains('duplicate') || msg.contains('23505') ? '已經有同名的廠商' : msg, error: true);
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('刪除「${widget.vendor!.name}」？'),
        content: const Text('刪除後這筆廠商資料就不見了，進貨紀錄不受影響。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.of(context).repo.deleteVendorContact(widget.vendor!.id!);
      if (!mounted) return;
      showMessage(context, '已刪除');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Widget _field(TextEditingController c, String label,
          {String? hint, int maxLength = 200, int maxLines = 1, TextInputType? keyboard, bool required = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: c,
          maxLength: maxLength,
          minLines: 1,
          maxLines: maxLines,
          keyboardType: keyboard ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
          decoration: InputDecoration(labelText: required ? '$label（必填）' : label, hintText: hint, counterText: ''),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.vendor != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '修改廠商' : '新增廠商'),
        actions: [
          if (editing)
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline, color: AppColors.bad),
              label: Text('刪除', style: TextStyle(color: AppColors.bad)),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text('類別', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        const SizedBox(height: 8),
        Row(children: [
          for (final e in VendorContact.kinds.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SelectChip(label: Text(e.value), selected: _kind == e.key, onSelected: (_) => setState(() => _kind = e.key)),
            ),
        ]),
        const SizedBox(height: 18),
        _field(_name, '廠商名稱', maxLength: 60, required: true),
        _field(_items, '品項', hint: '例：琴酒、伏特加、蘭姆酒', maxLength: 500, maxLines: 4),
        _field(_contact, '聯絡方式', hint: '電話、LINE、聯絡人', maxLength: 200, maxLines: 3),
        _field(_bank, '匯款銀行', hint: '例：台灣銀行 004', maxLength: 60),
        _field(_account, '匯款帳號', maxLength: 40, keyboard: TextInputType.text),
        _field(_billing, '結帳日', hint: '例：每月 25 日、月底', maxLength: 30),
        _field(_note, '備註', maxLength: 1000, maxLines: 5),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(_saving ? '儲存中…' : '儲存'),
        ),
        const SizedBox(height: 12),
        Text('只有老闆、店長看得到廠商資料（含匯款帳號）。',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
      ]),
    );
  }
}
