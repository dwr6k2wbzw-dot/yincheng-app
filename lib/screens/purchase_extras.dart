// 進貨頁的延伸（老闆 2026-11-13，進貨與庫存改善第一版）：
// - 點任何一筆都能看內容（照片、日期、類別…），App 登記的可以複製成日報表那一列
// - 依日期看每一筆（可篩 App 登記、缺憑、不計入）
// - 待確認清單（只有老闆、店長）：App 有記、跟日報表對不太上的進貨
part of 'purchases_screen.dart';

Future<void> copyDailyReportRow(BuildContext context, DateTime date, String category, String memo, double amount) async {
  await Clipboard.setData(ClipboardData(text: dailyReportRow(date, category, memo, amount)));
  if (context.mounted) showMessage(context, '已複製。到日報表點「日期」那一格貼上，會填好日期、類別、摘要、金額');
}

Widget _kv(String k, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 84, child: Text(k, style: TextStyle(color: AppColors.muted, fontSize: AppType.small))),
        Expanded(child: Text(v, style: TextStyle(fontSize: AppType.body, color: color))),
      ]),
    );

/// 點一筆進貨：先看內容，再決定要不要修改、刪除、複製。回傳 'edited'／'deleted'／null
Future<String?> purchaseTapped(BuildContext context, Membership membership, Purchase p, String categoryName) async {
  final repo = AppScope.of(context).repo;
  final mine = p.createdBy != null && p.createdBy == repo.currentUserId;
  final allowed = !p.fromExcel && (membership.isManager || mine) && !p.reconciled;
  final locked = !p.counted; // 已被取代或以日報表為準：只能刪
  final name = p.fromExcel ? (p.supplierName ?? p.memo ?? categoryName) : (p.supplierName ?? categoryName);
  final status = p.fromExcel
      ? '日報表帶入（要改請改日報表）'
      : p.superseded
          ? 'App 登記・日報表已經有同一筆，以日報表為準'
          : p.excelCovered
              ? 'App 登記・日報表沒有這一筆，目前不計入'
              : 'App 登記・先計入，等日報表帶入';
  final why = p.fromExcel
      ? null
      : p.reconciled
          ? '已核銷的進貨不能修改或刪除，請先由老闆或店長取消核銷'
          : !(membership.isManager || mine)
              ? '只有建立這筆的人或老闆、店長可以修改、刪除'
              : null;
  final act = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.card,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(ntd(p.amount),
                    style: TextStyle(
                        fontSize: AppType.display,
                        fontWeight: AppFont.figure,
                        fontFeatures: tabular,
                        color: p.amount < 0 ? AppColors.good : null)),
              ]),
            ),
            if (p.photoPath != null)
              Column(children: [
                PhotoThumb(key: ValueKey(p.photoPath), path: p.photoPath!, size: 84),
                const SizedBox(height: 4),
                Text('點照片看大圖', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
              ]),
          ]),
          const SizedBox(height: 8),
          Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 6),
          _kv('日期', DateFormat('yyyy/M/d（E）', 'zh_TW').format(p.purchaseDate)),
          _kv('類別', categoryName),
          _kv('付款', p.paidBy == 'petty_cash' ? '零用金' : '月結廠商'),
          if (!p.fromExcel && (p.memo ?? '').trim().isNotEmpty) _kv('填表人', p.memo!.trim()),
          if (p.fromExcel && p.supplierName != null && (p.memo ?? '').trim().isNotEmpty) _kv('摘要', p.memo!.trim()),
          _kv('單據', p.photoPath != null ? '有照片' : (p.noReceipt ? '缺憑（沒有單據）' : '沒有照片'),
              color: p.noReceipt ? AppColors.warn : null),
          _kv('核銷', p.reconciled ? '已核銷' : '未核銷'),
          _kv('來源', status, color: p.excelCovered && !p.superseded ? AppColors.warn : null),
          if (why != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(why, style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.45)),
            ),
          const SizedBox(height: 12),
          // 還沒進日報表的 App 進貨：一鍵複製成日報表那一列，不用再打一次
          if (!p.fromExcel && !p.superseded)
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(c, 'copy'),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('複製成日報表那一列'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          if (allowed)
            Row(children: [
              if (!locked)
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(c, 'edit'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('修改'),
                  ),
                ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(c, 'delete'),
                  icon: Icon(Icons.delete_outline, size: 18, color: AppColors.bad),
                  label: Text('刪除', style: TextStyle(color: AppColors.bad)),
                ),
              ),
            ]),
        ]),
      ),
    ),
  );
  if (!context.mounted || act == null) return null;
  if (act == 'copy') {
    await copyDailyReportRow(context, p.purchaseDate, categoryName, p.supplierName ?? '', p.amount);
    return null;
  }
  if (act == 'edit') {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => PurchaseFormScreen(membership: membership, editing: p)));
    return saved == true ? 'edited' : null;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('刪除這筆進貨？'),
      content: Text('${DateFormat('M/d').format(p.purchaseDate)}　$name　${ntd(p.amount)}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.bad),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('刪除'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return null;
  try {
    await repo.deletePurchase(p.id);
    if (!context.mounted) return 'deleted';
    showMessage(context, '已刪除');
    return 'deleted';
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
    return null;
  }
}

