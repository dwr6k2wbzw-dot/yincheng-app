// 員工顯示用的名字（ops 0125，老闆 2026-11-17：員工一律顯示全名，暱稱放括號）。

/// 全名（暱稱）。沒填全名＝照舊顯示暱稱；暱稱已經在全名裡就只顯示全名（跟資料庫 app.person_label 一樣）
String personLabel(String name, String? fullName) {
  if (fullName == null || fullName.isEmpty) return name;
  return fullName.contains(name) ? fullName : '$fullName（$name）';
}

/// 這次開 App 讀過的班表人員：id → 顯示用的名字。
/// 出勤、薪資那些畫面從資料庫只拿到暱稱，用人的 id 來這裡換成「全名（暱稱）」；
/// 沒讀過的人（例如別家店來支援的）照原樣顯示。
final Map<String, String> _labels = {};
void rememberPersonLabel(String personId, String label) => _labels[personId] = label;
String labelOfPerson(Object? personId, String fallback) => _labels[personId] ?? fallback;

/// 只要全名（薪資單上的姓名，ops 0126）：id → 全名；沒填全名的是班表上的名字
final Map<String, String> _fullNames = {};
void rememberPersonFullName(String personId, String fullName) => _fullNames[personId] = fullName;
String fullNameOfPerson(Object? personId, String fallback) => _fullNames[personId] ?? fallback;
