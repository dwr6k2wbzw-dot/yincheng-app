/// 連線設定。可用 --dart-define 覆寫：
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=... --dart-define=DEMO=false
/// publishable／anon key 本來就會放在 App 裡，屬於公開金鑰；service_role key 絕對不要放進 App。
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yfulcyeoqavqarpfnznw.supabase.co', // Staging
  );
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_qRkNUf71em4UTxNaUuJ4DA_iu_KyN6Y', // Staging publishable key
  );

  /// true：使用內建示範資料（不連線），方便先看畫面
  static const demo = bool.fromEnvironment('DEMO', defaultValue: false);

  /// true：公版那一份 App——登入頁可以不用邀請碼註冊，沒有任何店的帳號可以自己建立一家店（ops 0119）。
  /// 隱城／小城外這一份不開（資料庫那邊的開關也是關的，開了這個參數也建不了）。
  static const selfSignup = bool.fromEnvironment('SELF_SIGNUP', defaultValue: false);

  // 每家店的功能開關（班表分頁、以日報表為準、營收四項、銷貨單…）改放資料庫（0116），見 data/store_features.dart

  // 班表的記號、班別時段與時數不寫在這裡：記號看功能開關 shiftCodes，班別／時段在資料庫 shift_mark_options（見 data/shift_marks.dart）

  /// 進貨類別的顯示順序（老闆指定；沒列到的照原本順序排在後面）
  static const categoryOrder = [
    'xc_bar_liquor', 'xc_bar_supply', 'xc_bar_food', 'xc_bar_misc', // 酒吧：酒水、酒水副材料、食材、雜項
    'xc_cafe_food', 'xc_cafe_misc', // 咖啡吧：食材、雜項
    'xc_ramen_broth', 'xc_ramen_food', 'xc_ramen_misc', // 布布拉麵：高湯、食材、雜項
  ];

  /// 新增進貨類別後面的說明（老闆 2026-10-13：移除所有常用廠商提示，只留雜項的說明）
  static const categoryNote = {
    'yc_misc': '非酒材與食材的項目皆列為雜項',
    'xc_bar_misc': '非酒材與食材的項目皆列為雜項',
  };

  // 只在「零用金」付款時套用（老闆 2026-10-11；月結廠商維持原樣）：
  // 小城外 酒吧-酒水 顯示為「現結酒商」（只改顯示，類別代碼不變，匯入與成本率不受影響）
  static const pettyCashCategoryLabel = <String, String>{}; // 0048 起兩種付款都叫「酒水」，不再改名
  // 廠商名稱的調整（同一家的不同寫法、「選擇廠商」清單的改名／不顯示／一定列出、常用廠商提示、零用金不帶廠商的類別）
  // 改放資料庫每家店一份（ops 0166 vendor_name_rules），見 data/vendor_rules.dart；以前寫在這裡的內容在 VendorRules.legacy
}
