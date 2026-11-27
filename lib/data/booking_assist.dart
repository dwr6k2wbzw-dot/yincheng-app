import 'booking_profile.dart';
import 'shift_planner.dart';

/// AI 設定助理的一項建議：訂位（ops 0147：text／min_spend／langs／day）、
/// 排班（ops 0154：staffing／staffing_day／setting／rule）。原樣（[raw]）送回資料庫套用，畫面只用來顯示。
class AssistChange {
  const AssistChange(this.raw);
  final Map<String, dynamic> raw;
  String get op => raw['op'] as String? ?? '';

  static const fieldNames = {
    'title': '大標',
    'short_name': '簡稱',
    'intro': '介紹',
    'address_i18n': '地址',
    'directions_i18n': '交通說明',
    'min_spend_text': '低消說明',
  };

  // 排班（ops 0154）
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const settingNames = {
    'request_deadline': '填班截止日',
    'prefer_run': '盡量不連上',
    'off_per_day': '同一天最多幾位指休',
    'off_month_max': '每人每月最多指休',
  };
  static const ruleNames = {
    'month_off': '每月休幾天',
    'min_shifts': '每月最少上幾天',
    'max_shifts': '每月最多上幾天',
    'max_consecutive': '最多連上幾天',
    'no_weekdays': '固定不排的星期',
  };

  /// 這一項在改什麼（例：「介紹（English）」「12/5（週五）」）
  String get label {
    switch (op) {
      case 'text':
        final lang = BookingProfile.langNames[raw['lang']] ?? '${raw['lang']}';
        return '${fieldNames[raw['field']] ?? raw['field']}（$lang）';
      case 'min_spend':
        return '每人低消';
      case 'langs':
        return '訂位頁的語言';
      case 'day':
        return dayLabel(raw['date'] as String? ?? '');
      case 'staffing':
        final w = raw['weekday'];
        return w is int && w >= 1 && w <= 7 ? '每週${_weekdays[w - 1]}要幾人' : '每天要幾人';
      case 'staffing_day':
        return '${dayLabel(raw['date'] as String? ?? '')}要幾人';
      case 'setting':
        return settingNames[raw['field']] ?? '${raw['field']}';
      case 'rule':
        return '${raw['person_name'] ?? ''}・${ruleNames[raw['field']] ?? raw['field']}';
      default:
        return op;
    }
  }

  String get beforeText => _show(raw['before']);
  String get afterText => _show(raw['after']);

  String _show(Object? v) {
    switch (op) {
      case 'text':
        return v is String && v.isNotEmpty ? v : '（沒有）';
      case 'min_spend':
        return v is num ? '${v.toInt()} 元' : '（不顯示）';
      case 'langs':
        return v is List
            ? v.map((l) => BookingProfile.langNames[l] ?? '$l').join('、')
            : '';
      case 'day':
        if (v is Map && v['closed'] == true) {
          final note = v['note'];
          return note is String && note.isNotEmpty ? '整天不開放（$note）' : '整天不開放';
        }
        return '照平常開放';
      case 'staffing':
        if (v is Map) {
          final full = v['min_full'];
          return '${v['need']} 人${full is num && full > 0 ? '（正職至少 $full）' : ''}';
        }
        return '（沒設）';
      case 'staffing_day':
        return v is Map ? '${v['need']} 人' : '照星期的人數';
      case 'setting':
        // 空白的意思要跟排班實際算法一致（Codex P2）
        if (v == null) {
          return raw['field'] == 'prefer_run' ? '不設（只看每個人的最多連上幾天）' : '不限';
        }
        return switch (raw['field']) {
          'request_deadline' => '每月 $v 號',
          'off_per_day' => '$v 位',
          _ => '$v 天',
        };
      case 'rule':
        if (raw['field'] == 'no_weekdays') {
          return v is List && v.isNotEmpty
              ? v.map((d) => d is int && d >= 1 && d <= 7 ? '週${_weekdays[d - 1]}' : '$d').join('、')
              : '（沒有）';
        }
        // 空白＝排班照預設算（shift_auto_plan_screen）：最多連上 6 天、休幾天照當月應休、最少／最多天數不設限
        if (v == null) {
          return switch (raw['field']) {
            'max_consecutive' => '$defaultMaxConsecutive 天（預設）',
            'month_off' => '照當月應休（沒填約每月 9 天）',
            'min_shifts' => '沒有下限',
            'max_shifts' => '沒有上限',
            _ => '不限',
          };
        }
        final n = v is num && v == v.roundToDouble() ? v.toInt() : v;
        return '$n 天';
      default:
        return '$v';
    }
  }

  static String dayLabel(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const w = ['一', '二', '三', '四', '五', '六', '日'];
    return '${d.month}/${d.day}（週${w[d.weekday - 1]}）';
  }
}

/// AI 回覆：一兩句話＋建議（可能沒有）＋做不到的原因
class AssistReply {
  const AssistReply(
      {required this.reply, this.changes = const [], this.skipped = const []});
  final String reply;
  final List<AssistChange> changes;
  final List<String> skipped;
  factory AssistReply.fromJson(Map<String, dynamic> j) => AssistReply(
        reply: j['reply'] as String? ?? '',
        changes: [
          for (final c in (j['changes'] as List? ?? const []))
            if (c is Map) AssistChange(Map<String, dynamic>.from(c)),
        ],
        skipped: [for (final s in (j['skipped'] as List? ?? const [])) '$s'],
      );
}

/// 套用過的一筆（可以整筆改回去）
class AssistRecord {
  const AssistRecord(
      {required this.id,
      required this.appliedAt,
      this.request,
      required this.changes,
      this.undoneAt});
  final String id;
  final DateTime appliedAt;
  final String? request;
  final List<AssistChange> changes;
  final DateTime? undoneAt;
  factory AssistRecord.fromRow(Map<String, dynamic> r) => AssistRecord(
        id: r['id'] as String,
        appliedAt: DateTime.parse(r['applied_at'] as String).toLocal(),
        request: r['request'] as String?,
        changes: [
          for (final c in (r['changes'] as List? ?? const []))
            if (c is Map) AssistChange(Map<String, dynamic>.from(c)),
        ],
        undoneAt: r['undone_at'] == null
            ? null
            : DateTime.parse(r['undone_at'] as String).toLocal(),
      );
}

/// 對話裡的一則
class AssistTurn {
  AssistTurn.user(this.text)
      : fromUser = true,
        reply = null;
  AssistTurn.ai(AssistReply r)
      : fromUser = false,
        text = r.reply,
        reply = r;
  final bool fromUser;
  final String text;
  final AssistReply? reply;

  /// 建議卡片的狀態：null＝還沒決定、true＝套用了、false＝不用
  bool? applied;
}