/// 進貨頁最上面的「待確認」卡片（只有老闆、店長、而且有東西要看的時候才出現）
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.queue, required this.onTap});
  final List<PurchaseMatch> queue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final un = queue.where((m) => !m.isPair).toList();
    final pairs = queue.where((m) => m.isPair).length;
    final unAmount = un.fold<double>(0, (t, m) => t + m.amount);
    return Material(
      color: AppColors.warn.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.warn.withValues(alpha: 0.45)),
          ),
          child: Row(children: [
            Icon(Icons.rule_folder_outlined, color: AppColors.warn),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('待確認 ${queue.length} 筆', style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (un.isNotEmpty) '日報表沒有的 ${un.length} 筆 ${ntd(unAmount)}（沒有算進合計）',
                    if (pairs > 0) '跟日報表對不太上的 $pairs 筆',
                  ].join('\n'),
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.45),
                ),
              ]),
            ),
            Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}

/// 待確認清單（0104，老闆決定：各店店長每天看；判斷不了的再問老闆）。帳仍然以日報表為準，這裡只是請人看一眼。
class PurchaseMatchScreen extends StatefulWidget {
  const PurchaseMatchScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<PurchaseMatchScreen> createState() => _PurchaseMatchScreenState();
}

class _PurchaseMatchScreenState extends State<PurchaseMatchScreen> {
  Future<List<PurchaseMatch>>? _future;
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<PurchaseMatch>> _load() => AppScope.of(context).repo.purchaseMatchQueue(widget.membership.storeId);

