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
      );

  /// 所有時段（例：19:00、19:30 … 23:00）
  List<String> get slots {
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
  });
  factory Reservation.fromRow(Map<String, dynamic> r) => Reservation(
        id: r['id'] as String,
        date: DateTime.parse(r['slot_date'] as String),
        time: hm(r['slot_time']),
        party: (r['party_size'] as num).toInt(),
        name: r['guest_name'] as String,
        phone: r['phone'] as String,
        email: r['email'] as String?,
        note: r['note'] as String?,
        status: r['status'] as String,
        source: r['source'] as String,
        emailError: r['email_error'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );
  bool get active => status == 'confirmed' || status == 'arrived';
}

const reservationStatusLabel = {'confirmed': '已確認', 'arrived': '已到店', 'no_show': '未到', 'cancelled': '已取消'};

String hm(Object? v) {
  final s = (v ?? '00:00').toString();
  return s.length >= 5 ? s.substring(0, 5) : s;
}

int minutesOf(String hhmm) {
  final p = hhmm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

/// 公開訂位頁網址
String reservationPageUrl(String slug) => 'https://dwr6k2wbzw-dot.github.io/yincheng-app/book/?s=$slug';
