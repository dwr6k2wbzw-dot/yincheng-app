/// 訂位（0050）：客人在公開訂位頁訂、員工在 App 管理
class ReservationSettings {
  final String storeId;
  final String slug;
  final bool enabled;
  final String displayName;
  final String firstSlot; // HH:mm
  final String lastSlot;
  final int slotMinutes;
  final int maxGuestsPerSlot;
  final int maxParty;
  final int daysAhead;
  final String sameDayCutoff; // HH:mm
  final String? contactNote;
  // 0052 每天名額（null＝不限）、大桌、每週公休、未到幾次擋線上訂位
  final int? maxGroupsPerDay;
  final int? maxGuestsPerDay;
  final int largePartySize;
  final int? maxLargePerDay;
  final List<int> closedWeekdays; // 1＝週一 … 7＝週日
  final int noshowBlockCount; // 0＝不擋
  // 0054 自訂時段清單（空的＝照第一～最後每 N 分鐘）、地址、電話
  final List<String> slotTimes;
  final String? address;
  final String? phone;
  // 0063 依星期另設時段（1＝週一…7＝週日；沒設的照 slots）
  final Map<int, List<String>> weekdaySlotTimes;
  const ReservationSettings({
    required this.storeId,
    required this.slug,
    required this.enabled,
    required this.displayName,
    required this.firstSlot,
    required this.lastSlot,
    required this.slotMinutes,
    required this.maxGuestsPerSlot,
    required this.maxParty,
    required this.daysAhead,
    required this.sameDayCutoff,
    this.contactNote,
    this.maxGroupsPerDay,
    this.maxGuestsPerDay,
    this.largePartySize = 4,
    this.maxLargePerDay,
    this.closedWeekdays = const [],
    this.noshowBlockCount = 2,
    this.slotTimes = const [],
    this.address,
    this.phone,
    this.weekdaySlotTimes = const {},
  });
  factory ReservationSettings.fromRow(Map<String, dynamic> r) => ReservationSettings(
        storeId: r['store_id'] as String,
        slug: r['slug'] as String,
        enabled: r['enabled'] as bool? ?? true,
        displayName: r['display_name'] as String? ?? '',
        firstSlot: hm(r['first_slot']),
        lastSlot: hm(r['last_slot']),
        slotMinutes: (r['slot_minutes'] as num?)?.toInt() ?? 30,
        maxGuestsPerSlot: (r['max_guests_per_slot'] as num?)?.toInt() ?? 20,
        maxParty: (r['max_party'] as num?)?.toInt() ?? 6,
        daysAhead: (r['days_ahead'] as num?)?.toInt() ?? 7,
        sameDayCutoff: hm(r['same_day_cutoff']),
        contactNote: r['contact_note'] as String?,
        maxGroupsPerDay: (r['max_groups_per_day'] as num?)?.toInt(),
        maxGuestsPerDay: (r['max_guests_per_day'] as num?)?.toInt(),
        largePartySize: (r['large_party_size'] as num?)?.toInt() ?? 4,
        maxLargePerDay: (r['max_large_groups_per_day'] as num?)?.toInt(),
        closedWeekdays: [for (final x in (r['closed_weekdays'] as List? ?? const [])) (x as num).toInt()],
        noshowBlockCount: (r['noshow_block_count'] as num?)?.toInt() ?? 2,
        slotTimes: [for (final x in (r['slot_times'] as List? ?? const [])) hm(x)],
        address: r['address'] as String?,
        phone: r['phone'] as String?,
        weekdaySlotTimes: {
          for (final e in ((r['weekday_slot_times'] as Map?) ?? const {}).entries)
            if (int.tryParse('${e.key}') != null && e.value is List && (e.value as List).isNotEmpty)
              int.parse('${e.key}'): ([for (final x in e.value as List) hm(x)]..sort()),
        },
      );

  /// 這一天的時段：那個星期有另外設定就用它，否則照平常的時段（0063）
  List<String> slotsFor(DateTime day) => weekdaySlotTimes[day.weekday] ?? slots;

  /// 這一天的上限（特殊日期優先；每週公休＝不開放線上訂位）
  DayLimits limitsFor(DateTime day, ReservationSpecialDay? sp) => DayLimits(
        closed: sp != null ? sp.closed : closedWeekdays.contains(day.weekday),
        note: sp?.note,
        maxGroups: sp?.maxGroups ?? maxGroupsPerDay,
        maxGuests: sp?.maxGuests ?? maxGuestsPerDay,
        maxLarge: sp?.maxLarge ?? maxLargePerDay,
        largeSize: largePartySize,
      );

  /// 所有時段（例：19:00、19:30 … 23:00）
  List<String> get slots {
    if (slotTimes.isNotEmpty) return ([...slotTimes]..sort());
    final out = <String>[];
    var m = minutesOf(firstSlot);
    final end = minutesOf(lastSlot);
    while (m <= end && out.length < 200) {
      out.add('${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}');
      m += slotMinutes;
    }
    return out;
  }
}

