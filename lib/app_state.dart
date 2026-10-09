import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/models.dart';
import 'data/repository.dart';

/// 全 App 共用狀態：目前登入者的店家清單與目前選擇的店家
class AppState extends ChangeNotifier {
  AppState(this.repo);
  final Repository repo;

  List<Membership> memberships = [];
  Membership? current;
  bool loading = false;
  String? error;

  Future<void> loadMemberships() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      memberships = await repo.myMemberships();
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

