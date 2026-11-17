// 班表第二階段：自動算薪資、薪資單（資料庫 ops 0110，老闆 2026-11-15）。
// 金額以資料庫算的為準（payroll_entries.gross）；這裡的 [payrollTotal] 和資料庫 app.payroll_total 同一套公式，
// 只用在編輯畫面「按儲存前先試算」。

import 'person_names.dart';

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
/// 其他薪資項目（ops 0126，[PayExtras]）：收入的加進獎金那一格、支出的加進扣項那一格再算；領現不影響實發
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
  PayExtras extras = const PayExtras(),
}) {
  if (base == null) return null;
  bonus += extras.income;
  deduction += extras.deduction;
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

/// 自訂的薪資項目（ops 0126）：收入或支出、名稱、金額
class PayItem {
  final bool income; // true＝收入，false＝支出
  final String label;
  final double amount;
  const PayItem({required this.income, required this.label, required this.amount});
  factory PayItem.fromJson(Map<String, dynamic> j) =>
      PayItem(income: j['side'] == 'income', label: j['label'] as String? ?? '', amount: _num(j['amount']));
  Map<String, dynamic> toJson() => {'side': income ? 'income' : 'deduction', 'label': label, 'amount': amount};
}

/// 自訂項目最多幾項、名稱最多幾個字（跟資料庫 app.payroll_items_ok 一樣）
const payItemsMax = 12, payItemLabelMax = 20;

/// 薪資單上內建的其他項目＋自訂項目（ops 0126，老闆 2026-11-17：薪資單分收入／支出、有金額才列）。
/// 收入：全勤獎金；支出：勞保、健保、眷屬健保、所得稅；領現＝實發裡發現金的那一部分（不影響實發）。
class PayExtras {
  final double attendanceBonus;
  final double laborIns;
  final double healthIns;
  final double dependentsIns;
  final double incomeTax;
  final double cashPaid;
  final List<PayItem> items;
  const PayExtras({
    this.attendanceBonus = 0,
    this.laborIns = 0,
    this.healthIns = 0,
    this.dependentsIns = 0,
    this.incomeTax = 0,
    this.cashPaid = 0,
    this.items = const [],
  });
  factory PayExtras.fromRow(Map<String, dynamic> r) => PayExtras(
        attendanceBonus: _num(r['attendance_bonus']),
        laborIns: _num(r['labor_ins']),
        healthIns: _num(r['health_ins']),
        dependentsIns: _num(r['dependents_ins']),
        incomeTax: _num(r['income_tax']),
        cashPaid: _num(r['cash_paid']),
        items: [for (final j in (r['extra_items'] as List? ?? const [])) PayItem.fromJson(Map<String, dynamic>.from(j as Map))],
      );

  /// 加進收入的合計（全勤獎金＋自訂收入）
  double get income => attendanceBonus + items.where((i) => i.income).fold(0.0, (a, i) => a + i.amount);

  /// 加進支出的合計（勞保＋健保＋眷屬健保＋所得稅＋自訂支出）
  double get deduction =>
      laborIns + healthIns + dependentsIns + incomeTax + items.where((i) => !i.income).fold(0.0, (a, i) => a + i.amount);

  /// 存檔時送給資料庫的 p_more
  Map<String, dynamic> toJson() => {
        'attendance_bonus': attendanceBonus,
        'labor_ins': laborIns,
        'health_ins': healthIns,
        'dependents_ins': dependentsIns,
        'income_tax': incomeTax,
        'cash_paid': cashPaid,
        'extra_items': [for (final i in items) i.toJson()],
      };
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
  final PayExtras extras; // 全勤、勞保、健保、眷屬健保、所得稅、領現、自訂項目（ops 0126）
  final String slipName; // 薪資單上的姓名：全名（沒填全名才是班表上的名字）
  final String? note;
  final double? gross;
  final bool editable;
  final bool hidden; // 店長自己的那一列：只有名字
  final bool missingRate; // 應計薪名單上、還沒有這個月薪資列（沒有薪率，或薪率是帶入之後才加的）
  final bool exempt; // 老闆標了不計薪（不在應計薪名單上）
  final DateTime? updatedAt;
  /// 核准的加班帶入（ops 0127；月薪制、開了打卡的店）：null＝沒有帶入
  final double? autoOtHours, autoOtHours2;
  /// 店長手動改過加班時數（跟核准帶入的不一樣），之後不會被蓋掉
  final bool otManual;
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
    this.extras = const PayExtras(),
    String? slipName,
    this.note,
    this.gross,
    this.editable = false,
    this.hidden = false,
    this.missingRate = false,
    this.exempt = false,
    this.updatedAt,
    this.autoOtHours,
    this.autoOtHours2,
    this.otManual = false,
  }) : slipName = slipName ?? name;
  factory PayrollRow.fromRow(Map<String, dynamic> r) => PayrollRow(
        personId: r['person_id'] as String,
        name: labelOfPerson(r['person_id'], r['name'] as String? ?? ''),
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
        extras: PayExtras.fromRow(r),
        slipName: fullNameOfPerson(r['person_id'], r['name'] as String? ?? ''),
        note: r['note'] as String?,
        gross: _numOrNull(r['gross']),
        editable: r['editable'] as bool? ?? false,
        hidden: r['hidden'] as bool? ?? false,
        missingRate: r['missing_rate'] as bool? ?? false,
        exempt: r['exempt'] as bool? ?? false,
        updatedAt: _tsOrNull(r['updated_at']),
        autoOtHours: _numOrNull(r['auto_ot_hours']),
        autoOtHours2: _numOrNull(r['auto_ot_hours2']),
        otManual: r['ot_manual'] as bool? ?? false,
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
  /// 公司登記全名（薪資單抬頭，ops 0126；只有老闆能設）。沒設＝null，薪資單抬頭照舊用店名
  final String? companyName;
  const PayrollSettings({this.otMode = 'fixed', this.otRate = 200, this.companyName});
  factory PayrollSettings.fromRow(Map<String, dynamic> r) => PayrollSettings(
      otMode: r['ot_mode'] as String? ?? 'fixed',
      otRate: _numOrNull(r['ot_rate']) ?? 200,
      companyName: r['company_name'] as String?);
}

