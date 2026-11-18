// 員工顯示用的名字（ops 0125；老闆 2026-11-18：所有畫面一律只顯示全名，ops 0128）。

/// 有全名就只顯示全名；沒填全名＝照舊顯示暱稱（跟資料庫 app.person_label 一樣）
String personLabel(String name, String? fullName) {
  if (fullName == null || fullName.isEmpty) return name;
  return fullName;
}

/// 這次開 App 讀過的班表人員：id → 顯示用的名字。
/// 出勤、薪資那些畫面從資料庫只拿到暱稱，用人的 id 來這裡換成全名；
/// 沒讀過的人（例如別家店來支援的）照原樣顯示。
final Map<String, String> _labels = {};
void rememberPersonLabel(String personId, String label) => _labels[personId] = label;
String labelOfPerson(Object? personId, String fallback) => _labels[personId] ?? fallback;

/// 只要全名（薪資單上的姓名，ops 0126）：id → 全名；沒填全名的是班表上的名字
final Map<String, String> _fullNames = {};
void rememberPersonFullName(String personId, String fullName) => _fullNames[personId] = fullName;
String fullNameOfPerson(Object? personId, String fallback) => _fullNames[personId] ?? fallback;
