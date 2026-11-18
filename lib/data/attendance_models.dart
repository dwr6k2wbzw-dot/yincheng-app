// 班表第一階段：員工資料、QR 打卡（資料庫 ops 0109，老闆 2026-11-15）。
// 打卡時間一律是伺服器時間；營業日切點 06:00（台北），由資料庫算好帶回來（business_date）。

import '../services/clock.dart';
import 'person_names.dart';

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
  final String? personId; // 我在班表上是誰；null＝帳號還沒對應到員工資料（老闆、店長在班表人員對應）
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
        personName: r['person_name'] == null ? null : labelOfPerson(r['person_id'], r['person_name'] as String),
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
  /// 打卡用帳號（ops 0112）：哪個帳號登入後第一頁是密碼打卡；null＝一般打卡機（裝置密鑰）
  final String? accountUserId;
  final String? accountName;
  const KioskInfo(
      {required this.id,
      required this.name,
      required this.active,
      required this.createdAt,
      this.lastSeenAt,
      this.accountUserId,
      this.accountName});
  bool get isAccount => accountUserId != null;
  factory KioskInfo.fromRow(Map<String, dynamic> r) => KioskInfo(
        id: r['id'] as String,
        name: r['name'] as String? ?? '',
        active: r['active'] as bool? ?? false,
        createdAt: _ts(r['created_at']),
        lastSeenAt: _tsOrNull(r['last_seen_at']),
        accountUserId: r['account_user_id'] as String?,
        accountName: r['account_name'] as String?,
      );
}

/// 可以設成打卡用帳號的人（老闆設定時選）；blocked 不是 null＝不能選，內容是原因
class KioskAccountCandidate {
  final String userId;
  final String displayName;
  final String role;
  final String? blocked;
  const KioskAccountCandidate({required this.userId, required this.displayName, required this.role, this.blocked});
  factory KioskAccountCandidate.fromRow(Map<String, dynamic> r) => KioskAccountCandidate(
        userId: r['user_id'] as String,
        displayName: r['display_name'] as String? ?? '',
        role: r['role'] as String? ?? '',
        blocked: r['blocked'] as String?,
      );
}

/// 登入的帳號是打卡用帳號（ops 0112）：哪家店；error 不是 null＝現在不能打卡（打卡沒開、停權）
class KioskMine {
  final String kioskId;
  final String storeId;
  final String storeName;
  final String kioskName;
  final String? error;
  const KioskMine({required this.kioskId, required this.storeId, required this.storeName, required this.kioskName, this.error});
  factory KioskMine.fromRow(Map<String, dynamic> r) => KioskMine(
        kioskId: r['kiosk_id'] as String,
        storeId: r['store_id'] as String,
        storeName: r['store_name'] as String? ?? '',
        kioskName: r['kiosk_name'] as String? ?? '',
        error: r['error'] as String?,
      );
}

/// 密碼打卡的結果：ok／wrong（密碼不對）／locked（連錯 5 次，鎖 1 分鐘）／no_pin（這個人還沒設密碼）
class PinPunchResult {
  final String result;
  final String? personName;
  final String? punchType;
  final DateTime? punchedAt; // 伺服器時間
  final String? status;
  final List<String> flags;
  final int remaining; // 還可以試幾次
  final DateTime? lockedUntil;
  final String message;
  const PinPunchResult({
    required this.result,
    this.personName,
    this.punchType,
    this.punchedAt,
    this.status,
    this.flags = const [],
    this.remaining = 0,
    this.lockedUntil,
    this.message = '',
  });
  bool get ok => result == 'ok';
  bool get locked => result == 'locked';
  bool get pending => status == 'pending';
  factory PinPunchResult.fromRow(Map<String, dynamic> r) => PinPunchResult(
        result: r['result'] as String,
        personName: r['person_name'] as String?,
        punchType: r['punch_type'] as String?,
        punchedAt: _tsOrNull(r['punched_at']),
        status: r['status'] as String?,
        flags: [for (final f in (r['flags'] as List?) ?? const []) f as String],
        remaining: (r['remaining'] as num?)?.toInt() ?? 0,
        lockedUntil: _tsOrNull(r['locked_until']),
        message: r['message'] as String? ?? '',
      );
}

/// 打卡用帳號看的打卡名單（ops 0125）：先點名字再輸入密碼
class KioskPerson {
  final String personId;
  final String name; // 顯示用：全名
  final bool hasPin;
  const KioskPerson({required this.personId, required this.name, required this.hasPin});
  factory KioskPerson.fromRow(Map<String, dynamic> r) => KioskPerson(
      personId: r['person_id'] as String, name: r['name'] as String? ?? '', hasPin: r['has_pin'] as bool? ?? false);
}