  Future<void> _do(Iterable<String> ids, Future<void> Function() act, String done) async {
    setState(() => _busy.addAll(ids));
    try {
      await act();
      if (!mounted) return;
      showMessage(context, done);
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.removeAll(ids));
    }
  }

  Future<void> _reject(PurchaseMatch m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('不是同一筆？'),
        content: Text('會把 App 這筆「${m.appName}」${ntd(m.amount)} 跟日報表「${m.importName ?? ''}」分開，'
            '幾分鐘內重新比對。\n\n之後如果日報表有另一筆對得上的，會自動改配那一筆；沒有的話，這筆會列在「日報表沒有的」。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('不是同一筆')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = AppScope.of(context).repo;
    await _do([m.appId], () => repo.rejectPurchaseMatch(m.appId), '已送出，幾分鐘內會重新比對');
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    return Scaffold(
      appBar: AppBar(title: const Text('進貨待確認')),
      body: FutureBuilder<List<PurchaseMatch>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorView(message: friendlyError(snap.error!), onRetry: () => setState(() => _future = _load()));
          }
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const <PurchaseMatch>[];
          final un = list.where((m) => !m.isPair).toList();
          final pairs = list.where((m) => m.isPair).toList();
          final easy = pairs.where((m) => m.dateOnly).toList();
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              Text('帳一律以日報表為準。這裡列的是 App 有登記、但跟日報表對不太上的進貨，每天看一下就好。',
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.5)),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Column(children: [
                    Icon(Icons.task_alt, size: 40, color: AppColors.good),
                    const SizedBox(height: 12),
                    const Text('都看完了，沒有要確認的', textAlign: TextAlign.center),
                  ]),
                ),
              if (un.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('日報表沒有的・${un.length} 筆', style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('日報表已經記過那幾天，卻沒有這一筆，所以目前沒有算進成本。漏記的請補進日報表（補了會自動對上）；不用補的按「知道了」。',
                    style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.5)),
                for (final m in un) ...[const SizedBox(height: 10), _unmatched(m, repo)],
              ],
              if (pairs.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('跟日報表對不太上的・${pairs.length} 筆',
                    style: const TextStyle(fontSize: AppType.title, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('金額一樣所以先當成同一筆，但日期、名稱或類別不同。看一下是不是真的同一筆。',
                    style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.5)),
                if (easy.length >= 2) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy.isNotEmpty
                        ? null
                        : () => _do(easy.map((m) => m.appId),
                            () => repo.confirmPurchaseMatches([for (final m in easy) m.appId]), '已確認 ${easy.length} 筆'),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: Text('只差日期的 ${easy.length} 筆，全部是同一筆'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ],
                for (final m in pairs) ...[const SizedBox(height: 10), _pair(m, repo)],
              ],
            ]),
          );
        },
      ),
    );
  }

  Widget _who(PurchaseMatch m) => Text(
        '${m.paidBy == 'petty_cash' ? '零用金' : '月結廠商'}${m.createdName == null ? '' : '・${m.createdName} 登記'}',
        style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
      );

  Widget _side(String tag, DateTime? date, String? name, String? cat, {bool dim = false}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (dim ? AppColors.muted : AppColors.primary).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(tag, style: TextStyle(fontSize: AppType.caption, color: dim ? AppColors.muted : AppColors.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: date == null ? '' : '${DateFormat('M/d').format(date)}　', style: const TextStyle(fontFeatures: tabular)),
              TextSpan(text: (name ?? '').isEmpty ? '（沒寫）' : name, style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: cat == null ? '' : '　$cat', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            ])),
          ),
        ],
      );

  Widget _head(PurchaseMatch m) => Row(children: [
        if (m.photoPath != null) ...[
          PhotoThumb(key: ValueKey(m.photoPath), path: m.photoPath!, size: 44),
          const SizedBox(width: 12),
        ],
        Expanded(child: _who(m)),
        Text(ntd(m.amount),
            style: const TextStyle(fontSize: AppType.heading, fontWeight: AppFont.figure, fontFeatures: tabular)),
      ]);

  Widget _unmatched(PurchaseMatch m, Repository repo) {
    final busy = _busy.contains(m.appId);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _head(m),
        const SizedBox(height: 10),
        _side('App', m.appDate, m.appName, m.appCategory),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => copyDailyReportRow(context, m.appDate, m.appCategory, m.appName, m.amount),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('複製成日報表那一列'),
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => _do([m.appId], () => repo.dismissUnmatchedPurchase(m.appId), '好，這筆不再提醒'),
            child: const Text('知道了'),
          ),
        ]),
      ]),
    );
  }

  Widget _pair(PurchaseMatch m, Repository repo) {
    final busy = _busy.contains(m.appId);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _head(m),
        const SizedBox(height: 10),
        _side('App', m.appDate, m.appName, m.appCategory),
        const SizedBox(height: 8),
        _side('日報表', m.importDate, m.importName, m.importCategory, dim: true),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in m.reasons)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warn.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(r, style: TextStyle(color: AppColors.warn, fontSize: AppType.caption)),
            ),
        ]),
        const SizedBox(height: 4),
        if (m.waiting)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('已經按了「不是同一筆」，幾分鐘內會重新比對', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          )
        else
          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: busy ? null : () => _reject(m),
                child: Text('不是同一筆', style: TextStyle(color: busy ? null : AppColors.bad)),
              ),
            ),
            Expanded(
              child: FilledButton.tonal(
                onPressed: busy ? null : () => _do([m.appId], () => repo.confirmPurchaseMatches([m.appId]), '已確認'),
                child: const Text('是同一筆'),
              ),
            ),
          ]),
        const SizedBox(height: 4),
      ]),
    );
  }
}

