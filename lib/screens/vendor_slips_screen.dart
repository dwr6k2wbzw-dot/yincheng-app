import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'vendor_slip_edit_screen.dart';

/// 廠商銷貨單明細（隱城、小城外）：依廠商分組，展開後看每張單據的日期、品項、數量、金額。
/// 資料來自 Dropbox「有戲創藝_2026年廠商進貨單」的掃描單據，只能看；不影響成本率（成本率以日報表為準）。
class VendorSlipsScreen extends StatefulWidget {
  const VendorSlipsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<VendorSlipsScreen> createState() => _VendorSlipsScreenState();
}

class _VendorSlipsScreenState extends State<VendorSlipsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<(List<VendorSlip>, List<String>)> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _future = _load();
    }
  }

  Future<(List<VendorSlip>, List<String>)> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final r = await Future.wait([repo.vendorSlips(id, _month), repo.failedSlipFiles(id)]);
    return (r[0] as List<VendorSlip>, r[1] as List<String>);
  }

  void _reload() => setState(() => _future = _load());

  void _shiftMonth(int d) {
    _month = DateTime(_month.year, _month.month + d);
    _reload();
  }

  bool get _canEdit => widget.membership.isManager;

  Future<void> _edit(VendorSlip? s) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => VendorSlipEditScreen(membership: widget.membership, slip: s, month: _month),
    ));
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: _canEdit
            ? FloatingActionButton.extended(
                onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('新增銷貨單'))
            : null,
        body: _body(context),
      );

  Widget _body(BuildContext context) => FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (slips, failed) = snap.data!;
          final byVendor = <String, List<VendorSlip>>{};
          for (final s in slips) {
            byVendor.putIfAbsent(s.vendor, () => []).add(s);
          }
          final drafts = slips.where((s) => s.isDraft).length;
          final vendors = byVendor.entries.toList()
            ..sort((a, b) => _sum(b.value).compareTo(_sum(a.value)));
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              Row(children: [
                IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(DateFormat('yyyy 年 M 月', 'zh_TW').format(_month),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                ),
                IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
              ]),
              const SizedBox(height: 4),
              SectionCard(
                child: Row(children: [
                  const Icon(Icons.receipt_long, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${slips.length} 張銷貨單・${vendors.length} 家廠商',
                        style: const TextStyle(color: AppColors.muted)),
                  ),
                  Text(ntd(_sum(slips)), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ]),
              ),
              if (drafts > 0) ...[
                const SizedBox(height: 8),
                SectionCard(
                  child: Text(
                    '有 $drafts 張文字辨識的草稿待確認${_canEdit ? '：展開廠商、點單據核對修改' : '（老闆或店長核對）'}',
                    style: const TextStyle(color: AppColors.warn, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 8),
                SectionCard(
                  child: Text(
                    '有 ${failed.length} 個單據檔案文字辨識失敗，請手動新增：\n${failed.join('、')}',
                    style: const TextStyle(color: AppColors.warn, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (vendors.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Text('這個月還沒有銷貨單', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ),
              for (final v in vendors) ...[
                _VendorCard(vendor: v.key, slips: v.value, onTap: _canEdit ? _edit : null),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
              const Text(
                '資料來自 Dropbox 廠商進貨單資料夾（各月份資料夾）的掃描單據：新的單據每小時自動文字辨識成草稿，老闆或店長核對修改後確認。'
                '這裡只是明細參考，成本率與進貨金額仍以日報表為準。',
                style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
              ),
            ]),
          );
        },
      );

  static double _sum(List<VendorSlip> s) => s.fold(0.0, (a, x) => a + x.total);
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor, required this.slips, this.onTap});
  final String vendor;
  final List<VendorSlip> slips;
  final void Function(VendorSlip)? onTap;

  @override
  Widget build(BuildContext context) {
    final total = slips.fold(0.0, (a, x) => a + x.total);
    final items = slips.fold(0, (a, x) => a + x.lines.length);
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text(vendor, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          subtitle: Text(
              '${slips.length} 張單・$items 項${slips.any((s) => s.isDraft) ? '・${slips.where((s) => s.isDraft).length} 張草稿' : ''}',
              style: TextStyle(
                  color: slips.any((s) => s.isDraft) ? AppColors.warn : AppColors.muted, fontSize: 12)),
          trailing: Text(ntd(total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          children: [for (final s in slips) _slip(s)],
        ),
      ),
    );
  }

  Widget _slip(VendorSlip s) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: AppColors.cardHigh,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap == null ? null : () => onTap!(s),
            child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: s.isDraft ? Border.all(color: AppColors.warn.withValues(alpha: 0.6)) : null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (s.isDraft)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(onTap == null ? '草稿・待確認' : '草稿・待確認（點一下核對）',
                  style: const TextStyle(color: AppColors.warn, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          Row(children: [
            Text(DateFormat('M/d（E）', 'zh_TW').format(s.date), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('單號 ${s.slipNo}',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
            Text(ntd(s.total), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          if (s.note != null && s.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(s.note!, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
          const SizedBox(height: 6),
          for (final l in s.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.itemName, style: const TextStyle(fontSize: 13)),
                    Text(
                      [
                        if (l.itemCode != null && l.itemCode!.isNotEmpty) l.itemCode!,
                        if (l.unitPrice != null) '單價 ${ntd(l.unitPrice!)}',
                      ].join('・'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  child: Text('${_qty(l.qty)} ${l.unit ?? ''}',
                      textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
                ),
                SizedBox(
                  width: 80,
                  child: Text(ntd(l.amount),
                      textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          if ((s.linesTotal - s.total).abs() > 0.001)
            Text('品項合計 ${ntd(s.linesTotal)}，與單據合計不符',
                style: const TextStyle(color: AppColors.bad, fontSize: 11)),
        ]),
            ),
          ),
        ),
      );

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}
