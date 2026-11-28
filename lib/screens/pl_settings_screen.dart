import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/pl_template.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 損益設定（ops 0169，只有公版、只有老闆）：
///   * 還沒有會計科目：選業態套一組常用科目（只放科目，不放金額）
///   * 會計科目：新增、改名、改大項、指定自動帶入、停用（不能刪，0142）
///   * 刷卡手續費率、損益表抬頭
///   * 每月固定支出：新增、改名稱／大項／科目、刪除（改金額到總覽，可以選從哪個月起，0090）
class PlSettingsScreen extends StatefulWidget {
  const PlSettingsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<PlSettingsScreen> createState() => _PlSettingsScreenState();
}

class _PlSettingsScreenState extends State<PlSettingsScreen> {
  bool _started = false;
  bool _loaded = false;
  String? _loadError;
  bool _busy = false;

  List<PlAccount> _accounts = const [];
  List<PlTemplate> _templates = const [];
  String? _templateError;
  double _rate = 0.02;
  String? _title;
  List<RecurringExpenseItem> _recurring = const [];

  final _rateCtl = TextEditingController();
  final _titleCtl = TextEditingController();
  String? _basicError;

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

  /// 底部面板關閉的動畫還在用輸入框，等動畫跑完才釋放（馬上 dispose 會丟「used after being disposed」）
  void _disposeLater(List<TextEditingController> cs) {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      for (final c in cs) {
        c.dispose();
      }
    });
  }

  @override
  void dispose() {
    _rateCtl.dispose();
    _titleCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<Object?>([
        _repo.plAccounts(_store),
        _repo.cardFeeRate(_store),
        _repo.plTitle(_store),
        _repo.recurringExpenseItems(_store),
      ]);
      final accounts = (r[0] as List<PlAccount>).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      var templates = _templates;
      String? tErr;
      if (accounts.isEmpty && templates.isEmpty) {
        try {
          templates = await _repo.plTemplates();
        } catch (e) {
          tErr = friendlyError(e);
        }
      }
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _rate = r[1] as double;
        _title = r[2] as String?;
        _recurring = r[3] as List<RecurringExpenseItem>;
        _templates = templates;
        _templateError = tErr;
        _rateCtl.text = _pct(_rate);
        _titleCtl.text = _title ?? '';
        _loaded = true;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = friendlyError(e));
    }
  }

  /// 費率顯示：百分比最多兩位小數、去掉尾端的 0（同總覽）
  static String _pct(double rate) {
    var s = (rate * 100).toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  PlAccount? _accountOf(String? id) =>
      id == null ? null : _accounts.where((a) => a.id == id).firstOrNull;

  // ---------------------------------------------------------------- 範本
  Future<void> _previewTemplate(PlTemplate t) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(t.icon, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Text('${t.label}的科目',
                        style: const TextStyle(
                            fontSize: AppType.title,
                            fontWeight: AppFont.heading)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${t.summary}。只放科目、不放金額，套完都可以改名、停用、再加。',
                      style: TextStyle(
                          color: AppColors.muted,
                          fontSize: AppType.small,
                          height: 1.5)),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(shrinkWrap: true, children: [
                      for (final cat in const ['payroll', 'rent', 'misc']) ...[
                        if (t.accounts.any((a) => a.category == cat)) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Text(plCategoryLabels[cat]!,
                                style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: AppType.caption,
                                    fontWeight: AppFont.label)),
                          ),
                          for (final a
                              in t.accounts.where((a) => a.category == cat))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(children: [
                                Expanded(
                                    child: Text(a.name,
                                        style: const TextStyle(
                                            fontSize: AppType.body))),
                                if (a.autoKind != null)
                                  _AutoTag(kind: a.autoKind!),
                              ]),
                            ),
                        ],
                      ],
                    ]),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text('套用「${t.label}」')),
                  ),
                ]),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await _repo.applyPlTemplate(_store, t.kind);
      if (!mounted) return;
      showMessage(context, '已經建好 $n 個科目');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  // ---------------------------------------------------------------- 科目
  Future<void> _editAccount(PlAccount? a) async {
    final isNew = a == null;
    final name = TextEditingController(text: a?.name ?? '');
    var category = a?.category ?? 'misc';
    String? auto = a?.autoKind;
    var active = a?.active ?? true;
    String? err;
    // 送出中不能再按（慢網路連按會重複新增）
    var saving = false;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final autoOptions = [
            for (final e in plAutoKinds.entries)
              if (e.value.$2 == category) e.key
          ];
          Future<void> save() async {
            if (saving) return;
            final n = name.text.trim();
            if (n.isEmpty || n.length > 40) {
              set(() => err = '科目名稱要 1～40 個字');
              return;
            }
            final row = PlAccount(
              id: a?.id ?? '',
              name: n,
              category: category,
              autoKind: auto,
              sortOrder: a?.sortOrder ??
                  (_accounts.isEmpty
                      ? 1
                      : _accounts
                              .map((x) => x.sortOrder)
                              .reduce((x, y) => x > y ? x : y) +
                          1),
              active: active,
            );
            set(() => saving = true);
            try {
              await _repo.savePlAccount(_store, row, isNew: isNew);
              // 面板還開著（不是正在被拉下來關掉的動畫中）才關：動畫中 c 還在，
              // 這時再 pop 會把底下的設定畫面關掉（Codex 第三輪）
              if (c.mounted && (ModalRoute.of(c)?.isCurrent ?? false)) {
                Navigator.pop(c, true);
              } else if (mounted) {
                // 面板在儲存中被拉下來關掉了：照樣重新讀，免得以為沒存又新增一次
                await _load();
              }
            } catch (e) {
              if (c.mounted) {
                set(() {
                  saving = false;
                  err = friendlyError(e);
                });
              }
            }
          }

          // 儲存中不能按返回、點外面關掉面板
          return PopScope(
            canPop: !saving,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isNew ? '新增科目' : '修改科目',
                          style: const TextStyle(
                              fontSize: AppType.title,
                              fontWeight: AppFont.heading)),
                      if (err != null) ...[
                        const SizedBox(height: 12),
                        _ErrorLine(text: err!)
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: name,
                        maxLength: 40,
                        decoration:
                            const InputDecoration(labelText: '科目名稱（例：水電瓦斯費）'),
                        onChanged: (_) => set(() => err = null),
                      ),
                      const SizedBox(height: 4),
                      Text('算進損益卡片的哪一大項',
                          style: TextStyle(
                              color: AppColors.muted, fontSize: AppType.small)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            for (final e in plCategoryLabels.entries)
                              ButtonSegment(value: e.key, label: Text(e.value))
                          ],
                          selected: {category},
                          onSelectionChanged: (s) => set(() {
                            category = s.first;
                            if (auto != null &&
                                plAutoKinds[auto]!.$2 != category) {
                              auto = null;
                            }
                            err = null;
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String?>(
                        key: ValueKey('auto-$category'),
                        initialValue: autoOptions.contains(auto) ? auto : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: '自動帶入（匯出損益表時歸到這個科目）'),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('不自動帶入')),
                          for (final k in autoOptions)
                            DropdownMenuItem<String?>(
                                value: k,
                                child: Text(plAutoKinds[k]!.$1,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => set(() {
                          auto = v;
                          err = null;
                        }),
                      ),
                      if (!isNew) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('使用中'),
                          subtitle: Text('停用後新增支出時選不到；舊的支出照樣算在這個科目（科目不能刪）',
                              style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: AppType.caption)),
                          value: active,
                          onChanged: (v) => set(() => active = v),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                              onPressed: saving ? null : save,
                              child: Text(saving ? '儲存中…' : '儲存'))),
                    ]),
              ),
            ),
          );
        },
      ),
    );
    _disposeLater([name]);
    if (saved == true) await _load();
  }

  // ---------------------------------------------------------------- 手續費率、抬頭
  Future<void> _saveBasics() async {
    final v = double.tryParse(_rateCtl.text.trim());
    if (v == null || v < 0 || v > 100) {
      setState(() => _basicError = '手續費率請填 0～100 的數字（單位 %，例如 2 或 1.91）');
      return;
    }
    final title = _titleCtl.text.trim();
    if (title.length > 40) {
      setState(() => _basicError = '損益表抬頭最多 40 個字');
      return;
    }
    setState(() {
      _busy = true;
      _basicError = null;
    });
    try {
      final rate = (v * 100).round() / 10000;
      if (rate != _rate) await _repo.saveCardFeeRate(_store, rate);
      if (title != (_title ?? '')) await _repo.savePlTitle(_store, title);
      if (!mounted) return;
      showMessage(context, '已儲存');
    } catch (e) {
      if (mounted) setState(() => _basicError = friendlyError(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  // ---------------------------------------------------------------- 每月固定支出
  Future<void> _editRecurring(RecurringExpenseItem? it) async {
    final isNew = it == null;
    final name = TextEditingController(text: it?.name ?? '');
    final amount = TextEditingController(
        text: it == null ? '' : it.amount.round().toString());
    final note = TextEditingController(text: it?.note ?? '');
    var category = it?.category ?? 'misc';
    String? accountId = it?.accountId;
    String? err;
    // 送出中不能再按：新增是每按一次就多一筆，連按會讓每個月重複扣
    var saving = false;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final options = [
          for (final a in _accounts)
            if (a.active || a.id == accountId) a
        ];
        Future<void> save() async {
          if (saving) return;
          final n = name.text.trim();
          final amt = double.tryParse(amount.text.trim());
          if (n.isEmpty) {
            set(() => err = '請填名稱');
            return;
          }
          if (isNew && (amt == null || amt < 0)) {
            set(() => err = '請填每月金額（0 以上）');
            return;
          }
          set(() => saving = true);
          try {
            await _repo.saveRecurringExpenseItem(
              _store,
              RecurringExpenseItem(
                id: it?.id ?? '',
                name: n,
                category: category,
                amount: isNew ? amt! : it.amount,
                amountsFrom: it?.amountsFrom ?? const {},
                accountId: accountId,
                note: note.text,
              ),
              isNew: isNew,
            );
            // 面板還開著（不是正在被拉下來關掉的動畫中）才關：動畫中 c 還在，
            // 這時再 pop 會把底下的設定畫面關掉（Codex 第三輪）
            if (c.mounted && (ModalRoute.of(c)?.isCurrent ?? false)) {
              Navigator.pop(c, 'saved');
            } else if (mounted) {
              // 面板在儲存中被拉下來關掉了：照樣重新讀，免得以為沒存又新增一次（每月重複扣）
              await _load();
            }
          } catch (e) {
            if (c.mounted) {
              set(() {
                saving = false;
                err = friendlyError(e);
              });
            }
          }
        }

        // 儲存中不能按返回、點外面關掉面板
        return PopScope(
          canPop: !saving,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isNew ? '新增每月固定支出' : '修改每月固定支出',
                        style: const TextStyle(
                            fontSize: AppType.title,
                            fontWeight: AppFont.heading)),
                    if (err != null) ...[
                      const SizedBox(height: 12),
                      _ErrorLine(text: err!)
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '名稱（例：記帳費）'),
                      onChanged: (_) => set(() => err = null),
                    ),
                    const SizedBox(height: 12),
                    if (isNew)
                      TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: '每月金額', prefixText: 'NT\$ '),
                        onChanged: (_) => set(() => err = null),
                      )
                    else
                      Text(
                          '每月金額 ${ntd(it.amountFor(DateTime.now()))}。改金額請到總覽的本月損益點這一筆，可以選從哪個月起改。',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: AppType.small,
                              height: 1.5)),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          for (final e in ExpenseItem.categoryLabels.entries)
                            ButtonSegment(value: e.key, label: Text(e.value))
                        ],
                        selected: {category},
                        onSelectionChanged: (s) =>
                            set(() => category = s.first),
                      ),
                    ),
                    if (_accounts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: options.any((a) => a.id == accountId)
                            ? accountId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: '會計科目（匯出損益表照這個加總）'),
                        items: [
                          const DropdownMenuItem<String?>(
                              value: null, child: Text('未選')),
                          for (final a in options)
                            DropdownMenuItem<String?>(
                                value: a.id,
                                child: Text(a.name,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => set(() {
                          accountId = v;
                          final a = _accountOf(v);
                          if (a != null) category = a.category;
                        }),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: note,
                      maxLength: 100,
                      decoration:
                          const InputDecoration(labelText: '備註（損益表上看得到，可空白）'),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                            onPressed: saving ? null : save,
                            child: Text(saving ? '儲存中…' : '儲存'))),
                    if (!isNew) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: TextButton(
                          onPressed:
                              saving ? null : () => Navigator.pop(c, 'delete'),
                          child: Text('刪除這筆固定支出',
                              style: TextStyle(color: AppColors.bad)),
                        ),
                      ),
                    ],
                  ]),
            ),
          ),
        );
      }),
    );
    _disposeLater([name, amount, note]);
    if (result == 'delete' && it != null && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('刪除「${it.name}」？'),
          content:
              const Text('每個月都不會再自動帶入（包括過去的月份）。只想從某個月起不算，請到總覽把那個月起的金額改成 0。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('刪除')),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await _repo.deleteRecurringExpenseItem(it.id);
      } catch (e) {
        if (mounted) showMessage(context, friendlyError(e), error: true);
        return;
      }
    }
    if (result != null) await _load();
  }

  // ---------------------------------------------------------------- 畫面
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('損益設定')),
      body: !_loaded
          ? (_loadError != null
              ? ErrorView(message: _loadError!, onRetry: _load)
              : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_accounts.isEmpty) _templateCard() else _accountsCard(),
                  const SizedBox(height: 12),
                  _basicsCard(),
                  const SizedBox(height: 12),
                  _recurringCard(),
                ],
              ),
            ),
    );
  }

  Widget _templateCard() => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('還沒有會計科目',
              style: TextStyle(
                  fontSize: AppType.title, fontWeight: AppFont.heading)),
          const SizedBox(height: 6),
          Text('選一種最像你的店，先帶一組常用科目；匯出損益表就會照科目分類。之後可以改名、停用、自己加。',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                  height: 1.5)),
          const SizedBox(height: 14),
          if (_templateError != null)
            _ErrorLine(text: _templateError!)
          else
            for (final t in _templates)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.cardHigh,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: _busy ? null : () => _previewTemplate(t),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(children: [
                          Icon(t.icon, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.label,
                                      style: const TextStyle(
                                          fontSize: AppType.body,
                                          fontWeight: AppFont.heading)),
                                  const SizedBox(height: 2),
                                  Text('${t.summary}・${t.note}',
                                      style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: AppType.caption,
                                          height: 1.4)),
                                ]),
                          ),
                          Icon(Icons.chevron_right, color: AppColors.muted),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _editAccount(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('不用範本，自己從頭加'),
            ),
          ),
        ]),
      );

  Widget _accountsCard() {
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('會計科目',
                  style: TextStyle(
                      fontSize: AppType.title, fontWeight: AppFont.heading))),
          TextButton.icon(
              onPressed: () => _editAccount(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增')),
        ]),
        Text('匯出損益表照這些科目分類、照這個順序排。點一下可以改名、改大項或停用。',
            style: TextStyle(
                color: AppColors.muted, fontSize: AppType.small, height: 1.5)),
        for (final cat in const ['payroll', 'rent', 'misc'])
          if (_accounts.any((a) => a.category == cat)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text(plCategoryLabels[cat]!,
                  style: TextStyle(
                      color: AppColors.muted,
                      fontSize: AppType.caption,
                      fontWeight: AppFont.label)),
            ),
            for (final a in _accounts.where((a) => a.category == cat))
              _accountRow(a),
          ],
      ]),
    );
  }

  Widget _accountRow(PlAccount a) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => _editAccount(a),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Text(a.name,
                    style: TextStyle(
                        fontSize: AppType.body,
                        color: a.active ? null : AppColors.muted,
                        decoration:
                            a.active ? null : TextDecoration.lineThrough)),
              ),
              if (!a.active)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('已停用',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: AppType.caption)),
                ),
              if (a.autoKind != null) _AutoTag(kind: a.autoKind!),
              Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
            ]),
          ),
        ),
      );

  Widget _basicsCard() => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('手續費率與抬頭',
              style: TextStyle(
                  fontSize: AppType.title, fontWeight: AppFont.heading)),
          const SizedBox(height: 14),
          TextField(
            controller: _rateCtl,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: '刷卡手續費率', suffixText: '%'),
            onChanged: (_) => setState(() => _basicError = null),
          ),
          const SizedBox(height: 4),
          Text('每個月的刷卡金額 × 這個費率，自動算進雜項（不用每月輸入）。',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.caption,
                  height: 1.5)),
          const SizedBox(height: 14),
          TextField(
            controller: _titleCtl,
            enabled: !_busy,
            maxLength: 40,
            decoration: InputDecoration(
                labelText: '損益表抬頭', hintText: widget.membership.storeName),
            onChanged: (_) => setState(() => _basicError = null),
          ),
          Text('匯出的損益表最上面用這個名字（例：一店、二店）；空白＝用店名。',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.caption,
                  height: 1.5)),
          if (_basicError != null) ...[
            const SizedBox(height: 12),
            _ErrorLine(text: _basicError!)
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.tonal(
                onPressed: _busy ? null : _saveBasics, child: const Text('儲存')),
          ),
        ]),
      );

  Widget _recurringCard() {
    final now = DateTime.now();
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('每月固定支出',
                  style: TextStyle(
                      fontSize: AppType.title, fontWeight: AppFont.heading))),
          TextButton.icon(
              onPressed: () => _editRecurring(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增')),
        ]),
        Text('設一次，每個月自動帶進本月損益（例：記帳費、系統月費、保全）。',
            style: TextStyle(
                color: AppColors.muted, fontSize: AppType.small, height: 1.5)),
        if (_recurring.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('還沒有每月固定支出',
                style:
                    TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          ),
        for (final it in _recurring)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => _editRecurring(it),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.name,
                              style: const TextStyle(fontSize: AppType.body)),
                          Text(
                              '${ExpenseItem.categoryLabels[it.category] ?? it.category}・${_accountOf(it.accountId)?.name ?? (_accounts.isEmpty ? '' : '未選會計科目')}',
                              style: TextStyle(
                                  color: _accounts.isNotEmpty &&
                                          _accountOf(it.accountId) == null
                                      ? AppColors.warn
                                      : AppColors.muted,
                                  fontSize: AppType.caption)),
                        ]),
                  ),
                  Text(ntd(it.amountFor(now)),
                      style: const TextStyle(
                          fontSize: AppType.body, fontWeight: AppFont.label)),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _AutoTag extends StatelessWidget {
  const _AutoTag({required this.kind});
  final String kind;
  static const _short = {
    'payroll_base': '人事基底',
    'rent_base': '租金基底',
    'card_fee': '手續費自動',
    'purchase_misc': '進貨雜項'
  };
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Text('自動・${_short[kind] ?? kind}',
            style: const TextStyle(fontSize: AppType.caption)),
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