/// 依日期看這個月的每一筆（含不計入的 App 進貨），可以篩選；點一筆看內容
class PurchaseListScreen extends StatefulWidget {
  const PurchaseListScreen(
      {super.key, required this.membership, required this.month, required this.items, required this.categoryNames, this.today});
  final Membership membership;
  final DateTime month;
  final List<Purchase> items;
  final Map<String, String> categoryNames;
  final DateTime? today;
  @override
  State<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends State<PurchaseListScreen> {
  late List<Purchase> _items = List.of(widget.items);
  String _filter = 'all';

  static const _filters = [('all', '全部'), ('app', 'App 登記'), ('noreceipt', '缺憑'), ('uncounted', '不計入')];

  bool _match(Purchase p) => switch (_filter) {
        'app' => !p.fromExcel && p.counted,
        'noreceipt' => p.noReceipt,
        'uncounted' => !p.fromExcel && p.excelCovered && !p.superseded,
        // 全部：有算進帳的＋日報表沒有、沒算進去的；已經由日報表同一筆取代的不重複列
        _ => !p.superseded,
      };

  Future<void> _tap(Purchase p) async {
    final r = await purchaseTapped(context, widget.membership, p, widget.categoryNames[p.categoryCode] ?? p.categoryCode);
    if (r == null || !mounted) return;
    try {
      final all = await AppScope.of(context).repo.monthPurchases(widget.membership.storeId, widget.month);
      if (mounted) setState(() => _items = all);
    } catch (_) {
      if (mounted && r == 'deleted') setState(() => _items.removeWhere((x) => x.id == p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _items.where(_match).toList()
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    final days = <DateTime, List<Purchase>>{};
    for (final p in list) {
      days.putIfAbsent(DateTime(p.purchaseDate.year, p.purchaseDate.month, p.purchaseDate.day), () => []).add(p);
    }
    int n(String f) {
      final keep = _filter;
      _filter = f;
      final c = _items.where(_match).length;
      _filter = keep;
      return c;
    }

    return Scaffold(
      appBar: AppBar(
          title: Text('${DateFormat('M 月', 'zh_TW').format(widget.month)}每一筆', style: const TextStyle(fontSize: AppType.title))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in _filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SelectChip(
                    label: Text('${f.$2} ${n(f.$1)}'), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
              ),
          ]),
        ),
        if (_filter == 'uncounted')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('App 有登記，但日報表已經記過那幾天、卻沒有這一筆，所以沒有算進成本。漏記的補進日報表後會自動對上。',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.small, height: 1.5)),
          ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Text('沒有符合的進貨', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ),
        for (final d in days.keys) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              Expanded(
                child: Text(DateFormat('M/d（E）', 'zh_TW').format(d), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text('${days[d]!.length} 筆・${ntd(days[d]!.where((p) => p.counted).fold<double>(0, (t, p) => t + p.amount))}',
                  style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            ]),
          ),
          const SizedBox(height: 8),
          for (final p in days[d]!) ...[
            _PurchaseTile(
              p: p,
              isToday: widget.today != null && isSameDay(p.purchaseDate, widget.today!),
              categoryName: widget.categoryNames[p.categoryCode] ?? p.categoryCode,
              canReconcile: false,
              onToggle: () {},
              onTap: () => _tap(p),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ]),
    );
  }
}
