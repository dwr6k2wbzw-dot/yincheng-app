import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../data/booking_import.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/file_pick.dart';
import '../services/pl_export.dart' as pl;
import '../services/reservation_xlsx.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 訂位搬家（ops 0148，公版階段 2 第 6 步；老闆、店長）：
/// 舊系統的未來訂位一次匯進來（先預覽、整批檢查、可以整批復原），以及匯出全部訂位。
class BookingImportScreen extends StatefulWidget {
  const BookingImportScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<BookingImportScreen> createState() => _BookingImportScreenState();
}

class _BookingImportScreenState extends State<BookingImportScreen> {
  static const _previewMax = 50, _issueMax = 100;
  String? _fileName;
  List<ImportRow> _rows = const [];
  String _requestId = const Uuid().v4();
  ImportResult? _preview;
  // 狀態欄分出來的列（不送資料庫，預覽、結果裡一起列）
  List<ImportIssue> _localSkipped = const [], _localErrors = const [];
  String? _fileProblem;
  ImportResult? _done;
  bool _busy = false, _exporting = false, _changed = false;
  String? _error;
  List<ImportBatch>? _batches;
  String? _undoing;

  Repository get _repo => AppScope.of(context).repo;
  String get _store => widget.membership.storeId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_batches == null) _loadBatches();
  }

  Future<void> _loadBatches() async {
    try {
      final b = await _repo.reservationImports(_store);
      if (mounted) setState(() => _batches = b);
    } catch (e) {
      if (mounted) setState(() => _batches = const []);
    }
  }

  Future<void> _template() async {
    try {
      const name = '訂位匯入範本.xlsx';
      final r =
          await pl.saveFile(buildImportTemplate(), name, reservationXlsxMime);
      if (mounted && r == 'downloaded') showMessage(context, '已下載 $name');
    } catch (e) {
      if (mounted) {
        showMessage(context, '下載失敗：${friendlyError(e)}', error: true);
      }
    }
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    PickedFile? f;
    try {
      f = await pickFile(
          '.xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
      return;
    }
    if (f == null || !mounted) return;
    final name = f.name;
    setState(() {
      _busy = true;
      _fileName = name;
      _preview = null;
      _done = null;
      _fileProblem = null;
      _rows = const [];
      _requestId = const Uuid().v4(); // 新的檔案＝新的一批
    });
    try {
      final lower = name.toLowerCase();
      final List<List<String>> cells;
      if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
        cells = parseCsv(decodeCsvBytes(f.bytes));
      } else if (lower.endsWith('.xlsx')) {
        final x = readXlsxCells(f.bytes);
        if (x.problem != null) {
          setState(() => _fileProblem = x.problem);
          return;
        }
        cells = x.cells;
      } else {
        throw const FormatException(
            '只看得懂 Excel（.xlsx）或 CSV 檔；舊的 .xls 請先另存成 .xlsx');
      }
      final t = readImportTable(cells);
      if (t.problem != null) {
        setState(() => _fileProblem = t.problem);
        return;
      }
      if (t.rows.length > 2000) {
        setState(() =>
            _fileProblem = '這個檔案有 ${t.rows.length} 筆，一次最多 2000 筆，請分成幾個檔案');
        return;
      }
      // 狀態欄是已取消、未到、已到店的列、看不懂的狀態：App 讀檔時就分出來，不送資料庫
      final p = t.rows.isEmpty
          ? const ImportResult()
          : await _repo.previewReservationImport(_store, t.rows);
      if (!mounted) return;
      setState(() {
        _rows = t.rows;
        _localSkipped = t.skipped;
        _localErrors = t.errors;
        _preview = p.withLocal(t.skipped, t.errors);
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _fileProblem = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final p = _preview;
    if (p == null || p.errors.isNotEmpty || p.ready == 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r =
          await _repo.importReservations(_store, _rows, _fileName, _requestId);
      if (!mounted) return;
      if (r.errors.isNotEmpty) {
        // 預覽之後有人新增了同一筆、或日期剛好過了午夜：照新的結果再給老闆看一次
        setState(() => _preview = r.withLocal(_localSkipped, _localErrors));
        return;
      }
      setState(() {
        _done = r.withLocal(_localSkipped, const []);
        _preview = null;
        _rows = const [];
        _changed = true;
      });
      showMessage(context, r.repeat ? '這個檔案剛剛已經匯入過了' : '已匯入 ${r.inserted} 筆訂位');
      _loadBatches();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(ImportBatch b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('整批復原？'),
        content: Text(
            '這一批匯入的 ${b.inserted} 筆裡，今天以後、還是「已確認」的會改成「已取消」並隱藏，不會寄信給客人。\n已經到店、未到、過去日子的不會動。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.bad, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('整批復原'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _undoing = b.id);
    try {
      final n = await _repo.undoReservationImport(b.id);
      if (!mounted) return;
      _changed = true;
      showMessage(context, '已復原，取消了 $n 筆');
      await _loadBatches();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _undoing = null);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final rows = await _repo.allReservations(_store);
      final name = reservationsXlsxName(widget.membership.storeName);
      final r = await pl.saveFile(
          buildReservationsXlsx(widget.membership.storeName, rows),
          name,
          reservationXlsxMime);
      if (mounted && r == 'downloaded') {
        showMessage(context, '已下載 $name（${rows.length} 筆）');
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, '匯出失敗：${friendlyError(e)}', error: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('匯入、匯出訂位')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _importCard(),
              const SizedBox(height: 24),
              _label('匯入紀錄'),
              const SizedBox(height: 8),
              _batchList(),
              const SizedBox(height: 24),
              _label('匯出'),
              const SizedBox(height: 8),
              _exportCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(
          color: AppColors.muted,
          fontSize: AppType.small,
          fontWeight: AppFont.label));

  Widget _importCard() => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('從舊系統搬過來',
              style: TextStyle(
                  fontSize: AppType.title, fontWeight: AppFont.heading)),
          const SizedBox(height: 6),
          Text('已經訂好的未來訂位一次帶進來。不寄信給客人、不算線上名額，重複的會自動略過。',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                  height: 1.5)),
          const SizedBox(height: 14),
          _step('1', '下載範本填好，或用舊系統匯出的 Excel／CSV（第一列要有日期、時間、人數、姓名）'),
          _step('2', '選檔案，先看預覽，這時候還不會寫進去'),
          _step('3', '沒問題就確認匯入；匯錯了可以整批復原'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _template,
                icon: const Icon(Icons.download_outlined, size: 20),
                label: const Text('下載範本'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.upload_file_outlined, size: 20),
                label: Text(_fileName == null ? '選擇檔案' : '換一個檔案'),
              ),
            ),
          ]),
          if (_busy) ...[
            const SizedBox(height: 16),
            Row(children: [
              SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary)),
              const SizedBox(width: 10),
              Text(_preview == null ? '正在檢查每一列…' : '正在匯入…',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: AppType.small)),
            ]),
          ],
          if (_fileProblem != null) ...[
            const SizedBox(height: 16),
            _notice(Icons.error_outline, AppColors.bad,
                '${_fileName ?? ''} 看不懂', _fileProblem!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style:
                    TextStyle(color: AppColors.bad, fontSize: AppType.small)),
          ],
          if (_done != null && !_busy) ...[
            const SizedBox(height: 16),
            _notice(
                Icons.check_circle_outline,
                AppColors.good,
                '已匯入 ${_done!.inserted} 筆',
                _done!.skipped.isEmpty
                    ? '在訂位管理照日期就看得到。'
                    : '另外略過 ${_done!.skipped.length} 筆（重複或不是有效訂位）。在訂位管理照日期就看得到。'),
          ],
          if (_preview != null && !_busy) ..._previewBlock(_preview!),
        ]),
      );

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line)),
            child: Text(n,
                style: TextStyle(
                    fontSize: AppType.caption,
                    color: AppColors.muted,
                    fontFeatures: tabular)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style:
                      const TextStyle(fontSize: AppType.small, height: 1.45))),
        ]),
      );

  Widget _notice(IconData icon, Color color, String title, String body) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(fontWeight: AppFont.heading, color: color)),
              const SizedBox(height: 2),
              Text(body,
                  style:
                      const TextStyle(fontSize: AppType.small, height: 1.45)),
            ]),
          ),
        ]),
      );

  List<Widget> _previewBlock(ImportResult p) {
    final bad = {for (final e in p.errors) e.line};
    final skip = {for (final e in p.skipped) e.line};
    final ok = [
      for (final r in _rows)
        if (!bad.contains(r.line) && !skip.contains(r.line)) r
    ];
    final hasErrors = p.errors.isNotEmpty;
    return [
      const SizedBox(height: 18),
      Divider(height: 1, color: AppColors.line),
      const SizedBox(height: 14),
      Text(_fileName ?? '',
          style: TextStyle(color: AppColors.muted, fontSize: AppType.caption),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      const SizedBox(height: 8),
      Row(children: [
        _count('可以匯入', p.ready, AppColors.good),
        _count('略過', p.skipped.length, AppColors.muted),
        _count('有問題', p.errors.length,
            p.errors.isEmpty ? AppColors.muted : AppColors.bad),
      ]),
      if (hasErrors) ...[
        const SizedBox(height: 14),
        Text('有問題的列：改好檔案後再選一次（整個檔案都還沒匯入）',
            style: TextStyle(
                color: AppColors.bad,
                fontSize: AppType.small,
                fontWeight: AppFont.label)),
        const SizedBox(height: 6),
        ..._issues(p.errors, AppColors.bad),
      ],
      if (p.skipped.isNotEmpty) ...[
        const SizedBox(height: 10),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text('略過的 ${p.skipped.length} 列（已經有了、或不是有效訂位）',
                style:
                    TextStyle(color: AppColors.muted, fontSize: AppType.small)),
            children: _issues(p.skipped, AppColors.muted),
          ),
        ),
      ],
      if (!hasErrors && ok.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
            ok.length > _previewMax
                ? '前 $_previewMax 筆（共 ${ok.length} 筆）'
                : '會匯入的訂位',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
        const SizedBox(height: 6),
        for (final r in ok.take(_previewMax)) _okRow(r),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: hasErrors || p.ready == 0 || _busy ? null : _import,
          child: Text(hasErrors
              ? '有 ${p.errors.length} 列要先改好'
              : p.ready == 0
                  ? '沒有要匯入的（全部都已經有了）'
                  : '確認匯入 ${p.ready} 筆'),
        ),
      ),
    ];
  }

  Widget _count(String label, int n, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$n',
              style: TextStyle(
                  fontSize: AppType.display,
                  fontWeight: AppFont.figure,
                  color: color,
                  fontFeatures: tabular)),
          Text(label,
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        ]),
      );

  List<Widget> _issues(List<ImportIssue> list, Color color) => [
        for (final e in list.take(_issueMax))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 64,
                child: Text('第 ${e.line} 列',
                    style: TextStyle(
                        color: color,
                        fontSize: AppType.small,
                        fontFeatures: tabular)),
              ),
              Expanded(
                  child: Text(e.text,
                      style: const TextStyle(
                          fontSize: AppType.small, height: 1.4))),
            ]),
          ),
        if (list.length > _issueMax)
          Text('還有 ${list.length - _issueMax} 列',
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
      ];

  Widget _okRow(ImportRow r) {
    final d = DateTime.tryParse(r.date);
    final day = d == null ? r.date : DateFormat('M/d（EEEEE）', 'zh_TW').format(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
            width: 92,
            child: Text(day,
                style: const TextStyle(
                    fontSize: AppType.small, fontFeatures: tabular))),
        SizedBox(
            width: 48,
            child: Text(r.time,
                style: const TextStyle(
                    fontSize: AppType.small, fontFeatures: tabular))),
        SizedBox(
            width: 44,
            child: Text('${r.party} 位',
                style: TextStyle(
                    fontSize: AppType.small, color: AppColors.muted))),
        Expanded(
          child: Text(r.phone.isEmpty ? r.name : '${r.name}・${r.phone}',
              style: const TextStyle(fontSize: AppType.small),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  Widget _batchList() {
    final b = _batches;
    if (b == null) {
      return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()));
    }
    if (b.isEmpty) {
      return SectionCard(
        child: Text('還沒有匯入過',
            style: TextStyle(color: AppColors.muted, fontSize: AppType.small)),
      );
    }
    final at = DateFormat('M/d HH:mm');
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: [
        for (final x in b) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${at.format(x.createdAt.toLocal())}・${x.fileName ?? '未命名檔案'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppType.body)),
                      const SizedBox(height: 2),
                      Text(
                        x.undoneAt != null
                            ? '已復原・取消了 ${x.undoneCount ?? 0} 筆'
                            : '匯入 ${x.inserted} 筆${x.skipped > 0 ? '・略過 ${x.skipped} 筆' : ''}',
                        style: TextStyle(
                            color: x.undoneAt != null
                                ? AppColors.muted
                                : AppColors.good,
                            fontSize: AppType.small),
                      ),
                    ]),
              ),
              if (x.undoneAt == null)
                _undoing == x.id
                    ? const SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))))
                    : TextButton(
                        onPressed: _undoing == null ? () => _undo(x) : null,
                        child: const Text('整批復原')),
            ]),
          ),
          if (x != b.last) Divider(height: 1, color: AppColors.line),
        ],
      ]),
    );
  }

  Widget _exportCard() => SectionCard(
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('匯出全部訂位',
                  style: TextStyle(
                      fontSize: AppType.title, fontWeight: AppFont.heading)),
              const SizedBox(height: 4),
              Text('Excel 檔，含已取消的；客人電話、Email 都在裡面，請小心保管。',
                  style: TextStyle(
                      color: AppColors.muted,
                      fontSize: AppType.small,
                      height: 1.45)),
            ]),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _exporting ? null : _export,
            child: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('匯出'),
          ),
        ]),
      );
}
