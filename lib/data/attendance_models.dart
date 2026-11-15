// 班表第一階段：員工資料、QR 打卡（資料庫 ops 0109，老闆 2026-11-15）。
// 打卡時間一律是伺服器時間；營業日切點 06:00（台北），由資料庫算好帶回來（business_date）。

import '../services/clock.dart';

DateTime _ts(dynamic v) => DateTime.parse(v as String).toLocal();
DateTime? _tsOrNull(dynamic v) => v == null ? null : _ts(v);
DateTime _date(dynamic v) => DateTime.parse(v as String);
DateTime? _dateOrNull(dynamic v) => v == null ? null : _date(v);
double? _numOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
List<String> _strs(dynamic v) => v == null ? const [] : [for (final x in v as List) x as String];

String punchTypeLabel(String t) => t == 'in' ? '上班' : '下班';

/// 待確認原因（資料庫 attendance_punches.flags）
String punchFlagLabel(String f) => switch (f) {
      'code_expired' => 'QR 碼過期',
      'code_invalid' => 'QR 碼不對',
      'kiosk_inactive' => '打卡機已停用',
      'cross_store' => '跨店支援',
      'duplicate' => '2 分鐘內重複掃',
      _ => f,
    };

String anomalyKindLabel(String k) => switch (k) {
      'missing_out' => '漏打下班',
      'missing_in' => '漏打上班',
      'long_shift' => '超過 12 小時',
      'short_shift' => '不到 10 分鐘',
      'duplicate' => '重複掃',
      'pending' => '待確認',
      'amendment' => '待審補登',
      _ => k,
    };

/// 我在這家店的打卡狀態（attendance_me）
class AttendanceMe {
  final bool enabled; // 這家店有沒有開放打卡（目前只有隱城）
  final bool canManage; // 老闆、店長
  final String? personId; // 我在班表上是誰；null＝還沒在排班選「我是誰」
  final String? personName;
  final String? lastPunchType;
  final DateTime? lastPunchedAt;
  final bool onShift;
  final DateTime serverTime;
  final bool bindingPending; // 選了班表上的名字，但老闆還沒確認 → 不能打卡
  const AttendanceMe({
    required this.enabled,
    required this.canManage,
    this.personId,
    this.personName,
    this.lastPunchType,
    this.lastPunchedAt,
    this.onShift = false,
    required this.serverTime,
    this.bindingPending = false,
  });
  factory AttendanceMe.fromRow(Map<String, dynamic> r) => AttendanceMe(
        enabled: r['enabled'] as bool? ?? false,
        canManage: r['can_manage'] as bool? ?? false,
        personId: r['person_id'] as String?,
        personName: r['person_name'] as String?,
        lastPunchType: r['last_punch_type'] as String?,
        lastPunchedAt: _tsOrNull(r['last_punched_at']),
        onShift: r['on_shift'] as bool? ?? false,
        serverTime: _ts(r['server_time']),
        bindingPending: r['binding_pending'] as bool? ?? false,
      );
}

/// 掃碼打卡的結果
class PunchResult {
  final String punchId;
  final String storeName;
  final String punchType;
  final DateTime punchedAt; // 伺服器時間
  final DateTime businessDate;
  final String status; // ok／pending（待確認）
  final List<String> flags;
  const PunchResult({
    required this.punchId,
    required this.storeName,
    required this.punchType,
    required this.punchedAt,
    required this.businessDate,
    required this.status,
    required this.flags,
  });
  bool get pending => status == 'pending';
  factory PunchResult.fromRow(Map<String, dynamic> r) => PunchResult(
        punchId: r['punch_id'] as String,
        storeName: r['store_name'] as String? ?? '',
        punchType: r['punch_type'] as String,
        punchedAt: _ts(r['punched_at']),
        businessDate: _date(r['business_date']),
        status: r['status'] as String,
        flags: _strs(r['flags']),
      );
}

/// QR 碼內容：打卡網址 …/#/punch?k=打卡機&w=第幾個 30 秒&c=碼
class PunchLink {
  final String kiosk;
  final int window;
  final String code;
  const PunchLink(this.kiosk, this.window, this.code);

  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  /// 看得懂掃到的字（完整網址，或只有 #/punch?… 那段）才回傳；別的 QR 碼回 null
  static PunchLink? parse(String raw) {
    final s = raw.trim();
    final i = s.indexOf('#/punch?');
    if (i < 0) return null;
    final q = Uri.splitQueryString(s.substring(i + '#/punch?'.length));
    final k = q['k']?.toLowerCase(), w = int.tryParse(q['w'] ?? ''), c = q['c'];
    if (k == null || !_uuid.hasMatch(k) || w == null || c == null || c.isEmpty || c.length > 64) return null;
    return PunchLink(k, w, c);
  }

