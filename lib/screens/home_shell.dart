import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart';
import 'purchases_screen.dart';
import 'stock_counts_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.loading && state.current == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.error != null) {
      return Scaffold(body: ErrorView(message: state.error!, onRetry: state.loadMemberships));
    }
    final m = state.current;
    if (m == null) {
      return Scaffold(
        body: ErrorView(
          message: '這個帳號還沒有加入任何店家。\n請老闆在系統中把你加入店家成員。',
          onRetry: state.loadMemberships,
        ),
        floatingActionButton: TextButton(onPressed: state.repo.signOut, child: const Text('登出')),
      );
    }
    // 以店家 id 當 key：切換店家時各分頁重新載入
    final pages = [
      DashboardScreen(key: ValueKey('d-${m.storeId}'), membership: m),
      PurchasesScreen(key: ValueKey('p-${m.storeId}'), membership: m),
      StockCountsScreen(key: ValueKey('s-${m.storeId}'), membership: m),
    ];
    return Scaffold(
      appBar: AppBar(
        title: _StoreSwitcher(state: state),
        actions: [
          IconButton(
            tooltip: '登出',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('登出'),
                  content: Text('確定要登出 ${state.repo.currentUserEmail ?? ''}？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('登出')),
                  ],
                ),
              );
              if (ok == true) await state.repo.signOut();
            },
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '總覽'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: '進貨'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: '盤點'),
        ],
      ),
    );
  }
}

/// 標題列的店家切換（PRD 畫面左上角「隱城 ▾」）
class _StoreSwitcher extends StatelessWidget {
  const _StoreSwitcher({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final m = state.current!;
    final title = Row(mainAxisSize: MainAxisSize.min, children: [
      Text(m.storeName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      if (state.memberships.length > 1) const Icon(Icons.arrow_drop_down),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AppColors.cardHigh, borderRadius: BorderRadius.circular(8)),
        child: Text(roleLabel(m.role), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ),
    ]);
    if (state.memberships.length <= 1) return title;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.card,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('切換店家', style: TextStyle(fontSize: 16))),
            for (final x in state.memberships)
              ListTile(
                leading: Icon(x.storeId == m.storeId ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: AppColors.primary),
                title: Text(x.storeName),
                subtitle: Text(roleLabel(x.role)),
                onTap: () {
                  state.switchStore(x);
                  Navigator.pop(c);
                },
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: title),
    );
  }
}
