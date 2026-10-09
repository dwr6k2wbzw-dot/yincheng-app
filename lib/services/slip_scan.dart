import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

/// 拍照辨識送貨單：手機上選照片／拍照（JS ycPickImage），再用免費文字辨識讀出文字（JS ycOcr，Tesseract.js）
@JS('ycPickImage')
external JSPromise<JSAny?> _ycPickImage();
@JS('ycOcr')
external JSPromise<JSString> _ycOcr(JSString dataUrl);

/// 選照片（或拍照）。取消時回傳 null。回傳壓縮後的 JPEG data URL
Future<String?> pickSlipImage() async {
  final r = await _ycPickImage().toDart;
  if (r == null) return null;
  return (r as JSString).toDart;
}

Future<String> ocrSlip(String dataUrl) async => (await _ycOcr(dataUrl.toJS).toDart).toDart;

Uint8List dataUrlBytes(String dataUrl) => base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));

/// 從辨識文字猜出：廠商、日期、合計。讀不到的欄位是 null（由使用者自己填）
class SlipGuess {
  final String? vendor;
  final DateTime? date;
  final double? total;
  SlipGuess(this.vendor, this.date, this.total);
}

const _knownVendors = {
  '大倉捷': r'大[倉全舍]捷|2564-?1777',
  '盛豐行': r'盛豐|2690-?77',
};

double? _money(String s) {
  var t = s.replaceAll('，', ',').replaceAll(RegExp(r'[Oo]'), '0');
  t = t.replaceFirstMapped(RegExp(r',(\d{2})$'), (m) => '.${m[1]}'); // 「570,00」
  if ('.'.allMatches(t).length > 1) {
    final i = t.lastIndexOf('.');
    t = t.substring(0, i).replaceAll('.', '') + t.substring(i);
  }
  return double.tryParse(t.replaceAll(',', ''));
}

SlipGuess guessSlip(String text, List<String> supplierNames, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final compact = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  // 廠商：先找已知廠商名稱，再找固定的幾家，最後找「XX有限公司」
  String? vendor;
  final names = [...supplierNames]..sort((a, b) => b.length.compareTo(a.length));
  for (final n in names) {
    if (n.length >= 2 && compact.contains(n)) {
      vendor = n;
      break;
    }
  }
  vendor ??= _knownVendors.entries.where((e) => RegExp(e.value).hasMatch(compact)).map((e) => e.key).firstOrNull;
  if (vendor == null) {
    final m = RegExp(r'([一-龥A-Za-z]{2,12})(?:股份)?有限公司').firstMatch(compact);
    if (m != null) vendor = m.group(1);
  }
  // 日期：民國 115/10/01、2026/10/01、10/01
  DateTime? date;
  final roc = RegExp(r'(1[01]\d)\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{1,2})').firstMatch(compact);
  final ad = RegExp(r'(20\d{2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{1,2})').firstMatch(compact);
  DateTime? mk(int y, int m, int d) =>
      (m >= 1 && m <= 12 && d >= 1 && d <= 31) ? DateTime(y, m, d) : null;
  if (roc != null) date = mk(int.parse(roc[1]!) + 1911, int.parse(roc[2]!), int.parse(roc[3]!));
  if (date == null && ad != null) date = mk(int.parse(ad[1]!), int.parse(ad[2]!), int.parse(ad[3]!));
  if (date != null && (date.isAfter(now.add(const Duration(days: 2))) || date.isBefore(now.subtract(const Duration(days: 120))))) {
    date = null; // 讀錯的日期不採用
  }
  // 合計：「合計」「本次銷貨合計」「總計」後面的數字；沒有的話取最大的金額
  double? total;
  final money = r'\d{1,3}(?:[,，.]\d{3})*(?:[.,]\d{2})?|\d+(?:\.\d{2})?';
  for (final m in RegExp('(?:本次銷貨合計|總\\s*計|合\\s*計|應付金額|總金額)[^\\d\\n]{0,8}($money)').allMatches(compact)) {
    final v = _money(m[1]!);
    if (v != null && v > 0) {
      total = v;
      break;
    }
  }
  if (total == null) {
    final all = RegExp(r'\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d+\.\d{2}')
        .allMatches(compact)
        .map((m) => _money(m[0]!))
        .whereType<double>()
        .where((v) => v > 0 && v < 1000000)
        .toList();
    if (all.isNotEmpty) total = all.reduce((a, b) => a > b ? a : b);
  }
  return SlipGuess(vendor, date, total);
}