  /// base：App 網址（不含 #），例如 https://…/yincheng-app/
  String toUrl(String base) => '$base#/punch?k=$kiosk&w=$window&c=$code';
}

/// 打卡機畫面每 30 秒拿的碼
class KioskCode {
  final String storeName;
  final String kioskName;
  final int window;
  final String code;
  final DateTime serverTime;
  final DateTime validUntil;
  const KioskCode({
    required this.storeName,
    required this.kioskName,
    required this.window,
    required this.code,
    required this.serverTime,
    required this.validUntil,
  });
  factory KioskCode.fromRow(Map<String, dynamic> r) {
    // 密鑰錯、嘗試太多次：資料庫回一列 error（才記得住失敗次數），不是丟錯誤
    final err = r['error'] as String?;
    if (err != null) throw KioskCodeError(err);
    return KioskCode(
        storeName: r['store_name'] as String? ?? '',
        kioskName: r['kiosk_name'] as String? ?? '',
        window: (r['win'] as num).toInt(),
        code: r['code'] as String,
        serverTime: _ts(r['server_time']),
        validUntil: _ts(r['valid_until']),
      );
  }
}

/// 打卡機拿碼被拒（密鑰不對、嘗試太多次）
class KioskCodeError implements Exception {
  final String message;
  const KioskCodeError(this.message);
  @override
  String toString() => message;
}

class KioskInfo {
  final String id;
  final String name;
  final bool active;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  const KioskInfo({required this.id, required this.name, required this.active, required this.createdAt, this.lastSeenAt});
  factory KioskInfo.fromRow(Map<String, dynamic> r) => KioskInfo(
        id: r['id'] as String,
        name: r['name'] as String? ?? '',
        active: r['active'] as bool? ?? false,
        createdAt: _ts(r['created_at']),
        lastSeenAt: _tsOrNull(r['last_seen_at']),
      );
}

/// 一段出勤（上班配下一筆 14 小時內的下班）
class AttendanceSession {
  final String personId;
  final String personName;
  final DateTime businessDate;
  final DateTime? inAt;
  final DateTime? outAt;
  final int? minutes;
  final bool pending; // 有一筆還在待確認 → 確認前不計入工時
  final int countedMinutes; // 計入工時的分鐘（待確認的段＝0）
  const AttendanceSession({
    required this.personId,
    required this.personName,
    required this.businessDate,
    this.inAt,
    this.outAt,
    this.minutes,
    this.pending = false,
    int? countedMinutes,
  }) : countedMinutes = countedMinutes ?? (pending ? 0 : minutes ?? 0);
  factory AttendanceSession.fromRow(Map<String, dynamic> r) => AttendanceSession(
        personId: r['person_id'] as String,
        personName: r['person_name'] as String? ?? '',
        businessDate: _date(r['business_date']),
        inAt: _tsOrNull(r['in_at']),
        outAt: _tsOrNull(r['out_at']),
        minutes: (r['minutes'] as num?)?.toInt(),
        pending: r['pending'] as bool? ?? false,
        countedMinutes: (r['counted_minutes'] as num?)?.toInt(),
      );
}

/// 異常清單一列
class AttendanceAnomaly {
  final String kind;
  final DateTime? businessDate;
  final String? personId;
  final String personName;
  final String? punchId;
  final String? amendmentId;
  final DateTime? at;
  final String? punchType;
  final String? detail;
  const AttendanceAnomaly({
    required this.kind,
    this.businessDate,
    this.personId,
    required this.personName,
    this.punchId,
    this.amendmentId,
    this.at,
    this.punchType,
    this.detail,
  });
  factory AttendanceAnomaly.fromRow(Map<String, dynamic> r) => AttendanceAnomaly(
        kind: r['kind'] as String,
        businessDate: _dateOrNull(r['business_date']),
        personId: r['person_id'] as String?,
        personName: r['person_name'] as String? ?? '',
        punchId: r['punch_id'] as String?,
        amendmentId: r['amendment_id'] as String?,
        at: _tsOrNull(r['at']),
        punchType: r['punch_type'] as String?,
        detail: r['detail'] as String?,
      );
}

/// 我的打卡與補登（attendance_my_records）
class MyAttendanceRecord {
  final String kind; // punch／amendment
  final String id;
  final String punchType;
  final DateTime at;
  final DateTime? businessDate;
  final String storeName;
  final String status; // 打卡 ok／pending；補登 pending／approved／rejected／cancelled
  final List<String> flags;
  final String? review; // confirmed／rejected
  final String? note;
  const MyAttendanceRecord({
    required this.kind,
    required this.id,
    required this.punchType,
    required this.at,
    this.businessDate,
    required this.storeName,
    required this.status,
    this.flags = const [],
    this.review,
    this.note,
  });
  bool get isPunch => kind == 'punch';
  factory MyAttendanceRecord.fromRow(Map<String, dynamic> r) => MyAttendanceRecord(
        kind: r['kind'] as String,
        id: r['id'] as String,
        punchType: r['punch_type'] as String,
        at: _ts(r['at']),
        businessDate: _dateOrNull(r['business_date']),
        storeName: r['store_name'] as String? ?? '',
        status: r['status'] as String,
        flags: _strs(r['flags']),
        review: r['review'] as String?,
        note: r['note'] as String?,
      );