/// 打卡密碼設定狀態（看不到密碼本身）：老闆、店長看全部，其他人只有自己
class PinStatus {
  final String personId;
  final String name;
  final bool active;
  final bool hasPin;
  final DateTime? setAt;
  final bool canSet; // 我能不能設定這個人的（店長不能設自己的；本人只有還沒設的時候）
  final bool mine;
  const PinStatus(
      {required this.personId,
      required this.name,
      required this.active,
      required this.hasPin,
      this.setAt,
      required this.canSet,
      required this.mine});
  factory PinStatus.fromRow(Map<String, dynamic> r) => PinStatus(
        personId: r['person_id'] as String,
        name: labelOfPerson(r['person_id'], r['name'] as String? ?? ''),
        active: r['active'] as bool? ?? false,
        hasPin: r['has_pin'] as bool? ?? false,
        setAt: _tsOrNull(r['set_at']),
        canSet: r['can_set'] as bool? ?? false,
        mine: r['mine'] as bool? ?? false,
      );
}

/// 太好猜的打卡密碼：四個相同數字、連號（往上或往下）。跟資料庫 app.attendance_pin_weak 同一條規則（ops 0112）
bool isWeakPunchPin(String pin) =>
    pin.length == 4 && (pin == pin[0] * 4 || '0123456789'.contains(pin) || '9876543210'.contains(pin));

