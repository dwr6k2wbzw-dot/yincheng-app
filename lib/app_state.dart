import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/models.dart';
import 'data/repository.dart';
import 'services/load_timing.dart';

/// 全 App 共用狀態：目前登入者的店家清單與目前選擇的店家
class AppState extends ChangeNotifier {
  AppState(this.repo);
  final Repository repo;

  List<Membership> memberships = [];
  Membership? current;
  bool loading = false;
  String? error;

  /// 建立帳號時輸入的邀請碼：先存起來，登入後（可能要先點確認信）自動使用
  static const pendingCodeKey = 'pending_invite_code';
  String? inviteResult; // 自動使用邀請碼的結果（顯示一次）

  Future<void> loadMemberships() async {
    // 先用手機裡存的上次店家清單直接進主畫面，背景再向資料庫確認（老闆 2026-10-16：打開太慢）
    final cached = repo.peekMemberships();
    if (cached != null && cached.isNotEmpty && memberships.isEmpty) {
      memberships = cached;
      String? lastId;
      try {
        lastId = (await SharedPreferences.getInstance()).getString('last_store_id');
      } catch (_) {}
      current = cached.where((m) => m.storeId == lastId).firstOrNull ?? cached.first;
      markLoad('用上次的店家清單');
      notifyListeners();
      try {
        await _claimPendingCode();
        final fresh = await repo.myMemberships();
        memberships = fresh;
        final keep = fresh.where((m) => m.storeId == current?.storeId).firstOrNull;
        // 身分或店家有變才換掉目前店家（避免畫面重來）
        if (keep == null || keep.role != current?.role) current = keep ?? (fresh.isNotEmpty ? fresh.first : null);
        markLoad('讀到帳號與店家');
        notifyListeners();
      } catch (_) {
        // 沒網路：先用上次的
      }
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _claimPendingCode();
      memberships = await repo.myMemberships();
      markLoad('讀到帳號與店家');
      String? lastId;
      try {
        lastId = (await SharedPreferences.getInstance()).getString('last_store_id');
      } catch (_) {}
      current = memberships.where((m) => m.storeId == lastId).firstOrNull ??
          (memberships.isNotEmpty ? memberships.first : null);
    } catch (e) {
      error = friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _claimPendingCode() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    final code = prefs.getString(pendingCodeKey);
    if (code == null || code.isEmpty || !repo.isSignedIn) return;
    try {
      final n = await repo.claimInvite(code);
      inviteResult = n < 0 ? '邀請碼 $code 無效、已用過或已過期，請跟老闆要新的邀請碼。' : '已用邀請碼加入 $n 家店。';
    } catch (e) {
      inviteResult = friendlyError(e);
    }
    await prefs.remove(pendingCodeKey);
  }

  /// 已登入後輸入邀請碼加入店家
  Future<int> claimCode(String code) async {
    final n = await repo.claimInvite(code);
    if (n >= 0) await loadMemberships();
    return n;
  }

  Future<void> switchStore(Membership m) async {
    current = m;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setString('last_store_id', m.storeId);
    } catch (_) {}
  }

  void clear() {
    memberships = [];
    current = null;
    notifyListeners();
  }
}

/// 讓各畫面取得 AppState（不額外引入狀態管理套件）
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

