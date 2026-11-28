/// 打卡設定進度（ops 0164，公版階段 4）：新店從零開始用打卡，一步一步做完。
/// 資料來自 `attendance_setup_status(store)`（老闆、店長）。
library;

class SetupPerson {
  const SetupPerson(this.id, this.name);
  final String id;
  final String name;

  static List<SetupPerson> listFrom(Object? v) => [
    for (final x in (v as List?) ?? const [])
      if (x is Map) SetupPerson('${x['id']}', '${x['name'] ?? ''}'),
  ];
}

/// 每一步：做完了沒、要不要做（員工對應帳號是建議，不做也能打卡）
enum SetupStep { enable, kiosk, accounts, pins, times, test }

class AttendanceSetupStatus {
  const AttendanceSetupStatus({
    required this.canOwner,
    required this.enabled,
    this.kioskName,
    this.kioskInviteUntil,
    required this.people,
    this.unbound = const [],
    this.noPin = const [],
    required this.shiftCodes,
    required this.hasTime,
    this.untimed = const [],
    this.lastPinPunch,
  });

  /// 自己是老闆（打開打卡、打卡用帳號只有老闆能做）
  final bool canOwner;
  final bool enabled;
  final String? kioskName;

  /// 還沒用的打卡用邀請碼到幾點（沒有＝null）
  final DateTime? kioskInviteUntil;

  /// 班表上還在、要打卡的人數（不用打卡的特例不算）
  final int people;
  final List<SetupPerson> unbound;
  final List<SetupPerson> noPin;

  /// 用班別代碼的店（班的時間在班表的「班別／時段」設）；關＝V／O 記號
  final bool shiftCodes;
  final bool hasTime;

  /// 這個月、下個月班表上排了，卻算不出時間的記號
  final List<String> untimed;
  final DateTime? lastPinPunch;

  factory AttendanceSetupStatus.fromJson(Map<String, dynamic> j) =>
      AttendanceSetupStatus(
        canOwner: j['can_owner'] == true,
        enabled: j['enabled'] == true,
        kioskName: (j['kiosk'] as Map?)?['name'] as String?,
        kioskInviteUntil: DateTime.tryParse('${j['kiosk_invite_until'] ?? ''}'),
        people: (j['people'] as num?)?.toInt() ?? 0,
        unbound: SetupPerson.listFrom(j['unbound']),
        noPin: SetupPerson.listFrom(j['no_pin']),
        shiftCodes: j['shift_codes'] == true,
        hasTime: j['has_time'] == true,
        untimed: [for (final x in (j['untimed'] as List?) ?? const []) '$x'],
        lastPinPunch: DateTime.tryParse('${j['last_pin_punch'] ?? ''}'),
      );

  bool done(SetupStep s) => switch (s) {
    SetupStep.enable => enabled,
    SetupStep.kiosk => kioskName != null,
    SetupStep.accounts => people > 0 && unbound.isEmpty,
    SetupStep.pins => people > 0 && noPin.isEmpty,
    SetupStep.times => hasTime && untimed.isEmpty,
    SetupStep.test => lastPinPunch != null,
  };

  /// 一定要做的（員工對應帳號是建議）
  static const required = [
    SetupStep.enable,
    SetupStep.kiosk,
    SetupStep.pins,
    SetupStep.times,
    SetupStep.test,
  ];

  int get requiredDone => required.where(done).length;
  bool get ready => requiredDone == required.length;
}
