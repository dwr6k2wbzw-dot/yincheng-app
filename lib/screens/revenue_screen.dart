import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/item_sections.dart';
import '../widgets/revenue_mix.dart';

/// 每日營收：列表＋手動登記／修改。老闆／店長／正職可手動登記暫記（source=app）；
/// 營收以 Dropbox 日報表為準，匯入同一天會自動覆蓋暫記。Excel 匯入的那筆只有老闆／店長能改。
class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  late Future<(List<RevenueEntry>, DateTime?, Set<DateTime>)> _future;
  /// 已載入的品項（依營業日快取，捲動回來不重抓）
  final _items = <DateTime, Future<List<ItemSale>>>{};
  bool _started = false;

  /// 可手動登記營收：老闆／店長／正職（兼職、調酒師看不到這頁）
  bool get _canWrite => widget.membership.canSeeRevenue;

  /// 這店營收是否由 Dropbox 日報表同步（隱城、小城外都是）
  bool get _excelSynced => AppConfig.excelSyncedStores.contains(widget.membership.storeName);

  /// 能不能點開這一筆：老闆／店長／正職都能點開看；
  /// 能不能「改」由表單判斷（Excel 匯入的那筆正職只能看，見 RevenueFormScreen._readOnly）
  bool _canOpenRow(RevenueEntry e) => _canWrite;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  Future<(List<RevenueEntry>, DateTime?, Set<DateTime>)> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final list = await repo.revenueEntries(id, limit: 120); // 星期平均可看近 12 週
    final last = _excelSynced ? await repo.lastExcelSync(id) : null;
    // iCHEF 沒資料或讀不到（舊資料庫）不影響營收列表
    final ichef = await repo.ichefDays(id).catchError((_) => <DateTime>{});
    return (list, last, ichef);
  }

  Future<List<ItemSale>> _itemsFor(DateTime d) =>
      _items[d] ??= AppScope.of(context).repo.itemSales(widget.membership.storeId, d);

  /// 每次重新載入 +1：月累計卡跟著重新查詢（審查 P2）
  int _version = 0;

  void _reload() => setState(() {
        _items.clear();
        _version++;
        _future = _load();
      });

  Future<void> _open({RevenueEntry? entry}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RevenueFormScreen(membership: widget.membership, entry: entry)),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: !_canWrite
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _open(),
                icon: const Icon(Icons.add),
                label: const Text('登記營收'),
              ),
        body: FutureBuilder<(List<RevenueEntry>, DateTime?, Set<DateTime>)>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (all, last, ichef) = snap.data!;
            // 日報表先打好、還沒營業的日子（例：隱城 11/8 員旅，全是 0）不顯示（老闆 2026-11-05）
            final today = bizToday();
            final list = [
              for (final e in all)
                if (!(e.bizDate.isAfter(today) && e.received == 0 && e.guests == 0 && e.drinks + e.food + e.project + e.coffee + e.ramen == 0)) e
            ];
            final banner = _excelSynced ? _SyncBanner(last: last, canWrite: _canWrite) : null;
            if (list.isEmpty) {
              return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                if (banner != null) banner,
                const SizedBox(height: 120),
                Text(
                    !_canWrite
                        ? '還沒有同步到營收資料'
                        : '還沒有營收紀錄\n按右下角「登記營收」新增第一天',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted)),
              ]);
            }
            // 列表上方：同步說明（若有）＋星期平均
            final headers = <Widget>[
              if (banner != null) banner,
              _WeekdayStats(entries: list, multi: isMultiLineStore(widget.membership.storeName)),
              // 當月銷售品項累計（老闆 2026-11-13）：只算有 iCHEF 的日子，沒有的列「未計入」
              if (ichef.isNotEmpty)
                MonthItemsSection(
                  storeId: widget.membership.storeId,
                  version: _version,
                  load: AppScope.of(context).repo.monthItemSales,
                  entries: list,
                  ichef: ichef,
                  wrap: (child) => SectionCard(child: child),
                ),
            ];
            final offset = headers.length;
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                // 底部留 96：浮動按鈕高 56＋邊距 16，再多一點，捲到底最後一列才不會被蓋住
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length + offset,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i < offset) return headers[i];
                  final e = list[i - offset];
                  final day = DateTime(e.bizDate.year, e.bizDate.month, e.bizDate.day);
                  final fromIchef = ichef.contains(day);
                  return _RevenueTile(
                      e: e,
                      storeName: widget.membership.storeName,
                      ichef: fromIchef,
                      items: fromIchef ? _itemsFor(day) : null,
                      onTap: _canOpenRow(e) ? () => _open(entry: e) : null);
                },
              ),
            );
          },
        ),
      );
}

