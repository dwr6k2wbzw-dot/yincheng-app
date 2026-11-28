import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 進貨類別（ops 0165，公版）：類別跟著店，老闆可以新增、改名、停用。
/// 不能刪（舊進貨要對得到）；已經有進貨的類別不能改「算在哪一類」（成本率會跟著變），資料庫也會擋。
/// 隱城、小城外的類別照日報表，這個畫面不出現（入口只在公版、而且這家店沒有開「以日報表為準」）。
class CostCategoriesScreen extends StatefulWidget {
  const CostCategoriesScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<CostCategoriesScreen> createState() => _CostCategoriesScreenState();
}

class _CostCategoriesScreenState extends State<CostCategoriesScreen> {
  Future<List<CostCategory>>? _future;
  bool _seeding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<CostCategory>> _load() async {
    final m = widget.membership;
    final all = await AppScope.of(context).repo.costCategories();
    return all
        .where(
          (c) =>
              c.storeId == m.storeId ||
              (c.storeId == null && c.storeName == m.storeName),
        )
        .toList();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      final n = await AppScope.of(context).repo
          .seedCostCategories(widget.membership.storeId);
      if (mounted) showMessage(context, n > 0 ? '已帶入酒水、餐食、雜項' : '這家店已經有類別了');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _edit(CostCategory? c, List<CostCategory> all) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CostCategorySheet(
        membership: widget.membership,
        category: c,
        existing: all,
      ),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('進貨類別')),
    floatingActionButton: FutureBuilder<List<CostCategory>>(
      future: _future,
      builder: (context, snap) => snap.hasData && snap.data!.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _edit(null, snap.data!),
              icon: const Icon(Icons.add),
              label: const Text('新增類別'),
            )
          : const SizedBox.shrink(),
    ),
    body: FutureBuilder<List<CostCategory>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView(
            message: friendlyError(snap.error!),
            onRetry: _reload,
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data!;
        if (all.isEmpty) return _empty();
        final active = all.where((c) => c.selectable).toList();
        final off = all.where((c) => !c.selectable).toList();
        final note = TextStyle(
          color: AppColors.muted,
          fontSize: AppType.caption,
          height: 1.5,
        );
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text('新增進貨時選這些類別；成本率照每個類別「算在哪一類」加總。', style: note),
              const SizedBox(height: 12),
              for (final c in active) ...[
                _CategoryTile(c: c, onTap: () => _edit(c, all)),
                const SizedBox(height: 8),
              ],
              if (off.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '已停用（新增進貨選不到，舊的進貨照常計入）',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: AppType.small,
                    fontWeight: AppFont.label,
                  ),
                ),
                const SizedBox(height: 8),
                for (final c in off) ...[
                  _CategoryTile(c: c, onTap: () => _edit(c, all)),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 8),
              Text(
                '類別不能刪除；不用的請停用。已經有進貨的類別，不能改算在哪一類。',
                textAlign: TextAlign.center,
                style: note,
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _empty() => ListView(
    padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
    children: [
      const Text(
        '這家店還沒有進貨類別',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: AppType.title,
          fontWeight: AppFont.heading,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '先帶入最常用的三類，之後可以再新增、改名。',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted, height: 1.5),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _seeding ? null : _seed,
        icon: _seeding
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.playlist_add),
        label: const Text('帶入酒水、餐食、雜項'),
      ),
    ],
  );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.c, required this.onTap});
  final CostCategory c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final group = CostCategory.groupLabels[c.costGroup] ?? c.costGroup;
    final sub = ['算在$group', if (c.inMiscRate) '算雜項成本率'].join('・');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: SectionCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: TextStyle(
                        fontSize: AppType.title,
                        fontWeight: AppFont.heading,
                        color: c.selectable ? null : AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sub,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: AppType.small,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 新增／修改一個類別（底部表單）
class CostCategorySheet extends StatefulWidget {
  const CostCategorySheet({
    super.key,
    required this.membership,
    this.category,
    required this.existing,
  });
  final Membership membership;
  final CostCategory? category;
  final List<CostCategory> existing;
  @override
  State<CostCategorySheet> createState() => _CostCategorySheetState();
}

class _CostCategorySheetState extends State<CostCategorySheet> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String _group =
      CostCategory.groupLabels.containsKey(widget.category?.costGroup)
      ? widget.category!.costGroup
      : 'food';
  late bool _misc = widget.category?.inMiscRate ?? false;
  late bool _active = widget.category?.selectable ?? true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.category == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// App 先檢查一次（資料庫也會擋）
  String? _check() {
    final n = _name.text.trim();
    if (n.isEmpty) return '請輸入類別名稱';
    if (n.length > 20) return '類別名稱最多 20 個字';
    if (widget.existing.any(
      (c) => c.name == n && c.code != widget.category?.code,
    )) {
      return '這家店已經有同名的類別';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _check();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).repo.saveCostCategory(
        widget.membership.storeId,
        code: widget.category?.code,
        name: _name.text.trim(),
        costGroup: _group,
        inMiscRate: _misc,
        selectable: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: AppColors.muted,
      fontSize: AppType.small,
      height: 1.45,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isNew ? '新增類別' : '修改類別',
              style: const TextStyle(
                fontSize: AppType.heading,
                fontWeight: AppFont.heading,
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              autofocus: _isNew,
              maxLength: 20,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '類別名稱',
                hintText: '例如 咖啡豆、外帶杯',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 8),
            Text('算在哪一類（成本率）', style: muted),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in CostCategory.groupLabels.entries)
                  SelectChip(
                    label: Text(e.value),
                    selected: _group == e.key,
                    onSelected: (_) => setState(() {
                      _group = e.key;
                      if (_isNew) _misc = e.key == 'other';
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _misc,
              onChanged: (v) => setState(() => _misc = v),
              title: const Text('算進雜項成本率'),
              subtitle: Text('雜項成本率＝這些類別的進貨 ÷ 營收', style: muted),
            ),
            if (!_isNew)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: !_active,
                onChanged: (v) => setState(() => _active = !v),
                title: const Text('停用'),
                subtitle: Text('新增進貨選不到；舊的進貨照常計入', style: muted),
              ),
            if (!_isNew) ...[
              const SizedBox(height: 4),
              Text('已經有進貨的類別，只能改名字和停用。', style: muted),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }
}
