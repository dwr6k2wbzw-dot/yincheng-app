import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../data/repository.dart';
import 'dashboard_screen.dart';
import 'members_screen.dart';
import 'purchases_screen.dart';
import 'revenue_screen.dart';
import 'stock_counts_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 建立帳號時輸入的邀請碼自動使用後，顯示一次結果
    final state = AppScope.of(context);
    final msg = state.inviteResult;
    if (msg != null && !state.loading) {
      state.inviteResult = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showMessage(context, msg, error: msg.contains('無效') || msg.contains('錯誤'));
      });
    }
  }

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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.storefront_outlined, color: AppColors.muted, size: 48),
              const SizedBox(height: 12),
              const Text('這個帳號還沒有加入任何店家。\n請跟老闆要邀請碼，輸入後就能加入。', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => enterInviteCode(context),
                icon: const Icon(Icons.key_outlined),
                label: const Text('輸入邀請碼'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: state.loadMemberships, child: const Text('重新整理')),
            ]),
          ),
        ),
        floatingActionButton: TextButton(onPressed: state.repo.signOut, child: const Text('登出')),
      );
    }
    // 以店家 id 當 key：切換店家時各分頁重新載入
    // 營收分頁只給老闆／店長（資料庫也只允許這兩種角色讀寫營收）
    final tabs = <(Widget, NavigationDestination)>[
      (
        DashboardScreen(key: ValueKey('d-${m.storeId}'), membership: m),
        const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '總覽'),
      ),
      if (m.canSeeRevenue)
        (
          RevenueScreen(key: ValueKey('r-${m.storeId}'), membership: m),
          const NavigationDestination(
              icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: '營收'),
        ),
      (
        PurchasesScreen(key: ValueKey('p-${m.storeId}'), membership: m),
        const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: '進貨'),
      ),
      (
        StockCountsScreen(key: ValueKey('s-${m.storeId}'), membership: m),
        const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: '盤點'),
      ),
    ];
    final tab = _tab.clamp(0, tabs.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: _StoreSwitcher(state: state),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) async {
              if (v == 'members') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => MembersScreen(membership: m)));
                return;
              }
              if (v == 'code') {
                enterInviteCode(context);
                return;
              }
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
            itemBuilder: (_) => [
              if (m.role == Role.owner)
                const PopupMenuItem(value: 'members', child: ListTile(leading: Icon(Icons.group_outlined), title: Text('成員管理'))),
              const PopupMenuItem(value: 'code', child: ListTile(leading: Icon(Icons.key_outlined), title: Text('輸入邀請碼'))),
              const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('登出'))),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: tab, children: [for (final t in tabs) t.$1]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [for (final t in tabs) t.$2],
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

/// 已登入後輸入邀請碼（加入新店家）
Future<void> enterInviteCode(BuildContext context) async {
  final state = AppScope.of(context);
  final c = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('輸入邀請碼'),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(hintText: 'XXXXX-XXXXX'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('加入')),
      ],
    ),
  );
  if (code == null || code.isEmpty) return;
  try {
    final n = await state.claimCode(code);
    if (!context.mounted) return;
    showMessage(context, n < 0 ? '邀請碼無效、已用過或已過期，請跟老闆要新的邀請碼。' : '已加入 $n 家店', error: n < 0);
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
}
