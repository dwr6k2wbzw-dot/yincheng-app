import 'repository.dart';

/// 打卡設定（ops 0163）：每家店自己設的打卡規則。
/// 老闆、店長讀得到（店長要用寬限把差太多的時間標紅）；只有老闆能改，改了記在出勤異動紀錄。
class AttendanceSettings {
  const AttendanceSettings({
    required this.enabled,
    required this.graceMin,
    this.checkFrom,
    this.amendOwnerAfter = 3,
    this.managerPayroll = true,
    this.canEdit = false,
  });

  /// 讀不到時（還沒更新的資料庫、斷線）照以前的規則：寬限 30、補登 3
  static const fallback = AttendanceSettings(enabled: false, graceMin: 30);

  /// 開放打卡
  final bool enabled;

  /// 跟班表差幾分鐘以上算異常（5～180）
  final int graceMin;

  /// 異常、比對班表從這天起才列（null＝不限）
  final DateTime? checkFrom;

  /// 同一個人一個月補登核准幾筆以後，要老闆才能核准（null＝不限；0＝每一筆都要老闆）
  final int? amendOwnerAfter;

  /// 店長看得到薪資
  final bool managerPayroll;

  /// 這個帳號能不能改（只有老闆）
  final bool canEdit;

  factory AttendanceSettings.fromJson(Map<String, dynamic> j) {
    final from = j['check_from'];
    return AttendanceSettings(
      enabled: j['enabled'] == true,
      graceMin: (j['grace_min'] as num?)?.toInt() ?? 30,
      checkFrom: from == null ? null : DateTime.tryParse(from.toString()),
      amendOwnerAfter: (j['amend_owner_after'] as num?)?.toInt(),
      managerPayroll: j['manager_payroll'] != false,
      canEdit: j['can_edit'] == true,
    );
  }

  AttendanceSettings copyWith({
    bool? enabled,
    int? graceMin,
    DateTime? Function()? checkFrom,
    int? Function()? amendOwnerAfter,
    bool? managerPayroll,
  }) => AttendanceSettings(
    enabled: enabled ?? this.enabled,
    graceMin: graceMin ?? this.graceMin,
    checkFrom: checkFrom != null ? checkFrom() : this.checkFrom,
    amendOwnerAfter: amendOwnerAfter != null
        ? amendOwnerAfter()
        : this.amendOwnerAfter,
    managerPayroll: managerPayroll ?? this.managerPayroll,
    canEdit: canEdit,
  );

  /// 跟 [before] 比，只送有改的項目（ops attendance_settings_set 的格式）
  Map<String, Object?> changesFrom(AttendanceSettings before) => {
    if (enabled != before.enabled) 'enabled': enabled,
    if (graceMin != before.graceMin) 'grace_min': graceMin,
    if (!_sameDay(checkFrom, before.checkFrom))
      'check_from': checkFrom == null ? null : _ymd(checkFrom!),
    if (amendOwnerAfter != before.amendOwnerAfter)
      'amend_owner_after': amendOwnerAfter,
    if (managerPayroll != before.managerPayroll)
      'manager_payroll': managerPayroll,
  };

  /// 補登規則的一句話（說明文字用）
  String get amendRuleLabel => switch (amendOwnerAfter) {
    null => '補登店長都能核准',
    0 => '每一筆補登都要老闆核准',
    final n => '同一個人一個月第 ${n + 1} 次補登起只有老闆能核准',
  };
}

bool _sameDay(DateTime? a, DateTime? b) =>
    (a == null && b == null) ||
    (a != null &&
        b != null &&
        a.year == b.year &&
        a.month == b.month &&
        a.day == b.day);

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 寬限分鐘數打錯的原因（null＝沒問題）
String? attendanceGraceProblem(String text) {
  final n = int.tryParse(text.trim());
  if (n == null) return '寬限請填數字（分鐘）';
  if (n < 5 || n > 180) return '寬限要在 5～180 分鐘之間';
  return null;
}

/// 補登次數打錯的原因（null＝沒問題）
String? attendanceAmendProblem(String text) {
  final n = int.tryParse(text.trim());
  if (n == null) return '補登次數請填數字';
  if (n < 0 || n > 31) return '補登次數要在 0～31 之間';
  return null;
}

/// 讀這家店的打卡設定；讀不到（資料庫還沒更新、斷線、沒有權限）就照以前的規則
Future<AttendanceSettings> attendanceSettingsOrFallback(
  Repository repo,
  String storeId,
) async {
  try {
    return await repo.attendanceSettings(storeId);
  } catch (_) {
    return AttendanceSettings.fallback;
  }
}
