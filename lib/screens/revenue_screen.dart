import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/revenue_mix.dart';

/// 每日營收：列表＋新增／修改（老闆／店長；資料庫 RLS 也只允許這兩種角色）
class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  late Future<(List<RevenueEntry>, DateTime?)> _future;
  bool _started = false;

  /// 營收以 Dropbox 日報表為準的店：只能看
  bool get _synced => AppConfig.excelSyncedStores.contains(widget.membership.storeName);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load();
  }

  Future<(List<RevenueEntry>, DateTime?)> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final list = await repo.revenueEntries(id);
    final last = _synced ? await repo.lastExcelSync(id) : null;
    return (list, last);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _open({RevenueEntry? entry}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RevenueFormScreen(membership: widget.membership, entry: entry)),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: _synced
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _open(),
                icon: const Icon(Icons.add),
                label: const Text('登記營收'),
              ),
        body: FutureBuilder<(List<RevenueEntry>, DateTime?)>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (list, last) = snap.data!;
            final banner = _synced ? _SyncBanner(last: last) : null;
            if (list.isEmpty) {
              return ListView(padding: const EdgeInsets.all(16), children: [
                if (banner != null) banner,
                const SizedBox(height: 120),
                Text(_synced ? '還沒有同步到營收資料' : '還沒有營收紀錄\n按右下角「登記營收」新增第一天',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              ]);
            }
            final offset = banner == null ? 0 : 1;
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length + offset,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i < offset) return banner!;
                  final e = list[i - offset];
                  return _RevenueTile(e: e, storeName: widget.membership.storeName, onTap: _synced ? null : () => _open(entry: e));
                },
              ),
            );
          },
        ),
      );
}

class _RevenueTile extends StatelessWidget {
  const _RevenueTile({required this.e, required this.onTap, required this.storeName});
  final RevenueEntry e;
  final String storeName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mismatch = (e.received - e.detailTotal).abs() >= 1;
    final multi = isMultiLineStore(storeName);
    // 小城外的客單＝調酒收入 ÷ 來客數（與小城外 Excel 相同）
    final avg = e.guests > 0 ? (multi ? e.drinks + e.food + e.project : e.received) / e.guests : null;
    // 當日占比：分母＝各項合計，與總覽的占比條同一算法
    final parts = revenueParts(storeName,
        drinks: e.drinks, food: e.food, project: e.project, coffee: e.coffee, ramen: e.ramen, deposit: e.deposit);
    final base = parts.fold<double>(0, (a, p) => a + p.amount);
    double share(double v) => base > 0 ? v / base : 0;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SectionCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(DateFormat('M/d（E）', 'zh_TW').format(e.bizDate), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  '${e.guests} 位${avg == null ? '' : '・客單 ${ntd(avg.round())}'}'
                  '${e.source == 'import' ? '・Excel' : '・App'}'
                  '${mismatch ? '・明細不符' : ''}',
                  style: TextStyle(color: mismatch ? AppColors.warn : AppColors.muted, fontSize: 12),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(ntd(e.received), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 2),
              Text('現金 ${ntd(e.cash)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Text('刷卡 ${ntd(e.creditCard + e.amex)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (e.deposit != 0 && !multi)
                Text('訂金 ${ntd(e.deposit)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
            if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
          if (base > 0) ...[
            const SizedBox(height: 10),
            if (multi)
              Wrap(spacing: 12, runSpacing: 4, children: [
                for (final p in parts) _chip(p.label, p.amount, share(p.amount), p.color),
              ])
            else
              Row(children: [
                for (final p in parts) Expanded(child: _chip(p.label, p.amount, share(p.amount), p.color)),
              ]),
            const SizedBox(height: 8),
            MixBar(parts: parts, height: 6, showLegend: false),
          ],
        ]),
      ),
    );
  }

  Widget _chip(String label, double v, double share, Color dot) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 7, color: dot),
        const SizedBox(width: 5),
        Flexible(
          child: Text('$label ${ntd(v)}・${pct(share)}',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ),
      ]);
}