  String get statusLabel {
    if (!isPunch) {
      return switch (status) {
        'pending' => '補登待審',
        'approved' => '補登已核准',
        'rejected' => '補登退回',
        'cancelled' => '補登已取消',
        _ => status,
      };
    }
    if (review == 'confirmed') return '店長已確認';
    if (review == 'rejected') return '店長不採用';
    return status == 'pending' ? '待確認' : '正常';
  }
}

/// 匯出（CSV）一列
class AttendanceExportRow {
  final DateTime businessDate;
  final String personName;
  final String punchType;
  final DateTime punchedAt;
  final String storeName;
  final String source; // qr／amendment
  final String status;
  final String flags; // 空白分隔
  final String? review;
  final String? reviewReason;
  final String? amendmentReason;
  final bool counted;
  final String punchId;
  const AttendanceExportRow({
    required this.businessDate,
    required this.personName,
    required this.punchType,
    required this.punchedAt,
    required this.storeName,
    required this.source,
    required this.status,
    required this.flags,
    this.review,
    this.reviewReason,
    this.amendmentReason,
    required this.counted,
    required this.punchId,
  });
  /// 待確認：確認前不計入工時（老闆 2026-11-15）
  bool get awaitingReview => status == 'pending' && review == null;
  String get countedLabel => counted ? '算' : awaitingReview ? '待確認（不算）' : '不算';
  factory AttendanceExportRow.fromRow(Map<String, dynamic> r) => AttendanceExportRow(
        businessDate: _date(r['business_date']),
        personName: r['person_name'] as String? ?? '',
        punchType: r['punch_type'] as String,
        punchedAt: _ts(r['punched_at']),
        storeName: r['store_name'] as String? ?? '',
        source: r['source'] as String,
        status: r['status'] as String,
        flags: r['flags'] as String? ?? '',
        review: r['review'] as String?,
        reviewReason: r['review_reason'] as String?,
        amendmentReason: r['amendment_reason'] as String?,
        counted: r['counted'] as bool? ?? false,
        punchId: r['punch_id'] as String,
      );
}

/// 員工資料一覽（staff_directory）：老闆看全部；店長身分證、帳號是遮罩、沒有薪率；其他人只有自己
class StaffEntry {
  final String personId;
  final String name;
  final String kind; // full／part
  final bool active;
  final DateTime? hireDate;
  final String? userId;
  final String? phone;
  final String? emergencyContact;
  final String? emergencyPhone;
  final DateTime? leaveDate;
  final String? payType; // monthly／hourly
  final String? nationalId;
  final String? bankCode;
  final String? bankAccount;
  final bool identityMasked;
  final DateTime? rateEffectiveFrom;
  final String? ratePayType;
  final double? rateAmount;
  final double? insuredSalary;
  final double? pensionSelfRate;
  final bool canSeePay;
  final bool userVerified; // 帳號綁定老闆確認過了沒（沒確認＝不算本人）
  final String? userName; // 綁定的 App 帳號名稱
  const StaffEntry({
    required this.personId,
    required this.name,
    required this.kind,
    required this.active,
    this.hireDate,
    this.userId,
    this.phone,
    this.emergencyContact,
    this.emergencyPhone,
    this.leaveDate,
    this.payType,
    this.nationalId,
    this.bankCode,
    this.bankAccount,
    this.identityMasked = false,
    this.rateEffectiveFrom,
    this.ratePayType,
    this.rateAmount,
    this.insuredSalary,
    this.pensionSelfRate,
    this.canSeePay = false,
    this.userVerified = false,
    this.userName,
  });
  factory StaffEntry.fromRow(Map<String, dynamic> r) => StaffEntry(
        personId: r['person_id'] as String,
        name: r['name'] as String? ?? '',
        kind: r['kind'] as String? ?? 'full',
        active: r['active'] as bool? ?? true,
        hireDate: _dateOrNull(r['hire_date']),
        userId: r['user_id'] as String?,
        phone: r['phone'] as String?,
        emergencyContact: r['emergency_contact'] as String?,
        emergencyPhone: r['emergency_phone'] as String?,
        leaveDate: _dateOrNull(r['leave_date']),
        payType: r['pay_type'] as String?,
        nationalId: r['national_id'] as String?,
        bankCode: r['bank_code'] as String?,
        bankAccount: r['bank_account'] as String?,
        identityMasked: r['identity_masked'] as bool? ?? false,
        rateEffectiveFrom: _dateOrNull(r['rate_effective_from']),
        ratePayType: r['rate_pay_type'] as String?,
        rateAmount: _numOrNull(r['rate_amount']),
        insuredSalary: _numOrNull(r['insured_salary']),
        pensionSelfRate: _numOrNull(r['pension_self_rate']),
        canSeePay: r['can_see_pay'] as bool? ?? false,
        userVerified: r['user_verified'] as bool? ?? false,
        userName: r['user_name'] as String?,
      );
}

