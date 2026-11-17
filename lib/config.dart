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

  /// 新增進貨「類別（常用廠商）」提示的手動調整（2026-10-13 起不再顯示提示，保留設定以便恢復）（老闆指定；其餘照日報表統計）
  static const vendorHintHidden = {'xc_ramen_misc'}; // 布布拉麵-雜項：不顯示提示
  // 只在「零用金」付款時套用（老闆 2026-10-11；月結廠商維持原樣）：
  // 小城外 酒吧-酒水 顯示為「現結酒商」（只改顯示，類別代碼不變，匯入與成本率不受影響）
  static const pettyCashCategoryLabel = <String, String>{}; // 0048 起兩種付款都叫「酒水」，不再改名
  // 零用金時不顯示廠商提示：酒吧-酒水（月結廠商不適用）、布布拉麵-食材（信功、立成）
  static const pettyCashHintHidden = {'xc_bar_liquor', 'xc_ramen_food'};
  static const vendorHintRemove = {
    'xc_cafe_food': {'柳橙汁'}, // 咖啡吧-餐食（老闆 2026-10-13 移除）
  };
  static const vendorHintRename = {'二店拉麵食材': '立成'}; // 布布拉麵-食材
  /// 進貨「月結廠商」區塊：同一家廠商的不同寫法併成一塊（老闆 2026-10-29）。
  /// 名稱最後的括號會先去掉，所以這裡寫去掉括號後的名字。
  static const vendorGroupAlias = <String, String>{'德哥': '阿德水果'};
  /// 新增進貨「選擇廠商」清單的手動調整（老闆 2026-10-29），依店名：改名 → 移除 → 補上
  static const vendorListRename = <String, Map<String, String>>{
    // 欣利實業統一叫「欣利實業（茗茶酒）」（老闆 2026-11-05；日報表寫欣利／欣利實業）
    '小城外': {'小郭食材': '小郭', 'yoyo': 'YOYO', '欣利': '欣利實業（茗茶酒）', '欣力': '欣利實業（茗茶酒）', '欣利實業': '欣利實業（茗茶酒）'},
    '隱城': {'欣利': '欣利實業（茗茶酒）', '欣力': '欣利實業（茗茶酒）', '欣利實業': '欣利實業（茗茶酒）'},
  };
  static const vendorListRemove = <String, Set<String>>{
    '小城外': {'布布拉麵', '二店拉麵食材', '小郭抽成', '廣泰', '瑪格莉特比薩', '瑪格麗特披薩', '生蠔'},
    '隱城': {'薯條', '布布拉麵', '小郭食材'},
  };
  static const vendorListAdd = <String, List<String>>{
    '隱城': ['喝酒生活'],
    '小城外': ['花都'],
  };
  static const vendorHintAdd = {
    'xc_bar_food': ['小郭'], // 酒吧-食材
  };
}
