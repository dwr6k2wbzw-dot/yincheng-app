// 班表第二階段：自動算薪資、薪資單（資料庫 ops 0110，老闆 2026-11-15）。
// 金額以資料庫算的為準（payroll_entries.gross）；這裡的 [payrollTotal] 和資料庫 app.payroll_total 同一套公式，
// 只用在編輯畫面「按儲存前先試算」。

double? _numOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
double _num(dynamic v) => v == null ? 0 : (v as num).toDouble();
DateTime _date(dynamic v) => DateTime.parse(v as String);
DateTime? _tsOrNull(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// 計薪方式：日薪、月薪、時薪
String payrollTypeLabel(String? t) => switch (t) { 'daily' => '日薪', 'monthly' => '月薪', 'hourly' => '時薪', _ => '未設定' };

/// 加班費算法：固定時薪（預設 200）或依勞基法（月薪÷240，前 2 小時 ×1.34、第 3 小時起 ×1.67）
String otModeLabel(String m) => m == 'lsa' ? '依勞基法' : '固定時薪';

/// 四捨五入到元（.5 進位，負數也是離 0 遠的那邊；和 Postgres numeric 的 round 一樣）
int roundYuan(double v) => v >= 0 ? (v + 0.5 + 1e-9).floor() : -((-v) + 0.5 + 1e-9).floor();

/// 實發金額（和資料庫 app.payroll_total 同一套）。沒有薪率＝算不出來（null）。
/// - 日薪：日薪 × 天數（＋獎金−扣項；不扣勞健保、沒有加班）
/// - 月薪：底薪＋獎金−勞健保自付−扣項＋加班費（固定：時數×加班時薪；勞基法：月薪÷240×(1.34×前 2 小時＋1.67×之後)）
/// - 時薪：時薪 × 時數＋獎金−勞健保自付−扣項
/// 扣項（ops 0124）：三種計薪方式都從實發扣掉，扣的是什麼寫在備註
int? payrollTotal({
  required String payType,
  required double? base,
  double? days,
  double? hours,
  double otHours = 0,
  double otHours2 = 0,
  String otMode = 'fixed',
  double otRate = 200,
  double bonus = 0,
  double insurance = 0,
  double deduction = 0,
}) {
  if (base == null) return null;
  return switch (payType) {
    'daily' => roundYuan(base * (days ?? 0) + bonus - deduction),
    'hourly' => roundYuan(base * (hours ?? 0) + bonus - insurance - deduction),
    _ => roundYuan(base +
        bonus -
        insurance -
        deduction +
        (otMode == 'lsa' ? base / 240 * (1.34 * otHours + 1.67 * otHours2) : (otHours + otHours2) * otRate)),
  };
}

/// 時數只能是 0.5 小時的倍數（老闆 2026-11-15：打卡每段取整到半小時，手動輸入也一樣）
bool isHalfHour(double v) => (v * 2 - (v * 2).roundToDouble()).abs() < 1e-9;

/// 薪資數字欄位的檢查：空白＝沒填（null）；有錯回傳要顯示的紅字。
/// 格式不對（例 1..5、abc、負數）不能當成空白，不然會被當 0 存進去。
/// 小數位數與上限照 ops 0110 欄位定義：天數 numeric(4,1)、金額 numeric(10,2)；
/// 多的小數存進去會被資料庫四捨五入（1.25 天 → 1.3 天），和畫面試算不一樣，所以直接擋
String? payrollNumberError(String text, {required int decimals, int? max}) {
  final t = text.trim();
  if (t.isEmpty) return null;
  if (!RegExp(r'^\d*\.?\d*$').hasMatch(t) || !RegExp(r'\d').hasMatch(t)) {
    return '格式不對：只能填 0 或正數（例如 4、4.5、1500）';
  }
  final frac = t.contains('.') ? t.substring(t.indexOf('.') + 1).replaceFirst(RegExp(r'0+$'), '') : '';
  if (frac.length > decimals) return decimals == 1 ? '最多 1 位小數（例如 1.5）' : '最多 $decimals 位小數（例如 1500.25）';
  if (max != null && double.parse(t) > max) return '不能超過 $max';
  return null;
}

/// 這個月薪資清單的一列（payroll_month）
class PayrollRow {
  final String personId;
  final String name;
  final String kind;
  final String status; // draft 草稿／published 已發布
  final String payType;
  final double? baseAmount;
  final double? autoDays; // 打卡帶入（隱城；已確認的出勤段）
  final double? autoHours;
  final double? daysOverride; // 店長手動改的（null＝用帶入值）
  final double? hoursOverride;
  final double? days; // 實際用來算的
  final double? hours;
  final double otHours;
  final double otHours2;
  final String otMode;
  final double otRate;
  final double bonus;
  final double insurance;
  final double deduction; // 扣項（ops 0124）
  final String? note;
  final double? gross;
  final bool editable;
  final bool hidden; // 店長自己的那一列：只有名字
  final bool missingRate; // 應計薪名單上、還沒有這個月薪資列（沒有薪率，或薪率是帶入之後才加的）
  final bool exempt; // 老闆標了不計薪（不在應計薪名單上）
  final DateTime? updatedAt;
  const PayrollRow({
    required this.personId,
    required this.name,
    this.kind = 'full',
    this.status = 'draft',
    required this.payType,
    this.baseAmount,
    this.autoDays,
    this.autoHours,
    this.daysOverride,
    this.hoursOverride,
    this.days,
    this.hours,
    this.otHours = 0,
    this.otHours2 = 0,
    this.otMode = 'fixed',
    this.otRate = 200,
    this.bonus = 0,
    this.insurance = 0,
    this.deduction = 0,
    this.note,
    this.gross,
    this.editable = false,
    this.hidden = false,
    this.missingRate = false,
    this.exempt = false,
    this.updatedAt,
  });
  factory PayrollRow.fromRow(Map<String, dynamic> r) => PayrollRow(
        personId: r['person_id'] as String,
        name: r['name'] as String? ?? '',
        kind: r['kind'] as String? ?? 'full',
        status: r['status'] as String? ?? 'draft',
        payType: r['pay_type'] as String? ?? 'hourly',
        baseAmount: _numOrNull(r['base_amount']),
        autoDays: _numOrNull(r['auto_days']),
        autoHours: _numOrNull(r['auto_hours']),
        daysOverride: _numOrNull(r['days_override']),
        hoursOverride: _numOrNull(r['hours_override']),
        days: _numOrNull(r['days']),
        hours: _numOrNull(r['hours']),
        otHours: _num(r['ot_hours']),
        otHours2: _num(r['ot_hours2']),
        otMode: r['ot_mode'] as String? ?? 'fixed',
        otRate: _numOrNull(r['ot_rate']) ?? 200,
        bonus: _num(r['bonus']),
        insurance: _num(r['insurance']),
        deduction: _num(r['deduction']),
        note: r['note'] as String?,
        gross: _numOrNull(r['gross']),
        editable: r['editable'] as bool? ?? false,
        hidden: r['hidden'] as bool? ?? false,
        missingRate: r['missing_rate'] as bool? ?? false,
        exempt: r['exempt'] as bool? ?? false,
        updatedAt: _tsOrNull(r['updated_at']),
      );

  bool get published => status == 'published';
  bool get daysEdited => daysOverride != null;
  bool get hoursEdited => hoursOverride != null;
}

/// 月報（payroll_report）。total／costRate：店長少了自己那一列時是 null（避免反推自己的薪水）
class PayrollReport {
  final String? status; // null＝這個月還沒建立
  final int people;
  final double? total;
  final double? revenue;
  final double? costRate;
  final bool complete;
  final int missingRate;
  final double? visibleTotal;
  final List<String> missingNames; // 應計薪名單缺的人（不是空的就不能發布）
  const PayrollReport({
    this.status,
    this.people = 0,
    this.total,
    this.revenue,
    this.costRate,
    this.complete = false,
    this.missingRate = 0,
    this.visibleTotal,
    this.missingNames = const [],
  });
  factory PayrollReport.fromRow(Map<String, dynamic> r) => PayrollReport(
        status: r['status'] as String?,
        people: (r['people'] as num?)?.toInt() ?? 0,
        total: _numOrNull(r['total']),
        revenue: _numOrNull(r['revenue']),
        costRate: _numOrNull(r['cost_rate']),
        complete: r['complete'] as bool? ?? false,
        missingRate: (r['missing_rate'] as num?)?.toInt() ?? 0,
        visibleTotal: _numOrNull(r['visible_total']),
        missingNames: [for (final n in (r['missing_names'] as List? ?? const [])) n as String],
      );
  bool get published => status == 'published';
}

/// 加班費設定（payroll_settings）
class PayrollSettings {
  final String otMode;
  final double otRate;
  const PayrollSettings({this.otMode = 'fixed', this.otRate = 200});
  factory PayrollSettings.fromRow(Map<String, dynamic> r) =>
      PayrollSettings(otMode: r['ot_mode'] as String? ?? 'fixed', otRate: _numOrNull(r['ot_rate']) ?? 200);
}

/// 我的薪資單（payroll_my_slips：已發布、綁定經老闆確認的本人）
class PayrollSlip {
  final DateTime month;
  final String storeName;
  final String personName;
  final String payType;
  final double? baseAmount;
  final double? days;
  final double? hours;
  final double otHours;
  final double otHours2;
  final String otMode;
  final double otRate;
  final double bonus;
  final double insurance;
  final double deduction;
  final String? note;
  final double? gross;
  final DateTime? publishedAt;
  /// 已發布（管理頁的清單只知道狀態、沒有發布時間，所以另外帶）
  final bool published;
  const PayrollSlip({
    required this.month,
    required this.storeName,
    required this.personName,
    required this.payType,
    this.baseAmount,
    this.days,
    this.hours,
    this.otHours = 0,
    this.otHours2 = 0,
    this.otMode = 'fixed',
    this.otRate = 200,
    this.bonus = 0,
    this.insurance = 0,
    this.deduction = 0,
    this.note,
    this.gross,
    this.publishedAt,
    bool? published,
  }) : published = published ?? publishedAt != null;
  factory PayrollSlip.fromRow(Map<String, dynamic> r) => PayrollSlip(
        month: _date(r['month']),
        storeName: r['store_name'] as String? ?? '',
        personName: r['person_name'] as String? ?? '',
        payType: r['pay_type'] as String? ?? 'hourly',
        baseAmount: _numOrNull(r['base_amount']),
        days: _numOrNull(r['days']),
        hours: _numOrNull(r['hours']),
        otHours: _num(r['ot_hours']),
        otHours2: _num(r['ot_hours2']),
        otMode: r['ot_mode'] as String? ?? 'fixed',
        otRate: _numOrNull(r['ot_rate']) ?? 200,
        bonus: _num(r['bonus']),
        insurance: _num(r['insurance']),
        deduction: _num(r['deduction']),
        note: r['note'] as String?,
        gross: _numOrNull(r['gross']),
        publishedAt: _tsOrNull(r['published_at']),
      );

  /// 老闆、店長在薪資清單上看的那一列，轉成同樣格式的薪資單（列印用）
  factory PayrollSlip.fromPayrollRow(PayrollRow r, DateTime month, String storeName) => PayrollSlip(
        month: month,
        storeName: storeName,
        personName: r.name,
        payType: r.payType,
        baseAmount: r.baseAmount,
        days: r.days,
        hours: r.hours,
        otHours: r.otHours,
        otHours2: r.otHours2,
        otMode: r.otMode,
        otRate: r.otRate,
        bonus: r.bonus,
        insurance: r.insurance,
        deduction: r.deduction,
        note: r.note,
        gross: r.gross,
        published: r.published,
      );

  /// 加班費（月薪制）
  int otPay() => payType != 'monthly' || baseAmount == null
      ? 0
      : roundYuan(otMode == 'lsa' ? baseAmount! / 240 * (1.34 * otHours + 1.67 * otHours2) : (otHours + otHours2) * otRate);

  /// 薪資單上的每一行：項目、說明、金額（正＝加、負＝扣）。
  /// 每一行都先四捨五入到元；實發是整筆算完才四捨五入（和資料庫一樣），
  /// 兩邊差幾塊錢時多一行「進位調整」，讓每一行加起來一定等於實發。
  List<({String label, String detail, double amount})> lines() {
    final b = baseAmount ?? 0;
    String n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
    double r(double v) => roundYuan(v).toDouble();
    final items = [
      switch (payType) {
        'daily' => (label: '日薪', detail: '${n(b)} × ${n(days ?? 0)} 天', amount: r(b * (days ?? 0))),
        'hourly' => (label: '時薪', detail: '${n(b)} × ${n(hours ?? 0)} 小時', amount: r(b * (hours ?? 0))),
        _ => (label: '底薪', detail: '月薪', amount: r(b)),
      },
      if (payType == 'monthly' && otHours + otHours2 > 0)
        (
          label: '加班費',
          detail: otMode == 'lsa'
              ? '依勞基法：${n(b)}÷240 ×（1.34×${n(otHours)}${otHours2 > 0 ? '＋1.67×${n(otHours2)}' : ''} 小時）'
              : '${n(otHours + otHours2)} 小時 × ${n(otRate)}',
          amount: otPay().toDouble()
        ),
      if (bonus != 0) (label: '獎金', detail: '', amount: r(bonus)),
      if (insurance != 0) (label: '勞健保自付額', detail: '', amount: -r(insurance)),
      if (deduction != 0) (label: '扣項', detail: '', amount: -r(deduction)),
    ];
    final diff = gross == null ? 0.0 : gross!.roundToDouble() - items.fold<double>(0, (a, l) => a + l.amount);
    return [
      ...items,
      if (diff != 0) (label: '進位調整', detail: '各項四捨五入到元後與實發的差額', amount: diff),
    ];
  }
}
