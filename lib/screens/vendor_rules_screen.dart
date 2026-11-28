import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/vendor_rules.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 廠商名稱設定（ops 0166，公版）：同一家廠商的不同寫法合併、「選擇廠商」清單的調整、各類別的常用廠商提示。
/// 只有老闆、店長能改（資料庫 RLS 也是這樣）；只影響 App 顯示，進貨資料與成本率都不會變。
class VendorRulesScreen extends StatefulWidget {
  const VendorRulesScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<VendorRulesScreen> createState() => _VendorRulesScreenState();
}

class _VendorRulesScreenState extends State<VendorRulesScreen> {
  late Future<(List<VendorRule>, List<CostCategory>)> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  Future<(List<VendorRule>, List<CostCategory>)> _load() async {
    final repo = AppScope.of(context).repo;
    final r = await Future.wait(
        [repo.vendorRules(widget.membership.storeId), repo.costCategories()]);
    final rules = r[0] as List<VendorRule>;
    VendorRules.put(
        widget.membership.storeId, VendorRules(rules, fromDb: true));
    final cats = (r[1] as List<CostCategory>)
        .where((c) =>
            c.selectable &&
            (c.storeName == null || c.storeName == widget.membership.storeName))
        .toList();
    return (rules, cats);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _edit(
      VendorRule? rule, String kind, List<CostCategory> cats) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RuleSheet(
          membership: widget.membership, rule: rule, kind: kind, cats: cats),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(VendorRule r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除這條設定？'),
        content: Text(describeVendorRule(r, const {})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('刪除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.of(context).repo.deleteVendorRule(r.id!);
      if (mounted) showMessage(context, '已刪除');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('廠商名稱設定')),
        body: FutureBuilder<(List<VendorRule>, List<CostCategory>)>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorView(
                  message: friendlyError(snap.error!), onRetry: _reload);
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final (rules, cats) = snap.data!;
            final catName = {for (final c in cats) c.code: c.name};
            List<VendorRule> of(Set<String> kinds) =>
                rules.where((r) => kinds.contains(r.kind)).toList();
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text('只影響 App 顯示：進貨資料、日報表、成本率都不會改。',
                        style: TextStyle(
                            color: AppColors.muted,
                            fontSize: AppType.small,
                            height: 1.5)),
                    const SizedBox(height: 12),
                    _section(
                      title: '同一家廠商的不同寫法',
                      note: '例：「德哥」「阿德」都算「阿德水果」',
                      rules: of({'alias'}),
                      addLabel: '新增寫法',
                      onAdd: () => _edit(null, 'alias', cats),
                      catName: catName,
                      cats: cats,
                    ),
                    const SizedBox(height: 12),
                    _section(
                      title: '新增進貨「選擇廠商」清單',
                      note: '清單照最近三個月的月結廠商自動列；這裡可以改名、不顯示、一定列出',
                      rules: of({'list_alias', 'list_hide', 'list_add'}),
                      addLabel: '新增清單設定',
                      onAdd: () => _edit(null, 'list_hide', cats),
                      catName: catName,
                      cats: cats,
                    ),
                    const SizedBox(height: 12),
                    _section(
                      title: '常用廠商提示',
                      note: '新增進貨選了類別後，下面會出現常用廠商，點一下就帶入',
                      rules: of({
                        'hint_add',
                        'hint_remove',
                        'hint_alias',
                        'hint_hide',
                        'petty_hint_hide'
                      }),
                      addLabel: '新增常用廠商',
                      onAdd: () => _edit(null, 'hint_add', cats),
                      catName: catName,
                      cats: cats,
                    ),
                  ]),
            );
          },
        ),
      );

  Widget _section({
    required String title,
    required String note,
    required List<VendorRule> rules,
    required String addLabel,
    required VoidCallback onAdd,
    required Map<String, String> catName,
    required List<CostCategory> cats,
  }) =>
      SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: AppType.title, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(note,
                  style: TextStyle(
                      color: AppColors.muted,
                      fontSize: AppType.small,
                      height: 1.45)),
            ]),
          ),
          const SizedBox(height: 6),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('還沒有設定',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: AppType.small)),
            )
          else
            for (final r in rules)
              ListTile(
                contentPadding: EdgeInsets.zero,
                minTileHeight: 48,
                title: Text(describeVendorRule(r, catName)),
                subtitle: Text(vendorRuleLabels[r.kind]?.$1 ?? r.kind,
                    style: TextStyle(
                        color: AppColors.muted, fontSize: AppType.caption)),
                onTap: () => _edit(r, r.kind, cats),
                trailing: IconButton(
                  tooltip: '刪除',
                  icon: Icon(Icons.delete_outline, color: AppColors.muted),
                  onPressed: () => _delete(r),
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: Text(addLabel)),
          ),
        ]),
      );
}