/// 營收由 Dropbox 同步時，列表上方的說明
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.last});
  final DateTime? last;
  @override
  Widget build(BuildContext context) => SectionCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.sync, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('營收由 Dropbox 日報表自動同步', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '每小時檢查一次 Excel，有變動就更新。要修改數字請直接改 Excel。\n'
                '最後一次寫入：${last == null ? '尚無紀錄' : DateFormat('M/d HH:mm').format(last!)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
              ),
            ]),
          ),
        ]),
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
  static const _fields = ['cash', 'card', 'amex', 'deposit', 'guests', 'drinks', 'food', 'project'];
  final _c = {for (final f in _fields) f: TextEditingController()};
  final _note = TextEditingController();
  RevenueEntry? _existing; // 這一天已有的紀錄（修改模式）
  DateTime? _date;
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

  /// 選了日期：那天已有紀錄就帶入（改成修改），沒有就清空
  Future<void> _loadDate(DateTime d) async {
    final e = await AppScope.of(context).repo.revenueEntryFor(widget.membership.storeId, d);
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
    if (mounted) setState(() {});
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
    _note.text = e.note ?? '';
  }

  double _v(String f) => double.tryParse(_c[f]!.text.replaceAll(',', '')) ?? 0;

  RevenueEntry get _draft => RevenueEntry(
        id: _existing?.id,
        bizDate: _date!,
        cash: _v('cash'),
        creditCard: _v('card'),
        amex: _v('amex'),
        deposit: _v('deposit'),
        guests: _v('guests').round(),
        drinks: _v('drinks'),
        food: _v('food'),
        project: _v('project'),
        note: _note.text,
        source: _existing?.source ?? 'app',
      );

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
    final d = _draft;
    if (d.received <= 0) {
      showMessage(context, '請至少填一種收款金額', error: true);
      return;
    }
    if (d.guests <= 0 && !await _confirm('來客數是 0', '客單價會無法計算。確定這天沒有來客嗎？')) return;
    final diff = d.received - d.detailTotal;
    if (diff.abs() >= 1 &&
        !await _confirm('收款與明細不符',
            '收款合計 ${ntd(d.received)}，酒水＋餐食＋專案 ${ntd(d.detailTotal)}，相差 ${ntd(diff)}。\n成本率是用酒水、餐食計算，建議先核對。')) {
      return;
    }
    if (_existing?.source == 'import' &&
        !await _confirm('修改 Excel 匯入的資料',
            '這天是從日報表 Excel 匯入的。在 App 修改後，之後重新匯入 Excel 時會先停下來，避免蓋掉你的修改。')) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).repo.saveRevenueEntry(widget.membership.storeId, d);
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

  Widget _num(String f, String label, {bool money = true}) => TextField(
        controller: _c[f],
        keyboardType: TextInputType.numberWithOptions(decimal: money),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(money ? r'[0-9.,]' : r'[0-9]'))],
        decoration: InputDecoration(labelText: label, prefixText: money ? '\$ ' : null, suffixText: money ? null : '位'),
      );

  Widget _pair(Widget a, Widget b) => Row(children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);

  @override
  Widget build(BuildContext context) {
    final editing = _existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '修改營收' : '登記營收')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!)
              : _form(editing),
    );
  }

  Widget _form(bool editing) {
    final d = _draft;
    final diff = d.received - d.detailTotal;
    final mismatch = diff.abs() >= 1 && d.detailTotal > 0;
    return ListView(padding: const EdgeInsets.all(16), children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event),
        title: const Text('營業日'),
        subtitle: Text(
          editing ? '這天已有紀錄（${_existing!.source == 'import' ? 'Excel 匯入' : 'App 登記'}），儲存會更新' : '凌晨 6 點前算前一個營業日',
          style: TextStyle(fontSize: 12, color: editing ? AppColors.warn : null),
        ),
        trailing: Text(DateFormat('yyyy/M/d（E）', 'zh_TW').format(_date!), style: const TextStyle(fontSize: 16)),
        onTap: widget.entry != null
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
      const _Label('收款方式'),
      _pair(_num('cash', '現金'), _num('card', '信用卡')),
      const SizedBox(height: 12),
      _pair(_num('amex', 'AMEX'), _num('deposit', '訂金')),
      const SizedBox(height: 12),
      _pair(_num('guests', '來客數', money: false), const SizedBox()),
      const SizedBox(height: 20),
      const _Label('營業收入明細'),
      _pair(_num('drinks', '酒水'), _num('food', '餐食')),
      const SizedBox(height: 12),
      _pair(_num('project', '專案'), const SizedBox()),
      const SizedBox(height: 16),
      SectionCard(
        child: Column(children: [
          _sumRow('收款合計', ntd(d.received), bold: true),
          _sumRow('酒水＋餐食＋專案', ntd(d.detailTotal)),
          if (d.guests > 0 && d.received > 0) _sumRow('客單價', ntd((d.received / d.guests).round())),
          if (mismatch) _sumRow('差額', ntd(diff), color: AppColors.warn),
        ]),
      ),
      const SizedBox(height: 12),
      TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: '備註（選填）')),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: _saving
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(editing ? '更新' : '儲存', style: const TextStyle(fontSize: 16)),
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
        child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13, letterSpacing: 0.5)),
      );
}