String payTypeLabel(String? t) => switch (t) { 'daily' => '日薪', 'monthly' => '月薪', 'hourly' => '時薪', _ => '未設定' };

/// 薪率（生效日歷史；不能改，調薪＝新增一筆較晚的生效日）
class PayRate {
  final String id;
  final DateTime effectiveFrom;
  final String payType;
  final double amount;
  final double? insuredSalary;
  final double pensionSelfRate;
  final String? note;
  const PayRate({
    required this.id,
    required this.effectiveFrom,
    required this.payType,
    required this.amount,
    this.insuredSalary,
    this.pensionSelfRate = 0,
    this.note,
  });
  factory PayRate.fromRow(Map<String, dynamic> r) => PayRate(
        id: r['id'] as String,
        effectiveFrom: _date(r['effective_from']),
        payType: r['pay_type'] as String,
        amount: (r['amount'] as num).toDouble(),
        insuredSalary: _numOrNull(r['insured_salary']),
        pensionSelfRate: _numOrNull(r['pension_self_rate']) ?? 0,
        note: r['note'] as String?,
      );
}

/// 營業日＋台北的「幾點幾分」→ 真實時間點（補登用）。早上 6 點前算隔天凌晨（跟營業日切點一樣）。
DateTime taipeiInstant(DateTime bizDate, int hour, int minute) =>
    DateTime.utc(bizDate.year, bizDate.month, bizDate.day + (hour < 6 ? 1 : 0), hour, minute).subtract(taipeiOffset);

/// 班表那格的上下班時間（補登「從班表帶入」）：時段 18:00-00:30 或班別代碼（照班別時段）；V、休假這類沒時間的回 null
({int inH, int inM, int outH, int outM})? scheduleTimes(String? mark, Map<String, String> codeTimes) {
  if (mark == null) return null;
  final range = mark.contains(':') ? mark : codeTimes[mark];
  final m = RegExp(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$').firstMatch(range ?? '');
  if (m == null) return null;
  final v = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
  if (v[0] > 23 || v[2] > 23 || v[1] > 59 || v[3] > 59) return null;
  return (inH: v[0], inM: v[1], outH: v[2], outM: v[3]);
}

/// 一筆打卡的歷程（attendance_punch_history：補登申請、打卡、核准、每一次審核）
class PunchHistoryEntry {
  final DateTime at;
  final String action; // amendment_request／punch／amendment_punch／amendment_approve／review…
  final String? decision;
  final String? reason;
  final String? actorName;
  const PunchHistoryEntry({required this.at, required this.action, this.decision, this.reason, this.actorName});
  factory PunchHistoryEntry.fromRow(Map<String, dynamic> r) => PunchHistoryEntry(
        at: _ts(r['at']),
        action: r['action'] as String? ?? '',
        decision: r['decision'] as String?,
        reason: r['reason'] as String?,
        actorName: r['actor_name'] as String?,
      );

  String get label => switch (action) {
        'punch' => '掃碼打卡',
        'amendment_punch' => '補登產生',
        'amendment_request' => '申請補登',
        'amendment_approve' => '核准補登',
        'amendment_reject' => '退回補登',
        'amendment_cancel' => '取消補登',
        'review' => decision == 'confirmed' ? '確認' : decision == 'rejected' ? '不採用' : '審核',
        _ => action,
      };
}

/// 補登可以選的人（attendance_people：這家店的人＋來支援過的別家店員工）
class AttendancePerson {
  final String personId;
  final String name;
  final String? homeStoreName;
  final bool crossStore;
  const AttendancePerson({required this.personId, required this.name, this.homeStoreName, this.crossStore = false});
  factory AttendancePerson.fromRow(Map<String, dynamic> r) => AttendancePerson(
        personId: r['person_id'] as String,
        name: r['name'] as String? ?? '',
        homeStoreName: r['home_store_name'] as String?,
        crossStore: r['cross_store'] as bool? ?? false,
      );
  String get label => crossStore ? '$name（${homeStoreName ?? '別家店'}支援）' : name;
}