class _RuleSheet extends StatefulWidget {
  const _RuleSheet(
      {required this.membership,
      required this.rule,
      required this.kind,
      required this.cats});
  final Membership membership;
  final VendorRule? rule;
  final String kind;
  final List<CostCategory> cats;
  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late String _kind = widget.kind;
  late String? _category = widget.rule?.category;
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _target = TextEditingController(text: widget.rule?.target ?? '');
  String? _error;
  bool _saving = false;

  /// 新增時可以換成哪幾種（跟開啟的區塊同一組）；修改時種類不換
  List<String> get _choices {
    if (widget.rule != null) return [_kind];
    return switch (widget.kind) {
      'alias' => const ['alias'],
      'list_alias' || 'list_hide' || 'list_add' => const [
          'list_hide',
          'list_add',
          'list_alias'
        ],
      _ => const [
          'hint_add',
          'hint_remove',
          'hint_hide',
          'petty_hint_hide',
          'hint_alias'
        ],
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = validateVendorRule(_kind, _category, _name.text, _target.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).repo.saveVendorRule(
            widget.membership.storeId,
            VendorRule(
              id: widget.rule?.id,
              kind: _kind,
              category: VendorRule.needsCategory(_kind) ? _category : null,
              name: VendorRule.needsName(_kind) ? _name.text.trim() : null,
              target:
                  VendorRule.needsTarget(_kind) ? _target.text.trim() : null,
              sortOrder: widget.rule?.sortOrder ?? 0,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final msg = friendlyError(e);
      if (mounted) {
        setState(() {
          _saving = false;
          _error = msg.contains('duplicate') || msg.contains('23505')
              ? '已經有同一條設定'
              : msg;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = vendorRuleLabels[_kind];
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.rule == null ? '新增設定' : '修改設定',
                  style: const TextStyle(
                      fontSize: AppType.title, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (_choices.length > 1) ...[
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final k in _choices)
                    SelectChip(
                      label: Text(vendorRuleLabels[k]?.$1 ?? k),
                      selected: _kind == k,
                      onSelected: (_) => setState(() {
                        _kind = k;
                        _error = null;
                      }),
                    ),
                ]),
                const SizedBox(height: 10),
              ],
              if (info != null)
                Text(info.$2,
                    style: TextStyle(
                        color: AppColors.muted,
                        fontSize: AppType.small,
                        height: 1.45)),
              const SizedBox(height: 12),
              if (VendorRule.needsCategory(_kind)) ...[
                DropdownButtonFormField<String>(
                  initialValue: widget.cats.any((c) => c.code == _category)
                      ? _category
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '進貨類別'),
                  items: [
                    for (final c in widget.cats)
                      DropdownMenuItem(value: c.code, child: Text(c.name))
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 12),
              ],
              if (VendorRule.needsName(_kind)) ...[
                TextField(
                  controller: _name,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: VendorRule.needsTarget(_kind) ? '原本的寫法' : '廠商名稱',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (VendorRule.needsTarget(_kind)) ...[
                TextField(
                  controller: _target,
                  maxLength: 60,
                  decoration:
                      const InputDecoration(labelText: '統一叫做', counterText: ''),
                ),
                const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                Text(_error!,
                    style: TextStyle(
                        color: AppColors.bad, fontSize: AppType.small)),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('儲存'),
              ),
            ]),
      ),
    );
  }
}