/// 薪資單上的一行：項目、說明、金額
typedef SlipLine = ({String label, String detail, double amount});

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
  final PayExtras extras;
  /// 公司登記全名（薪資單抬頭）；沒設就用店名
  final String? companyName;
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
    this.extras = const PayExtras(),
    this.companyName,
    this.note,
    this.gross,
    this.publishedAt,
    bool? published,
  }) : published = published ?? publishedAt != null;
  factory PayrollSlip.fromRow(Map<String, dynamic> r) => PayrollSlip(
        month: _date(r['month']),
        storeName: r['store_name'] as String? ?? '',
        personName: r['person_name'] as String? ?? '', // 資料庫給的就是全名（沒填全名才是班表上的名字）
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
        extras: PayExtras.fromRow(r),
        companyName: r['company_name'] as String?,
        note: r['note'] as String?,
        gross: _numOrNull(r['gross']),
        publishedAt: _tsOrNull(r['published_at']),
      );

  /// 老闆、店長在薪資清單上看的那一列，轉成同樣格式的薪資單（列印用）
  factory PayrollSlip.fromPayrollRow(PayrollRow r, DateTime month, String storeName, {String? companyName}) => PayrollSlip(
        month: month,
        storeName: storeName,
        personName: r.slipName,
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
        extras: r.extras,
        companyName: companyName,
        note: r.note,
        gross: r.gross,
        published: r.published,
      );

  /// 薪資單抬頭：公司登記全名；還沒設就用店名
  String get title => (companyName == null || companyName!.trim().isEmpty) ? storeName : companyName!.trim();

  /// 加班費（月薪制）
  int otPay() => payType != 'monthly' || baseAmount == null
      ? 0
      : roundYuan(otMode == 'lsa' ? baseAmount! / 240 * (1.34 * otHours + 1.67 * otHours2) : (otHours + otHours2) * otRate);

  static String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
  static double _r(double v) => roundYuan(v).toDouble();

  /// 收入那一欄（不含進位調整）：本薪、加班費、全勤獎金、獎金、自訂收入。有金額才列；金額都是正的、四捨五入到元
  List<SlipLine> _incomeItems() {
    final b = baseAmount ?? 0;
    return [
      switch (payType) {
        'daily' => (label: '日薪', detail: '${_n(b)} × ${_n(days ?? 0)} 天', amount: _r(b * (days ?? 0))),
        'hourly' => (label: '時薪', detail: '${_n(b)} × ${_n(hours ?? 0)} 小時', amount: _r(b * (hours ?? 0))),
        _ => (label: '底薪', detail: '月薪', amount: _r(b)),
      },
      if (payType == 'monthly' && otHours + otHours2 > 0)
        (
          label: '加班費',
          detail: otMode == 'lsa'
              ? '依勞基法：${_n(b)}÷240 ×（1.34×${_n(otHours)}${otHours2 > 0 ? '＋1.67×${_n(otHours2)}' : ''} 小時）'
              : '${_n(otHours + otHours2)} 小時 × ${_n(otRate)}',
          amount: otPay().toDouble()
        ),
      if (extras.attendanceBonus != 0) (label: '全勤獎金', detail: '', amount: _r(extras.attendanceBonus)),
      if (bonus != 0) (label: '獎金', detail: '', amount: _r(bonus)),
      for (final i in extras.items)
        if (i.income) (label: i.label, detail: '', amount: _r(i.amount)),
    ];
  }

  /// 支出那一欄：勞保、健保、眷屬健保、所得稅、（舊的）勞健保自付額、扣項、自訂支出。有金額才列；金額都是正的
  List<SlipLine> deductionLines() => [
        if (extras.laborIns != 0) (label: '勞保費', detail: '', amount: _r(extras.laborIns)),
        if (extras.healthIns != 0) (label: '健保費', detail: '', amount: _r(extras.healthIns)),
        if (extras.dependentsIns != 0) (label: '眷屬健保費', detail: '', amount: _r(extras.dependentsIns)),
        if (extras.incomeTax != 0) (label: '所得稅', detail: '', amount: _r(extras.incomeTax)),
        if (insurance != 0) (label: '勞健保自付額', detail: '', amount: _r(insurance)),
        if (deduction != 0) (label: '扣項', detail: '', amount: _r(deduction)),
        for (final i in extras.items)
          if (!i.income) (label: i.label, detail: '', amount: _r(i.amount)),
      ];

  /// 每一項都先四捨五入到元；實發是整筆算完才四捨五入（和資料庫一樣），差的幾塊錢
  double get _roundingDiff => gross == null
      ? 0.0
      : gross!.roundToDouble() -
          (_incomeItems().fold<double>(0, (a, l) => a + l.amount) - deductionLines().fold<double>(0, (a, l) => a + l.amount));

  /// 收入那一欄；各項進位後跟實發對不上時多一行「進位調整」，讓 收入合計 − 支出合計 一定等於實發
  List<SlipLine> incomeLines() {
    final diff = _roundingDiff;
    return [..._incomeItems(), if (diff != 0) (label: '進位調整', detail: '各項四捨五入到元後與實發的差額', amount: diff)];
  }

  double get incomeTotal => incomeLines().fold<double>(0, (a, l) => a + l.amount);
  double get deductionTotal => deductionLines().fold<double>(0, (a, l) => a + l.amount);

  /// 領現金額（實發裡發現金的那一部分）；實際入帳＝實發−領現
  double get cashPaid => _r(extras.cashPaid);
  double? get transfer => gross == null ? null : gross!.roundToDouble() - cashPaid;

  /// 全部排成一欄：收入（正）、支出（負）、進位調整。每一行加起來一定等於實發。
  List<SlipLine> lines() {
    final diff = _roundingDiff;
    return [
      ..._incomeItems(),
      for (final l in deductionLines()) (label: l.label, detail: l.detail, amount: -l.amount),
      if (diff != 0) (label: '進位調整', detail: '各項四捨五入到元後與實發的差額', amount: diff),
    ];
  }
}