class _RevenueTile extends StatelessWidget {
  const _RevenueTile({required this.e, required this.onTap, required this.storeName, this.ichef = false, this.items});
  final RevenueEntry e;
  final String storeName;
  final VoidCallback? onTap;
  /// 這天的來客、酒水、餐食、現金、刷卡由 iCHEF 帶入（0096）
  final bool ichef;
  final Future<List<ItemSale>>? items;

  @override
  Widget build(BuildContext context) {
    final multi = isMultiLineStore(storeName);
    // 小城外的客單＝調酒收入 ÷ 來客數（與小城外 Excel 相同）
    final avg = e.guests > 0 ? (multi ? e.drinks + e.food + e.project : e.received) / e.guests : null;
    // 當日占比：分母＝各項合計，與總覽的占比條同一算法
    final parts = revenueParts(storeName,
        drinks: e.drinks, food: e.food, project: e.project, coffee: e.coffee, ramen: e.ramen, deposit: e.deposit);
    final base = parts.fold<double>(0, (a, p) => a + p.amount);
    // 收款合計 vs 明細合計：小城外的明細含訂金，隱城不含（用各組成項加總，依店別）
    final mismatch = (e.received - base).abs() >= 1;
    double share(double v) => base > 0 ? v / base : 0;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 日期放大一級並用主題金色（老闆 2026-11-13），原本是預設 14、白字
                Text(DateFormat('M/d（E）', 'zh_TW').format(e.bizDate),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppType.title, color: AppColors.primary)),
                const SizedBox(height: 4),
                Text(
                  '${e.guests} 位${avg == null ? '' : '・客單 ${ntd(avg.round())}'}'
                  '${ichef ? '・iCHEF' : e.source == 'import' ? '・Excel' : '・App'}'
                  '${mismatch ? '・明細不符' : ''}',
                  style: TextStyle(color: mismatch ? AppColors.warn : AppColors.muted, fontSize: AppType.small),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(ntd(e.received), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppType.title)),
              const SizedBox(height: 2),
              Text('現金 ${ntd(e.cash)}', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              Text('刷卡 ${ntd(e.creditCard + e.amex)}', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
              if (e.deposit != 0 && !multi)
                Text('訂金 ${ntd(e.deposit)}', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            ]),
            if (onTap != null) Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
          if (base > 0) ...[
            const SizedBox(height: 10),
            // 一律用 Wrap：窄螢幕放不下就換行，金額不會被截成「85…」
            Wrap(spacing: 12, runSpacing: 4, children: [
              for (final p in parts) _chip(p.label, p.amount, share(p.amount), p.color),
            ]),
            const SizedBox(height: 8),
            MixBar(parts: parts, height: 6, showLegend: false),
          ],
          if (items != null) _ItemSales(items: items!),
        ]),
      ),
    );
  }

  Widget _chip(String label, double v, double share, Color dot) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 7, color: dot),
        const SizedBox(width: 5),
        Flexible(
          child: Text('$label ${ntd(v)}・${pct(share)}',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppType.small)),
        ),
      ]);
}

