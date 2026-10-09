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

  /// 營收以 Dropbox 日報表為準的店家：App 的營收分頁只能看，不能登記或修改（每小時自動同步）
  static const excelSyncedStores = {'隱城', '小城外'};

  /// 營收照 Excel 分「咖啡／調酒／拉麵／訂金」四項顯示的店家（調酒＝酒水＋餐食；客單＝調酒收入 ÷ 來客數，與小城外 Excel 相同）
  static const multiLineStores = {'小城外'};

  /// 以「廠商銷貨單」分頁取代「盤點」分頁的店家（資料來自 Dropbox 廠商進貨單資料夾）
  static const vendorSlipStores = {'隱城', '小城外'};

  /// 有「班表」分頁的店家
  static const scheduleStores = {'隱城'};

  /// 進貨類別的顯示順序（老闆指定；沒列到的照原本順序排在後面）
  static const categoryOrder = [
    'xc_bar_liquor', 'xc_bar_supply', 'xc_bar_food', 'xc_bar_misc', // 酒吧：酒水、酒水副材料、食材、雜項
    'xc_cafe_food', 'xc_cafe_misc', // 咖啡吧：食材、雜項
    'xc_ramen_broth', 'xc_ramen_food', 'xc_ramen_misc', // 布布拉麵：高湯、食材、雜項
  ];

  /// 新增進貨「類別（常用廠商）」提示的手動調整（老闆指定；其餘照日報表統計）
  static const vendorHintHidden = {'xc_ramen_misc'}; // 布布拉麵-雜項：不顯示提示
  static const vendorHintRename = {'二店拉麵食材': '立成'}; // 布布拉麵-食材
  static const vendorHintAdd = {
    'xc_bar_food': ['小郭'], // 酒吧-食材
  };
}
