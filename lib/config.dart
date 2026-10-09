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
}