/// 星期平均（老闆 2026-10-12）：週一～週日各自的平均營業額、平均來客數、客單價。
/// 營業額＝收款合計（與列表大字相同）；客單＝合計營業額÷合計來客（小城外用調酒收入，與小城外 Excel 相同）。
class _WeekdayStats extends StatefulWidget {
  const _WeekdayStats({required this.entries, required this.multi});
  final List<RevenueEntry> entries;
  final bool multi;
  @override
  State<_WeekdayStats> createState() => _WeekdayStatsState();
}

class _WeekdayStatsState extends State<_WeekdayStats> {
  String _range = '4w'; // month＝本月、4w＝近 4 週、12w＝近 12 週
  static const _ranges = {'month': '本月', '4w': '近 4 週', '12w': '近 12 週'};
  static const _names = ['一', '二', '三', '四', '五', '六', '日'];

  List<RevenueEntry> _pick() {
    final today = bizToday();
    if (_range == 'month') {
      return widget.entries.where((e) => e.bizDate.year == today.year && e.bizDate.month == today.month).toList();
    }
    final days = _range == '4w' ? 28 : 84;
    final from = today.subtract(Duration(days: days));
    return widget.entries.where((e) => e.bizDate.isAfter(from) && !e.bizDate.isAfter(today)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = List.generate(7, (_) => <RevenueEntry>[]);
    for (final e in _pick()) {
      rows[e.bizDate.weekday - 1].add(e);
    }
    final avg = <double?>[];
    for (final r in rows) {
      avg.add(r.isEmpty ? null : r.fold<double>(0, (a, e) => a + e.received) / r.length);
    }
    final best = avg.whereType<double>().fold<double>(0, (a, v) => v > a ? v : a);
    final head = TextStyle(color: AppColors.muted, fontSize: AppType.small);
    const cell = TextStyle(fontSize: AppType.small, fontFeatures: [FontFeature.tabularFigures()]);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('星期平均', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final k in _ranges.keys)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: SelectChip(
                label: Text(_ranges[k]!, style: const TextStyle(fontSize: AppType.small)),
                selected: _range == k,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _range = k),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(width: 44, child: Text('星期', style: head)),
          Expanded(child: Text('平均營業額', textAlign: TextAlign.right, style: head)),
          SizedBox(width: 64, child: Text('來客', textAlign: TextAlign.right, style: head)),
          SizedBox(width: 72, child: Text('客單', textAlign: TextAlign.right, style: head)),
        ]),
        const Divider(height: 12),
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: () {
              final r = rows[i];
              if (r.isEmpty) {
                return Row(children: [
                  SizedBox(width: 44, child: Text('週${_names[i]}', style: cell)),
                  Expanded(child: Text('—', textAlign: TextAlign.right, style: TextStyle(color: AppColors.muted))),
                ]);
              }
              final guests = r.fold<int>(0, (a, e) => a + e.guests);
              final base = r.fold<double>(0, (a, e) => a + (widget.multi ? e.drinks + e.food + e.project : e.received));
              final top = avg[i] == best && best > 0;
              return Row(children: [
                SizedBox(
                  width: 44,
                  child: Text('週${_names[i]}',
                      style: cell.copyWith(fontWeight: top ? FontWeight.w700 : null, color: top ? AppColors.primary : null)),
                ),
                Expanded(
                  child: Text('${ntd(avg[i]!.round())}（${r.length}天）',
                      textAlign: TextAlign.right,
                      style: cell.copyWith(fontWeight: top ? FontWeight.w700 : null, color: top ? AppColors.primary : null)),
                ),
                SizedBox(width: 64, child: Text('${(guests / r.length).toStringAsFixed(1)} 位', textAlign: TextAlign.right, style: cell)),
                SizedBox(
                  width: 72,
                  child: Text(guests > 0 ? ntd((base / guests).round()) : '—', textAlign: TextAlign.right, style: cell),
                ),
              ]);
            }(),
          ),
        const SizedBox(height: 4),
        InfoLine(
          icon: null,
          padding: EdgeInsets.zero,
          text: '粗體是平均最高的那天',
          detail: '平均營業額、來客＝該星期幾每天的平均；客單＝${widget.multi ? '調酒收入' : '營業額'}合計 ÷ 來客合計。',
        ),
      ]),
    );
  }
}