/// 設定打卡密碼的結果：ok（隨機產生時 pin 只在這次看得到）／rejected（太好猜）／reset_needed（本人已經設過，要店長重設）
class PinSetResult {
  final String result;
  final String? pin;
  final String message;
  const PinSetResult({required this.result, this.pin, this.message = ''});
  bool get ok => result == 'ok';
  factory PinSetResult.fromRow(Map<String, dynamic> r) =>
      PinSetResult(result: r['result'] as String, pin: r['pin'] as String?, message: r['message'] as String? ?? '');
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
        personName: labelOfPerson(r['person_id'], r['person_name'] as String? ?? ''),
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
        personName: labelOfPerson(r['person_id'], r['person_name'] as String? ?? ''),
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
  String get countedLabel => counted ? '計入工時' : awaitingReview ? '待確認（不計入工時）' : '不計入工時';
  factory AttendanceExportRow.fromRow(Map<String, dynamic> r) => AttendanceExportRow(
        businessDate: _date(r['business_date']),
        personName: labelOfPerson(r['person_id'], r['person_name'] as String? ?? ''),
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
  final bool userVerified; // 帳號對應生效了沒（0125 之前員工自己選的要確認一次；沒生效＝不算本人）
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

  /// 員工資料頁的離職日：只在停用或已填離職日的人顯示（還在職的人要離職，先到班表把人停用）
  bool get showsLeaveDate => !active || leaveDate != null;
  factory StaffEntry.fromRow(Map<String, dynamic> r) => StaffEntry(
        personId: r['person_id'] as String,
        name: labelOfPerson(r['person_id'], r['name'] as String? ?? ''),
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

/// 薪率（生效日歷史；ops 0123 起可以修改、刪除、補更早的生效日）
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

/// 漏打下班（老闆 2026-11-18：漏打下班的紀錄不能顯示「正常」）：上班卡之後 14 小時內沒有同一個人的下班卡
/// （中間又打了上班也算）；最後一筆上班還不到 14 小時＝還在上班，不算漏打。不採用、重複掃的卡不看。
/// 匯出沒有人的 id，用店名＋名字分人。
Set<String> missingOutPunchIds(List<AttendanceExportRow> rows, DateTime now) => _missingOut([
      for (final r in rows)
        if (r.review != 'rejected' && !r.flags.split(' ').contains('duplicate'))
          (key: '${r.storeName}|${r.personName}', id: r.punchId, type: r.punchType, at: r.punchedAt),
    ], now);

/// 我的出勤（本人）：同一套規則，只看打卡（補登申請不算）
Set<String> myMissingOutIds(List<MyAttendanceRecord> rows, DateTime now) => _missingOut([
      for (final r in rows)
        if (r.isPunch && r.review != 'rejected' && !r.flags.contains('duplicate'))
          (key: r.storeName, id: r.id, type: r.punchType, at: r.at),
    ], now);

Set<String> _missingOut(List<({String key, String id, String type, DateTime at})> xs, DateTime now) {
  final byPerson = <String, List<({String key, String id, String type, DateTime at})>>{};
  for (final x in xs) {
    byPerson.putIfAbsent(x.key, () => []).add(x);
  }
  final missing = <String>{};
  for (final list in byPerson.values) {
    list.sort((a, b) => a.at.compareTo(b.at));
    for (var i = 0; i < list.length; i++) {
      final r = list[i];
      if (r.type != 'in') continue;
      final limit = r.at.add(const Duration(hours: 14));
      final next = i + 1 < list.length ? list[i + 1] : null;
      if (next == null && now.isBefore(limit)) continue; // 還在上班
      if (next != null && next.type == 'out' && !next.at.isAfter(limit)) continue;
      missing.add(r.id);
    }
  }
  return missing;
}

/// 補登（或打卡）的時間跟班表差幾分鐘（正＝比班表晚）。老闆 2026-11-18：核准補登的畫面要看班表時間，差超過 30 分鐘標紅。
/// range 是班表那格的時段（例 18:00-00:30）；at 是台北的牆上時間；班表沒有時間＝null。
/// 早上 6 點以前開始的班算隔天；下班比上班早＝過午夜。
int? scheduleDiffMinutes({required DateTime businessDate, required String? range, required String punchType, required DateTime at}) {
  final t = scheduleTimes(range, const {});
  if (t == null) return null;
  final d = DateTime(businessDate.year, businessDate.month, businessDate.day);
  var start = d.add(Duration(hours: t.inH, minutes: t.inM));
  if (t.inH < 6) start = start.add(const Duration(days: 1));
  var end = DateTime(start.year, start.month, start.day, t.outH, t.outM);
  if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
  final plan = punchType == 'in' ? start : end;
  final wall = DateTime(at.year, at.month, at.day, at.hour, at.minute);
  return wall.difference(plan).inMinutes;
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
        'punch' => '打卡',
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
        name: labelOfPerson(r['person_id'], r['name'] as String? ?? ''),
        homeStoreName: r['home_store_name'] as String?,
        crossStore: r['cross_store'] as bool? ?? false,
      );
  String get label => crossStore ? '$name（${homeStoreName ?? '別家店'}支援）' : name;
}

// ---------------- 打卡跟班表比對、加班申請（ops 0127，老闆 2026-11-17 第 5、6 點） ----------------

/// 比對班表的異常種類（attendance_schedule_check.issues）
String scheduleIssueLabel(String k) => switch (k) {
      'early_in' => '早到',
      'late_in' => '遲到',
      'early_out' => '早退',
      'late_out' => '晚走',
      'no_schedule' => '沒排班有打卡',
      'no_punch' => '有排班沒打卡',
      _ => k,
    };

/// 打卡跟班表比對的一列：一個人一天（只列有異常的）
class ScheduleCheckRow {
  final DateTime businessDate;
  final String personId;
  final String personName;
  final String? mark; // 班表那格（V、B、18:00-00:30…；沒排班是 null）
  final DateTime? planStart, planEnd; // 班的開始、結束（沒設時間是 null）
  final DateTime? firstIn, lastOut; // 那天第一筆上班、最後一筆下班
  final List<String> issues;
  final int? earlyInMin, lateInMin, earlyOutMin, lateOutMin;
  final bool punchPending; // 有打卡還在待確認
  final double? otApproved; // 那天核准的加班時數
  final bool otPending; // 那天有待審的加班申請
  const ScheduleCheckRow({
    required this.businessDate,
    required this.personId,
    required this.personName,
    this.mark,
    this.planStart,
    this.planEnd,
    this.firstIn,
    this.lastOut,
    this.issues = const [],
    this.earlyInMin,
    this.lateInMin,
    this.earlyOutMin,
    this.lateOutMin,
    this.punchPending = false,
    this.otApproved,
    this.otPending = false,
  });
  factory ScheduleCheckRow.fromRow(Map<String, dynamic> r) => ScheduleCheckRow(
        businessDate: _date(r['business_date']),
        personId: r['person_id'] as String,
        personName: labelOfPerson(r['person_id'], r['person_name'] as String? ?? ''),
        mark: r['mark'] as String?,
        planStart: _tsOrNull(r['plan_start']),
        planEnd: _tsOrNull(r['plan_end']),
        firstIn: _tsOrNull(r['first_in']),
        lastOut: _tsOrNull(r['last_out']),
        issues: _strs(r['issues']),
        earlyInMin: (r['early_in_min'] as num?)?.toInt(),
        lateInMin: (r['late_in_min'] as num?)?.toInt(),
        earlyOutMin: (r['early_out_min'] as num?)?.toInt(),
        lateOutMin: (r['late_out_min'] as num?)?.toInt(),
        punchPending: r['punch_pending'] as bool? ?? false,
        otApproved: _numOrNull(r['ot_approved']),
        otPending: r['ot_pending'] as bool? ?? false,
      );

  int? minutesOf(String issue) => switch (issue) {
        'early_in' => earlyInMin,
        'late_in' => lateInMin,
        'early_out' => earlyOutMin,
        'late_out' => lateOutMin,
        _ => null,
      };

  /// 「早到 40 分」「有排班沒打卡」
  String issueText(String issue) {
    final m = minutesOf(issue);
    return m == null ? scheduleIssueLabel(issue) : '${scheduleIssueLabel(issue)} ${durationLabel(m)}';
  }

  /// 晚走但沒有核准、也沒有待審的加班
  bool get lateWithoutOvertime => issues.contains('late_out') && (otApproved ?? 0) == 0 && !otPending;

  /// 晚走幾分鐘換成加班時數的建議值（往下取到 0.5 小時，最少 0.5）
  double get suggestedOvertimeHours {
    final m = lateOutMin ?? 0;
    final h = (m ~/ 30) / 2;
    return h < 0.5 ? 0.5 : (h > 12 ? 12 : h);
  }
}

/// 75 → 「1 小時 15 分」、40 → 「40 分」
String durationLabel(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m 分';
  return m == 0 ? '$h 小時' : '$h 小時 $m 分';
}

/// 加班時數顯示：2.0 → 「2」、2.5 → 「2.5」
String hoursLabel(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toString();

/// 加班申請（attendance_overtime_list）
class OvertimeRequest {
  final String id;
  final String personId;
  final String personName;
  final DateTime businessDate;
  final double hours;
  final String reason;
  final bool afterTheFact; // 事後申請
  final String status; // pending／approved／rejected／cancelled
  final double? approvedHours;
  final String? requestedByName;
  final DateTime requestedAt;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionNote;
  final bool mine; // 我送出的（可以撤回還沒審的）
  final bool canDecide; // 我可以審（老闆；店長不能審自己的）
  const OvertimeRequest({
    required this.id,
    required this.personId,
    required this.personName,
    required this.businessDate,
    required this.hours,
    required this.reason,
    this.afterTheFact = false,
    this.status = 'pending',
    this.approvedHours,
    this.requestedByName,
    required this.requestedAt,
    this.decidedByName,
    this.decidedAt,
    this.decisionNote,
    this.mine = false,
    this.canDecide = false,
  });
  factory OvertimeRequest.fromRow(Map<String, dynamic> r) => OvertimeRequest(
        id: r['id'] as String,
        personId: r['person_id'] as String,
        personName: labelOfPerson(r['person_id'], r['person_name'] as String? ?? ''),
        businessDate: _date(r['business_date']),
        hours: (r['hours'] as num).toDouble(),
        reason: r['reason'] as String? ?? '',
        afterTheFact: r['after_the_fact'] as bool? ?? false,
        status: r['status'] as String? ?? 'pending',
        approvedHours: _numOrNull(r['approved_hours']),
        requestedByName: r['requested_by_name'] as String?,
        requestedAt: _ts(r['requested_at']),
        decidedByName: r['decided_by_name'] as String?,
        decidedAt: _tsOrNull(r['decided_at']),
        decisionNote: r['decision_note'] as String?,
        mine: r['mine'] as bool? ?? false,
        canDecide: r['can_decide'] as bool? ?? false,
      );

  bool get pending => status == 'pending';
  String get statusLabel => switch (status) {
        'pending' => '待審',
        'approved' => approvedHours != null && approvedHours != hours ? '已核准 ${hoursLabel(approvedHours!)} 小時' : '已核准',
        'rejected' => '已退回',
        'cancelled' => '已撤回',
        _ => status,
      };
}

/// 隱城 V、O 的時間（shift_mark_times；weekday 0＝平常，1＝週一…7＝週日另設）
class ShiftMarkTime {
  final String mark;
  final int weekday;
  final String timeRange;
  const ShiftMarkTime({required this.mark, this.weekday = 0, required this.timeRange});
  factory ShiftMarkTime.fromRow(Map<String, dynamic> r) =>
      ShiftMarkTime(mark: r['mark'] as String, weekday: (r['weekday'] as num?)?.toInt() ?? 0, timeRange: r['time_range'] as String);
}

const weekdayLabels = ['平常', '週一', '週二', '週三', '週四', '週五', '週六', '週日'];

/// 某一天 V／O 的時間：那個星期另設的優先，沒有就用平常的
String? markTimeOn(List<ShiftMarkTime> times, String mark, DateTime day) =>
    (times.where((t) => t.mark == mark && t.weekday == day.weekday).firstOrNull ??
            times.where((t) => t.mark == mark && t.weekday == 0).firstOrNull)
        ?.timeRange;
