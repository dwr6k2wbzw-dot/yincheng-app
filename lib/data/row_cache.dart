import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 上次讀到的資料（老闆 2026-10-16「打開太慢」）：
/// 打開 App 先顯示手機裡存的上一次資料，背景再向資料庫拿最新的。
/// 只存這台手機登入者自己讀得到的資料（權限照舊由資料庫決定）；登出時清掉。
class RowCache {
  static const _key = 'yc_row_cache_v1';
  static const _maxEntries = 80;
  static Map<String, dynamic> _data = {};
  static Timer? _saveTimer;

  /// App 啟動時讀一次（很快，只讀手機本機）
  static Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) _data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _data = {};
    }
  }

  static dynamic get(String key) => _data[key];

  static void put(String key, dynamic value) {
    _data.remove(key); // 移到最後＝最新
    _data[key] = value;
    while (_data.length > _maxEntries) {
      _data.remove(_data.keys.first);
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  static Future<void> _save() async {
    try {
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(_data));
    } catch (_) {}
  }

  static Future<void> clear() async {
    _saveTimer?.cancel();
    _data = {};
    try {
      (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }
}
