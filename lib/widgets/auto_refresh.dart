import 'dart:async';

import 'package:flutter/widgets.dart';

/// 自動更新（老闆 2026-10-24：別人在 App 新增訂位，這邊不用手動往下拉）。
/// - 每 [autoRefreshEvery] 安靜重讀一次（畫面不轉圈、不閃；讀取失敗就保留原本的畫面）。
/// - 從別的 App 切回來：超過 20 秒沒更新就馬上重讀。
/// - 上面蓋著別的頁面或對話框（例如正在填訂位資料）時先不讀，免得資料在手上變動。
mixin AutoRefresh<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  Duration get autoRefreshEvery => const Duration(minutes: 1);

  /// 安靜重讀：成功才換掉畫面上的資料；失敗請丟出錯誤（會被忽略，下次再試）。
  Future<void> autoRefresh();

  Timer? _arTimer;
  DateTime _arLast = DateTime.now();
  bool _arBusy = false;

  /// 使用者自己重新整理（往下拉、換日期、存檔）後呼叫：計時從這裡重新算。
  void markRefreshed() => _arLast = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 計時器每 15 秒看一次，距離上次更新滿一分鐘才真的讀
    _arTimer = Timer.periodic(const Duration(seconds: 15), (_) => _arTick(autoRefreshEvery));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _arTick(const Duration(seconds: 20));
  }

  Future<void> _arTick(Duration minAge) async {
    if (!mounted || _arBusy) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (DateTime.now().difference(_arLast) < minAge) return;
    _arBusy = true;
    try {
      await autoRefresh();
    } catch (_) {
      // 網路不穩：保留原本的畫面，下次再試
    } finally {
      _arLast = DateTime.now();
      _arBusy = false;
    }
  }
}