class Reservation {
  final String id;
  final DateTime date;
  final String time; // HH:mm
  final int party;
  final String name;
  final String phone;
  final String? email;
  final String? note;
  final String status; // confirmed / cancelled / arrived / no_show
  final String source; // web / app
  final String? emailError;
  final DateTime createdAt;
  // 0055 客人申請改人數（pending 待確認／approved／rejected）
  final int? requestedParty;
  final String? partyRequestStatus;
  final String lang; // 0058 客人訂位時選的語言 zh／en／ja
  // 0061 時間軸：排到哪幾張桌（併桌＝多張）、入座／清桌時間、現場客
  final List<String> tableIds;
  final DateTime? seatedAt;
  final DateTime? clearedAt;
  final bool walkIn;
  final DateTime? hiddenAt; // 0064 已取消的訂位被滑掉隱藏（大家都看不到，資料還在）
  const Reservation({
    required this.id,
    required this.date,
    required this.time,
    required this.party,
    required this.name,
    required this.phone,
    this.email,
    this.note,
    required this.status,
    required this.source,
    this.emailError,
    required this.createdAt,
    this.requestedParty,
    this.partyRequestStatus,
    this.lang = 'zh',
    this.tableIds = const [],
    this.seatedAt,
    this.clearedAt,
    this.walkIn = false,
    this.hiddenAt,
  });
  factory Reservation.fromRow(Map<String, dynamic> r) => Reservation(
        id: r['id'] as String,
        date: DateTime.parse(r['slot_date'] as String),
        time: hm(r['slot_time']),
        party: (r['party_size'] as num).toInt(),
        name: r['guest_name'] as String,
        phone: r['phone'] as String? ?? '', // 0057 電話訂位可以不留電話（空字串）
        email: r['email'] as String?,
        note: r['note'] as String?,
        status: r['status'] as String,
        source: r['source'] as String,
        emailError: r['email_error'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        requestedParty: (r['requested_party'] as num?)?.toInt(),
        partyRequestStatus: r['party_request_status'] as String?,
        lang: r['lang'] as String? ?? 'zh',
        tableIds: [for (final x in (r['table_ids'] as List? ?? const [])) x as String],
        seatedAt: r['seated_at'] == null ? null : DateTime.parse(r['seated_at'] as String).toLocal(),
        clearedAt: r['cleared_at'] == null ? null : DateTime.parse(r['cleared_at'] as String).toLocal(),
        walkIn: r['walk_in'] as bool? ?? false,
        hiddenAt: r['hidden_at'] == null ? null : DateTime.parse(r['hidden_at'] as String).toLocal(),
      );

  /// 示範模式用：改幾個欄位
  Reservation copyWith({String? status, String? note, bool clearNote = false, List<String>? tableIds, DateTime? seatedAt,
          bool clearSeated = false, DateTime? clearedAt, bool clearCleared = false, int? party, String? partyRequestStatus, DateTime? hiddenAt, bool clearHidden = false}) =>
      Reservation(
        id: id, date: date, time: time, party: party ?? this.party, name: name, phone: phone, email: email,
        note: clearNote ? null : (note ?? this.note), status: status ?? this.status, source: source, emailError: emailError,
        createdAt: createdAt, requestedParty: requestedParty, partyRequestStatus: partyRequestStatus ?? this.partyRequestStatus,
        lang: lang, tableIds: tableIds ?? this.tableIds, seatedAt: clearSeated ? null : (seatedAt ?? this.seatedAt),
        clearedAt: clearCleared ? null : (clearedAt ?? this.clearedAt), walkIn: walkIn,
        hiddenAt: clearHidden ? null : (hiddenAt ?? this.hiddenAt),
      );
  bool get partyPending => partyRequestStatus == 'pending' && requestedParty != null && status == 'confirmed';
  bool get active => status == 'confirmed' || status == 'arrived';
}

const reservationStatusLabel = {'confirmed': '已確認', 'arrived': '已入座', 'no_show': '未到', 'cancelled': '已取消'};

/// 桌位（0061）：桌號、人數、可併桌；老闆／店長在 App 設定
class ReservationTable {
  final String id; // 空字串＝新的
  final String name;
  final int seats;
  final bool combinable;
  final int sort;
  final bool active;
  /// 座位圖（老闆 2026-11-01）：在平面圖上的格子位置與大小（格子為單位）；posX／posY 是 null＝還沒排，照 sort 自動排
  final int? posX;
  final int? posY;
  final int w;
  final int h;
  /// 桌形：round 圓桌（吧台單人座、小圓桌）／square 方桌（照 iCHEF 座位表）
  final String shape;
  bool get isRound => shape != 'square';
  /// 樓層（座位圖分頁，照 iCHEF：1F／2F／3F）
  final String floor;
  const ReservationTable({
    this.id = '',
    required this.name,
    this.seats = 2,
    this.combinable = false,
    this.sort = 0,
    this.active = true,
    this.posX,
    this.posY,
    this.w = 1,
    this.h = 1,
    this.shape = 'round',
    this.floor = '1F',
  });
  bool get placed => posX != null && posY != null;
  ReservationTable copyWith({int? posX, int? posY, int? w, int? h, String? shape, String? floor, bool clearPos = false}) => ReservationTable(
        id: id,
        name: name,
        seats: seats,
        combinable: combinable,
        sort: sort,
        active: active,
        posX: clearPos ? null : (posX ?? this.posX),
        posY: clearPos ? null : (posY ?? this.posY),
        w: w ?? this.w,
        h: h ?? this.h,
        shape: shape ?? this.shape,
        floor: floor ?? this.floor,
      );
  factory ReservationTable.fromRow(Map<String, dynamic> r) => ReservationTable(
        id: r['id'] as String,
        name: r['name'] as String,
        seats: (r['seats'] as num).toInt(),
        combinable: r['combinable'] as bool? ?? false,
        sort: (r['sort'] as num?)?.toInt() ?? 0,
        active: r['active'] as bool? ?? true,
        posX: (r['pos_x'] as num?)?.toInt(),
        posY: (r['pos_y'] as num?)?.toInt(),
        w: ((r['w'] as num?)?.toInt() ?? 1).clamp(1, 4),
        h: ((r['h'] as num?)?.toInt() ?? 1).clamp(1, 4),
        shape: (r['shape'] as String?) ?? 'round',
        floor: (r['floor'] as String?) ?? '1F',
      );
}

String hm(Object? v) {
  final s = (v ?? '00:00').toString();
  return s.length >= 5 ? s.substring(0, 5) : s;
}

int minutesOf(String hhmm) {
  final p = hhmm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

/// 公開訂位頁網址
// 各店專屬網址（分享到 LINE／IG 會出現店家照片的預覽卡；老闆 2026-10-18）；舊的 ?s= 網址照樣能用
String reservationPageUrl(String slug) => 'https://dwr6k2wbzw-dot.github.io/yincheng-app/book/$slug/';


/// 某一天的線上訂位上限（0052）
class DayLimits {
  final bool closed;
  final String? note;
  final int? maxGroups, maxGuests, maxLarge;
  final int largeSize;
  const DayLimits({required this.closed, this.note, this.maxGroups, this.maxGuests, this.maxLarge, required this.largeSize});

  /// 加上這一組後會超過哪些上限（空的＝沒超過）
  List<String> overBy(List<Reservation> others, int party) {
    final act = others.where((r) => r.active).toList();
    final groups = act.length + 1;
    final guests = act.fold<int>(0, (t, r) => t + r.party) + party;
    final large = act.where((r) => r.party >= largeSize).length + (party >= largeSize ? 1 : 0);
    return [
      if (closed) '這天不開放線上訂位${note == null ? '' : '（$note）'}',
      if (maxGroups != null && groups > maxGroups!) '一天最多 $maxGroups 組（加上這組是 $groups 組）',
      if (maxGuests != null && guests > maxGuests!) '一天最多 $maxGuests 位（加上這組是 $guests 位）',
      if (party >= largeSize && maxLarge != null && large > maxLarge!) '$largeSize 位以上一天最多 $maxLarge 組（加上這組是 $large 組）',
    ];
  }
}

/// 特殊日期（0052）：整天不開放，或改名額；欄位 null＝照平常
class ReservationSpecialDay {
  final DateTime day;
  final bool closed;
  final int? maxGroups, maxGuests, maxLarge;
  final String? note;
  const ReservationSpecialDay({required this.day, this.closed = false, this.maxGroups, this.maxGuests, this.maxLarge, this.note});
  factory ReservationSpecialDay.fromRow(Map<String, dynamic> r) => ReservationSpecialDay(
        day: DateTime.parse(r['day'] as String),
        closed: r['closed'] as bool? ?? false,
        maxGroups: (r['max_groups'] as num?)?.toInt(),
        maxGuests: (r['max_guests'] as num?)?.toInt(),
        maxLarge: (r['max_large'] as num?)?.toInt(),
        note: r['note'] as String?,
      );
}

/// 熟客資料（0052）：以電話數字對回
class GuestProfile {
  final String phoneDigits;
  final List<String> tags;
  final String? note;
  final DateTime? noshowResetAt;
  const GuestProfile({required this.phoneDigits, this.tags = const [], this.note, this.noshowResetAt});
  factory GuestProfile.fromRow(Map<String, dynamic> r) => GuestProfile(
        phoneDigits: r['phone_digits'] as String,
        tags: [for (final t in (r['tags'] as List? ?? const [])) t as String],
        note: r['note'] as String?,
        noshowResetAt: r['noshow_reset_at'] == null ? null : DateTime.parse(r['noshow_reset_at'] as String).toLocal(),
      );
}

/// 一位客人在這家店的紀錄（App 端算）：來過幾次、未到幾次（解除那天以後）
class GuestStats {
  final int visits;
  final int noShows;
  final GuestProfile? profile;
  const GuestStats(this.visits, this.noShows, this.profile);
}

String phoneDigitsOf(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

const guestTagPresets = ['VIP', '熟客', '吧台', '生日', '過敏', '素食', '不吃辣'];
