import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'vendor_slip_edit_screen.dart';

/// 廠商銷貨單明細（隱城、小城外）：依當初新增進貨的付款方式分月結銷貨單／零用金發票・收據（老闆 2026-10-12），
/// 展開後看每張單據的廠商、日期、品項、金額。資料以「新增進貨」拍的送貨單照片為主（不再讀 Dropbox）；
/// 只是明細參考，不影響成本率（成本率以日報表為準）。
class VendorSlipsScreen extends StatefulWidget {
  const VendorSlipsScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<VendorSlipsScreen> createState() => _VendorSlipsScreenState();
}

class _VendorSlipsScreenState extends State<VendorSlipsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<(List<VendorSlip>, List<String>, Map<String, CostCategory>)> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _future = _load();
    }
  }

  Future<(List<VendorSlip>, List<String>, Map<String, CostCategory>)> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final r = await Future.wait([repo.vendorSlips(id, _month), repo.failedSlipFiles(id), repo.costCategories()]);
    final cats = {for (final c in r[2] as List<CostCategory>) c.code: c};
    return (r[0] as List<VendorSlip>, r[1] as List<String>, cats);
  }

  void _reload() => setState(() => _future = _load());

  void _shiftMonth(int d) {
    _month = DateTime(_month.year, _month.month + d);
    _reload();
  }

  bool get _canEdit => widget.membership.isManager;

  static List<VendorSlip> _newestFirst(List<VendorSlip> list) {
    final idx = {for (var i = 0; i < list.length; i++) list[i]: i};
    return [...list]..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : idx[b]!.compareTo(idx[a]!);
      });
  }

  Future<void> _edit(VendorSlip? s) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => VendorSlipEditScreen(membership: widget.membership, slip: s, month: _month),
    ));
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        // 手動新增銷貨單已移除（老闆 2026-10-14）：銷貨單只從「新增進貨」拍的照片自動建立；既有的仍可點進去核對、修改
        body: _body(context),
      );

  Widget _body(BuildContext context) => FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (slips, _, _) = snap.data!;
          // 依付款方式分組：月結廠商→月結銷貨單、零用金→零用金發票／收據；對不到進貨的歸月結銷貨單
          final byGroup = <String, List<VendorSlip>>{};
          for (final s in slips) {
            byGroup.putIfAbsent(slipGroupOf(s.paidBy), () => []).add(s);
          }
          final groups = [
            for (final g in slipGroups)
              // 最新的在最上面（老闆 2026-10-14）；同一天依原本順序倒過來（後建立的在上）
              if (byGroup[g] != null) MapEntry(g, _newestFirst(byGroup[g]!))
          ];
          // 例：「・月結銷貨單 $8,630・零用金發票／收據 $500」（各組加起來＝總額）
          final summary = [
            for (final g in slipGroups)
              if (byGroup[g] != null) '・$g ${ntd(_sum(byGroup[g]!))}'
          ].join();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              Row(children: [
                IconButton(tooltip: '上個月', onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(DateFormat('yyyy 年 M 月', 'zh_TW').format(_month),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: AppType.title)),
                ),
                IconButton(tooltip: '下個月', onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
              ]),
              const SizedBox(height: 4),
              SectionCard(
                child: Row(children: [
                  Icon(Icons.receipt_long, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${slips.length} 張銷貨單$summary', style: TextStyle(color: AppColors.muted)),
                  ),
                  Text(ntd(_sum(slips)), style: const TextStyle(fontSize: AppType.heading, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 12),
              if (groups.isEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Text('這個月還沒有銷貨單', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ),
              for (final g in groups) ...[
                _VendorCard(
                    vendor: g.key,
                    slips: g.value,
                    showVendor: true,
                    onTap: _canEdit ? _edit : null,
                    onPhoto: (p) => showStoragePhoto(context, p)),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
              Text(
                '資料來自「新增進貨」時拍的送貨單照片，存檔時自動建立；依新增進貨的付款方式分「月結銷貨單」與「零用金發票／收據」。'
                '點照片可放大；照片上傳 2 個月後自動刪除。'
                '這裡只是明細參考，成本率與進貨金額仍以日報表為準。',
                style: TextStyle(color: AppColors.muted, fontSize: AppType.caption, height: 1.5),
              ),
            ]),
          );
        },
      );

  static double _sum(List<VendorSlip> s) => s.fold(0.0, (a, x) => a + x.total);
}

class _VendorCard extends StatelessWidget {
  const _VendorCard(
      {required this.vendor, required this.slips, this.onTap, required this.onPhoto, this.showVendor = false});
  final String vendor;
  final bool showVendor; // 分組不是依廠商時，每張單據顯示廠商名稱
  final List<VendorSlip> slips;
  final void Function(VendorSlip)? onTap;
  final void Function(String path) onPhoto;

  @override
  Widget build(BuildContext context) {
    final total = slips.fold(0.0, (a, x) => a + x.total);
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text(vendor, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppType.title)),
          subtitle: Text('${slips.length} 張', style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          trailing: Text(ntd(total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppType.title)),
          children: [for (final s in slips) _slip(s)],
        ),
      ),
    );
  }

  // 每張單只顯示：照片、日期、廠商／品項、金額（老闆 2026-10-12）
  Widget _slip(VendorSlip s) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: AppColors.cardHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap == null ? null : () => onTap!(s),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                if (s.photoPath != null) ...[
                  _PhotoThumb(path: s.photoPath!, onTap: () => onPhoto(s.photoPath!)),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(DateFormat('M/d（E）', 'zh_TW').format(s.date),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_itemText(s),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                    // 月結銷貨單顯示填表人、零用金發票／收據顯示請款人（新增進貨時填的那一欄）
                    Text('${s.paidBy == 'petty_cash' ? '請款人' : '填表人'}：${s.filer ?? '未填'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(ntd(s.total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppType.body)),
              ]),
            ),
          ),
        ),
      );

  /// 廠商／品項：新增進貨填的那一欄；手動單有品項明細時接在後面
  static String _itemText(VendorSlip s) {
    final items = s.lines.map((l) => l.itemName.trim()).where((n) => n.isNotEmpty).toList();
    return items.isEmpty ? s.vendor : '${s.vendor}：${items.join('、')}';
  }

}

/// 送貨單照片縮圖：點一下放大；照片已刪除或載入失敗就顯示圖示
class _PhotoThumb extends StatefulWidget {
  const _PhotoThumb({required this.path, required this.onTap});
  final String path;
  final VoidCallback onTap;
  @override
  State<_PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<_PhotoThumb> {
  Future<String>? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _url ??= AppScope.of(context).repo.shiftPhotoUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    Widget placeholder(IconData icon) => Container(
          width: size,
          height: size,
          color: AppColors.card,
          child: Icon(icon, color: AppColors.muted, size: 22),
        );
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: FutureBuilder<String>(
          future: _url,
          builder: (context, snap) {
            if (snap.hasError) return placeholder(Icons.image_not_supported_outlined);
            if (!snap.hasData) return placeholder(Icons.image_outlined);
            return Image.network(snap.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: 168,
                errorBuilder: (_, __, ___) => placeholder(Icons.image_not_supported_outlined));
          },
        ),
      ),
    );
  }
}