/// 營收由 Dropbox 同步時，列表上方的一行狀態（點 ⓘ 看完整說明）
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.last, required this.canWrite});
  final DateTime? last;
  final bool canWrite;
  @override
  Widget build(BuildContext context) => InfoLine(
        text: '每小時從日報表同步・最後 ${last == null ? '尚無紀錄' : DateFormat('M/d HH:mm').format(last!)}',
        detail: canWrite
            ? '營收以 Dropbox 日報表為準。還沒進日報表的日子可以先手動登記（暫記）；之後日報表匯入同一天時，會自動以日報表為準覆蓋暫記。'
            : '營收以 Dropbox 日報表為準，每小時檢查一次，有變動就更新。',
      );
}

/// 新增／修改一天的營收
class RevenueFormScreen extends StatefulWidget {
  const RevenueFormScreen({super.key, required this.membership, this.entry});
  final Membership membership;
  final RevenueEntry? entry;
  @override
  State<RevenueFormScreen> createState() => _RevenueFormScreenState();
}

class _RevenueFormScreenState extends State<RevenueFormScreen> {
  static const _fields = ['cash', 'card', 'amex', 'deposit', 'guests', 'drinks', 'food', 'project', 'coffee', 'ramen'];
  final _c = {for (final f in _fields) f: TextEditingController()};
  final _note = TextEditingController();
  RevenueEntry? _existing; // 這一天已有的紀錄（修改模式）
  double? _ichefCash; // 小城外這天的 iCHEF 現金（沒有 iCHEF 資料是 null），見 _cashAuto
  String? _ichefError; // 讀 iCHEF 現金失敗（跟「沒有 iCHEF 資料」不同）：不能儲存，要重試
  bool _ichefRetrying = false;
  String? _savedCheck; // 存檔後讀回來，資料庫算出的數字跟畫面不同時的說明
  bool _wrote = false; // 已經寫進資料庫（留在這頁時，離開要通知列表重新載入）
  bool _newRowUnread = false; // 新增成功但沒讀回那筆（不知道 id）：再存前要先讀回，免得再新增一筆撞同日唯一索引
  DateTime? _date;
  int _dayGen = 0; // 每換一次營業日就加 1：換日前送出、換日後才回來的回應一律丟掉，見 _stale
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    for (final c in _c.values) {
      c.addListener(() => setState(() {}));
    }
    _init();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      if (widget.entry != null) {
        _fill(widget.entry!);
        await _loadIchefCash(widget.entry!.bizDate);
      } else {
        final d = await AppScope.of(context).repo.businessDate(widget.membership.storeId);
        await _loadDate(d);
      }
    } catch (e) {
      _error = friendlyError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 送出請求後營業日換了（或頁面關了）：回來的是舊回應，不能套到現在畫面上
  bool _stale(int gen) => !mounted || gen != _dayGen;

  /// 選了日期：那天已有紀錄就帶入（改成修改），沒有就清空
  Future<void> _loadDate(DateTime d) async {
    final gen = ++_dayGen;
    _savedCheck = null;
    final e = await AppScope.of(context).repo.revenueEntryFor(widget.membership.storeId, d);
    if (_stale(gen)) return;
    _newRowUnread = false;
    if (e != null) {
      _fill(e);
    } else {
      _existing = null;
      _date = d;
      for (final c in _c.values) {
        c.text = '';
      }
      _note.text = '';
    }
    await _loadIchefCash(d);
    if (mounted) setState(() {});
  }

  /// 只有小城外需要：有 iCHEF 的日子現金自動算。
  /// 沒有 iCHEF 資料（null）→ 照舊手動填；讀取失敗 → 記下錯誤、暫停儲存，避免把錯的現金存進去
  /// 讀完才換掉舊值：重試讀取中畫面仍維持「讀不到」（不會短暫變成手動填現金）
  Future<void> _loadIchefCash(DateTime d) async {
    final gen = _dayGen;
    double? cash;
    String? error;
    if (_multi && mounted) {
      final repo = AppScope.of(context).repo;
      try {
        cash = await repo.ichefCash(widget.membership.storeId, d);
      } catch (e) {
        error = friendlyError(e);
      }
    }
    if (_stale(gen)) return;
    _ichefCash = cash;
    _ichefError = error;
  }

  /// 重試讀取中（_ichefRetrying）不能儲存，見 _save 與儲存鈕
  Future<void> _retryIchef() async {
    setState(() => _ichefRetrying = true);
    await _loadIchefCash(_date!);
    if (mounted) setState(() => _ichefRetrying = false);
  }

  void _fill(RevenueEntry e) {
    String t(num v) => v == 0 ? '' : NumberFormat('0.##').format(v);
    _existing = e;
    _date = e.bizDate;
    _c['cash']!.text = t(e.cash);
    _c['card']!.text = t(e.creditCard);
    _c['amex']!.text = t(e.amex);
    _c['deposit']!.text = t(e.deposit);
    _c['guests']!.text = t(e.guests);
    _c['drinks']!.text = t(e.drinks);
    _c['food']!.text = t(e.food);
    _c['project']!.text = t(e.project);
    _c['coffee']!.text = t(e.coffee);
    _c['ramen']!.text = t(e.ramen);
    _note.text = e.note ?? '';
  }

  bool get _multi => isMultiLineStore(widget.membership.storeName);

  /// Excel 匯入的那筆，只有老闆／店長能改；正職打開只能看
  bool get _readOnly => _existing?.source == 'import' && !widget.membership.isManager;

  /// 小城外有 iCHEF 的日子：現金＝iCHEF 現金＋咖啡＋拉麵（老闆 2026-11-14），不用手動填。
  /// 資料庫 0096 每次寫入都從 iCHEF 現金重算，所以重存、改、清空咖啡拉麵都不會重複加
  bool get _cashAuto => _ichefCash != null;

  double _v(String f) => double.tryParse(_c[f]!.text.replaceAll(',', '')) ?? 0;

  RevenueEntry get _draft => RevenueEntry(
        id: _existing?.id,
        bizDate: _date!,
        cash: _cashAuto ? _ichefCash! + _v('coffee') + _v('ramen') : _v('cash'),
        creditCard: _v('card'),
        amex: _v('amex'),
        deposit: _v('deposit'),
        guests: _v('guests').round(),
        drinks: _v('drinks'),
        food: _v('food'),
        project: _v('project'),
        coffee: _v('coffee'),
        ramen: _v('ramen'),
        note: _note.text,
        source: _existing?.source ?? 'app',
      );

  /// 明細合計（依店別；小城外含訂金，隱城不含）＝各組成項加總
  double _detailOf(RevenueEntry d) => revenueParts(widget.membership.storeName,
          drinks: d.drinks, food: d.food, project: d.project, coffee: d.coffee, ramen: d.ramen, deposit: d.deposit)
      .fold<double>(0, (a, p) => a + p.amount);

  /// 客單價（小城外＝調酒收入÷來客數；其他＝收款合計÷來客數，與列表、總覽一致）
  int? _avgOf(RevenueEntry d) =>
      d.guests > 0 ? ((_multi ? d.drinks + d.food + d.project : d.received) / d.guests).round() : null;

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('回去修改')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('仍要儲存')),
          ],
        ),
      ) ??
      false;

  Future<void> _save() async {
    if (_ichefRetrying) {
      showMessage(context, '正在重新讀取 iCHEF 現金，請稍候', error: true);
      return;
    }
    if (_ichefError != null) {
      showMessage(context, '還沒讀到這天的 iCHEF 現金，請先按「重試」', error: true);
      return;
    }
    final gen = _dayGen;
    if (_newRowUnread && !await _rereadNewRow()) return;
    if (!mounted || _stale(gen)) return;
    final d = _draft;
    if (d.received <= 0) {
      showMessage(context, '請至少填一種收款金額', error: true);
      return;
    }
    if (d.guests <= 0 && !await _confirm('來客數是 0', '客單價會無法計算。確定這天沒有來客嗎？')) return;
    final detail = _detailOf(d);
    final diff = d.received - detail;
    if (diff.abs() >= 1 &&
        !await _confirm('收款與明細不符',
            '收款合計 ${ntd(d.received)}，明細合計 ${ntd(detail)}，相差 ${ntd(diff)}。\n成本率是用營業收入明細計算，建議先核對。')) {
      return;
    }
    if (_existing?.source == 'import' &&
        !await _confirm('修改 Excel 匯入的資料',
            '這天是從日報表 Excel 匯入的。在 App 修改後，之後重新匯入 Excel 時會先停下來，避免蓋掉你的修改。')) {
      return;
    }
    if (!mounted || _stale(gen)) return;
    setState(() => _saving = true);
    try {
      final repo = AppScope.of(context).repo;
      await repo.saveRevenueEntry(widget.membership.storeId, d);
      _wrote = true;
      if (_stale(gen)) return;
      _newRowUnread = d.id == null;
      // 小城外：資料庫寫入時會依 iCHEF 重算現金、刷卡（0096），讀回來確認實際存進去的數字
      if (_multi && await _checkSaved(repo, d)) return;
      if (mounted) {
        showMessage(context, _existing == null ? '已登記' : '已更新');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 讀回存檔結果；現金或刷卡跟畫面不同（例如存檔前 iCHEF 剛更新）就留在這頁顯示實際數字，回傳 true
  Future<bool> _checkSaved(Repository repo, RevenueEntry d) async {
    final gen = _dayGen;
    RevenueEntry? saved;
    try {
      saved = await repo.revenueEntryFor(widget.membership.storeId, d.bizDate);
      if (_stale(gen)) return true;
      if (saved != null && !DateUtils.isSameDay(saved.bizDate, d.bizDate)) throw StateError('讀回的營業日不同');
      if (saved != null) _newRowUnread = false;
    } catch (_) {
      if (mounted) setState(() => _savedCheck = '已儲存，但讀不回存檔結果，請回營收列表確認這天的現金。');
      return true;
    }
    if (saved != null && (saved.cash - d.cash).abs() < 0.5 && (saved.creditCard - d.creditCard).abs() < 0.5) {
      return false;
    }
    if (!mounted) return true;
    if (saved != null) {
      _fill(saved);
      await _loadIchefCash(saved.bizDate);
    }
    if (!mounted) return true;
    setState(() => _savedCheck = saved == null
        ? '已儲存，但讀不到這天的紀錄，請回營收列表確認。'
        : '已儲存。資料庫依 iCHEF 算出的是現金 ${ntd(saved.cash)}、刷卡 ${ntd(saved.creditCard)}'
            '（畫面原本是 ${ntd(d.cash)}、${ntd(d.creditCard)}），畫面已換成存進去的數字，請確認。');
    return true;
  }

  /// 剛新增的那筆沒讀回來：先讀回取得 id（只記下那筆，不改畫面上的數字），之後改成更新而不是再新增。
  /// 讀不到就不存，回傳 false
  Future<bool> _rereadNewRow() async {
    final gen = _dayGen;
    final day = _date!;
    setState(() => _saving = true);
    try {
      final e = await AppScope.of(context).repo.revenueEntryFor(widget.membership.storeId, day);
      if (_stale(gen)) return false;
      if (e != null && !DateUtils.isSameDay(e.bizDate, day)) throw StateError('讀回的營業日不同');
      if (e != null) _existing = e;
      _newRowUnread = false;
      return true;
    } catch (e) {
      if (mounted) showMessage(context, '讀不回剛才存的紀錄（${friendlyError(e)}），請稍後再試，避免重複新增', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _num(String f, String label, {bool money = true}) => TextField(
        controller: _c[f],
        enabled: !_readOnly,
        keyboardType: TextInputType.numberWithOptions(decimal: money),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(money ? r'[0-9.,]' : r'[0-9]'))],
        decoration: InputDecoration(labelText: label, prefixText: money ? '\$ ' : null, suffixText: money ? null : '位'),
      );

  /// 自動算的現金：只顯示，不能改
  Widget _autoCash(double cash) => InputDecorator(
        key: const Key('auto-cash'),
        decoration: const InputDecoration(labelText: '現金（自動）', prefixText: '\$ ', enabled: false),
        child: Text(NumberFormat('#,##0.##').format(cash)),
      );

  Widget _pair(Widget a, Widget b) => Row(children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);

  @override
  Widget build(BuildContext context) {
    final editing = _existing != null;
    // 已寫入但留在這頁（讀回不同或讀回失敗）：離開時一樣回傳 true，讓列表重新載入
    // 儲存／讀回中不能離開：等結果回來，才知道列表要不要重新載入
    return PopScope<bool>(
      canPop: !_wrote && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_saving) {
          showMessage(context, '正在儲存，請稍候', error: true);
        } else {
          Navigator.pop(context, true);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(editing ? '修改營收' : '登記營收')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: _error!)
                : _form(editing),
      ),
    );
  }

  Widget _form(bool editing) {
    final d = _draft;
    final detail = _detailOf(d);
    final diff = d.received - detail;
    final mismatch = diff.abs() >= 1 && detail > 0;
    final avg = _avgOf(d);
    return ListView(padding: const EdgeInsets.all(16), children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event),
        title: const Text('營業日'),
        subtitle: Text(
          editing ? '這天已有紀錄（${_existing!.source == 'import' ? 'Excel 匯入' : 'App 登記'}），儲存會更新' : '凌晨 6 點前算前一個營業日',
          style: TextStyle(fontSize: AppType.small, color: editing ? AppColors.warn : null),
        ),
        trailing: Text(DateFormat('yyyy/M/d（E）', 'zh_TW').format(_date!), style: const TextStyle(fontSize: AppType.title)),
        // 儲存、讀回、重試 iCHEF 中不能換日：回應回來時要對得上同一天
        onTap: widget.entry != null || _saving || _ichefRetrying
            ? null
            : () async {
                final p = await showDatePicker(
                  context: context,
                  initialDate: _date!,
                  firstDate: DateTime(2025),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (p != null) {
                  setState(() => _loading = true);
                  try {
                    await _loadDate(p);
                  } catch (e) {
                    if (mounted) showMessage(context, friendlyError(e), error: true);
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                }
              },
      ),
      const SizedBox(height: 8),
      if (_readOnly)
        SectionCard(
          child: Row(children: [
            Icon(Icons.lock_outline, color: AppColors.muted, size: 20),
            SizedBox(width: 10),
            Expanded(child: Text('這天是從日報表 Excel 匯入的，只有老闆／店長能修改。', style: TextStyle(fontSize: AppType.small))),
          ]),
        )
      else if (!editing)
        SectionCard(
          child: Row(children: [
            Icon(Icons.info_outline, color: AppColors.primary, size: 20),
            SizedBox(width: 10),
            Expanded(
                child: Text('手動登記是「暫記」，之後日報表匯入同一天時，會自動以日報表為準覆蓋這筆。',
                    style: TextStyle(fontSize: AppType.small))),
          ]),
        ),
      if (_savedCheck != null) ...[
        const SizedBox(height: 8),
        SectionCard(
          key: const Key('saved-check'),
          child: Row(children: [
            Icon(Icons.fact_check_outlined, color: AppColors.warn, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(_savedCheck!, style: const TextStyle(fontSize: AppType.small))),
          ]),
        ),
      ],
      if (_ichefError != null && !_readOnly) ...[
        const SizedBox(height: 8),
        SectionCard(
          key: const Key('ichef-error'),
          child: Row(children: [
            Icon(Icons.error_outline, color: AppColors.bad, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text('讀不到這天的 iCHEF 現金（$_ichefError），先暫停儲存，避免現金算錯。',
                    style: const TextStyle(fontSize: AppType.small))),
            TextButton(onPressed: _ichefRetrying || _saving ? null : _retryIchef, child: const Text('重試')),
          ]),
        ),
      ],
      if (_cashAuto && !_readOnly) ...[
        const SizedBox(height: 8),
        SectionCard(
          child: Row(children: [
            Icon(Icons.auto_awesome_outlined, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text('這天有 iCHEF 資料：現金會自動算成 iCHEF 現金 ${ntd(_ichefCash!)}＋咖啡＋拉麵，只要填咖啡、拉麵。',
                    style: const TextStyle(fontSize: AppType.small))),
          ]),
        ),
      ],
      const SizedBox(height: 8),
      const _Label('收款方式'),
      _pair(_cashAuto ? _autoCash(d.cash) : _num('cash', '現金'), _num('card', '信用卡')),
      const SizedBox(height: 12),
      _pair(_num('amex', 'AMEX'), _num('deposit', '訂金')),
      const SizedBox(height: 12),
      _pair(_num('guests', '來客數', money: false), const SizedBox()),
      const SizedBox(height: 20),
      const _Label('營業收入明細'),
      if (_multi) ...[
        _pair(_num('coffee', '咖啡'), _num('drinks', '酒水')),
        const SizedBox(height: 12),
        _pair(_num('food', '餐食'), _num('ramen', '拉麵')),
      ] else ...[
        _pair(_num('drinks', '酒水'), _num('food', '餐食')),
        const SizedBox(height: 12),
        _pair(_num('project', '專案'), const SizedBox()),
      ],
      const SizedBox(height: 16),
      SectionCard(
        child: Column(children: [
          _sumRow('收款合計', ntd(d.received), bold: true),
          _sumRow('明細合計', ntd(detail)),
          if (avg != null && d.received > 0) _sumRow(_multi ? '客單（調酒）' : '客單價', ntd(avg)),
          if (mismatch) _sumRow('差額', ntd(diff), color: AppColors.warn),
        ]),
      ),
      const SizedBox(height: 12),
      TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: '備註（選填）')),
      const SizedBox(height: 24),
      if (!_readOnly)
        FilledButton(
          onPressed: _saving || _ichefRetrying || _ichefError != null ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(editing ? '更新' : '儲存', style: const TextStyle(fontSize: AppType.title)),
        ),
    ]);
  }

  Widget _sumRow(String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(k, style: TextStyle(color: color ?? AppColors.muted)),
          const Spacer(),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color, fontSize: bold ? 18 : 14)),
        ]),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(color: AppColors.muted, fontSize: AppType.small, letterSpacing: 0.5)),
      );
}

/// 每日營收卡片裡的品項銷售（畫面在 item_sections.dart 的 DayItemsBlock，測試得到）
class _ItemSales extends StatelessWidget {
  const _ItemSales({required this.items});
  final Future<List<ItemSale>> items;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ItemSale>>(
        future: items,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null || list.isEmpty) return const SizedBox.shrink();
          return DayItemsBlock(items: list);
        },
      );
}
