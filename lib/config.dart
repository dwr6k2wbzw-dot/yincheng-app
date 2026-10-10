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
  static const scheduleStores = {'隱城', '小城外'};

  /// 班表可選的記號（依店家）
  static const shiftMarks = {
    '隱城': ['V', '休', '指休', 'O'],
    '小城外': ['B', 'BH', 'RBK', '休', '指休'], // 老闆 2026-10-10：班別只留 B、BH、RBK（其他代碼的時數仍保留，舊資料照算）
  };

  /// 班別代碼的時段（老闆 2026-10-10 提供的小城外班別表）
  static const shiftCodeTimes = {
    '小城外': {
      'R': '16:00-20:30',
      'R1': '14:00-21:00',
      'RBK': '16:00-23:00',
      'B': '17:00-00:30',
      'BP': '19:00-00:30',
      'BP+': '18:00-00:30',
      'BHP': '19:00-01:30',
      'BHP-': '20:00-01:30',
      'BH': '17:00-01:30',
      'BH-': '18:00-01:30',
    },
  };

  /// 以「時數」統計的店家：班別代碼的時數（老闆班別表）；兼職填時段照實際時間
  static const shiftHours = {
    '小城外': {
      'R': 4.5, 'R1': 7.0, 'RBK': 7.0, 'B': 7.5, 'BP': 5.5,
      'BP+': 6.5, 'BHP': 6.5, 'BHP-': 5.5, 'BH': 8.5, 'BH-': 7.5,
    },
  };
  static const shiftQuickRanges = ['17:00-01:30', '18:00-00:30', '18:00-01:30', '19:00-00:30', '19:00-01:30', '20:00-01:30'];

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
