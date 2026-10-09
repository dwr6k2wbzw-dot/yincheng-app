import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 各身分能看到什麼（顯示在邀請與修改身分的選項下方）
const _roleHints = {
  Role.manager: '營收、進貨、成本率都看得到；看不到租金、人事與損益',
  Role.bartender: '進貨、盤點；看不到營收與成本',
  Role.staff: '進貨、盤點；看不到營收與成本',
};
const _invitableRoles = [Role.manager, Role.bartender, Role.staff];

/// 成員管理（只有老闆）：成員清單、邀請碼、修改身分、停權
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late Future<(List<MemberInfo>, List<MemberInvite>)> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _future = _load();
    }
  }

  Future<(List<MemberInfo>, List<MemberInvite>)> _load() async {
    final repo = AppScope.of(context).repo;
    final id = widget.membership.storeId;
    final r = await Future.wait([repo.storeMembers(id), repo.openInvites(id)]);
    return (r[0] as List<MemberInfo>, r[1] as List<MemberInvite>);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final me = state.repo.currentUserId;
    return Scaffold(
      appBar: AppBar(title: Text('成員管理・${widget.membership.storeName}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _invite,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('邀請成員'),
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (members, invites) = snap.data!;
          final active = members.where((m) => m.active).toList();
          final inactive = members.where((m) => !m.active).toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              _header('成員（${active.length}）'),
              for (final m in active) _memberTile(m, isMe: m.userId == me),
              if (invites.isNotEmpty) ...[
                const SizedBox(height: 16),
                _header('等待加入（邀請碼還沒被使用）'),
                for (final i in invites) _inviteTile(i),
              ],
              if (inactive.isNotEmpty) ...[
                const SizedBox(height: 16),
                _header('已停權（${inactive.length}）'),
                for (final m in inactive) _memberTile(m, isMe: false),
              ],
              const SizedBox(height: 16),
              const Text(
                '邀請方式：按「邀請成員」產生邀請碼，用 LINE 傳給對方。對方打開 App 網址 → 「第一次使用？用邀請碼建立帳號」→ 輸入 Email、密碼和邀請碼就能加入。邀請碼 14 天內有效、只能用一次。',
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      );

  Widget _memberTile(MemberInfo m, {required bool isMe}) {
    final editable = !isMe && m.role != Role.owner;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SectionCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: editable ? () => _editMember(m) : null,
          leading: CircleAvatar(
            backgroundColor: AppColors.cardHigh,
            child: Text(m.displayName.isEmpty ? '?' : m.displayName.characters.first,
                style: TextStyle(color: m.active ? AppColors.primary : AppColors.muted)),
          ),
          title: Text('${m.displayName}${isMe ? '（你）' : ''}',
              style: TextStyle(color: m.active ? null : AppColors.muted)),
          subtitle: Text(m.email, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _roleChip(m.role, muted: !m.active),
            if (editable) const Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }

  Widget _roleChip(Role r, {bool muted = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AppColors.cardHigh, borderRadius: BorderRadius.circular(8)),
        child: Text(roleLabel(r),
            style: TextStyle(fontSize: 12, color: muted ? AppColors.muted : (r == Role.owner ? AppColors.warn : null))),
      );

  Widget _inviteTile(MemberInvite i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SectionCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: AppColors.cardHigh, child: Icon(Icons.key_outlined, size: 20)),
            title: Text(i.displayName),
            subtitle: Text(
              i.expired ? '已過期' : '${DateFormat('M/d').format(i.expiresAt)} 前有效',
              style: TextStyle(color: i.expired ? AppColors.bad : AppColors.muted, fontSize: 12),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _roleChip(i.role),
              IconButton(tooltip: '取消邀請', icon: const Icon(Icons.close), onPressed: () => _revoke(i)),
            ]),
          ),
        ),
      );

  Future<void> _revoke(MemberInvite i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('取消邀請'),
        content: Text('取消給「${i.displayName}」的邀請碼？取消後這組邀請碼就不能用了。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('不要')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('取消邀請')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.of(context).repo.revokeInvite(i.id);
      if (mounted) showMessage(context, '已取消邀請');
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editMember(MemberInfo m) async {
    final repo = AppScope.of(context).repo;
    final storeId = widget.membership.storeId;
    final result = await showModalBottomSheet<(Role?, bool?)>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (c) {
        var role = m.role;
        return StatefulBuilder(
          builder: (c, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(m.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(m.email, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 12),
                if (m.active) ...[
                  for (final r in _invitableRoles)
                    RadioListTile<Role>(
                      value: r,
                      groupValue: role,
                      onChanged: (v) => setSheet(() => role = v!),
                      title: Text(roleLabel(r)),
                      subtitle: Text(_roleHints[r]!, style: const TextStyle(fontSize: 12)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: role == m.role ? null : () => Navigator.pop(c, (role, null)),
                    child: const Text('儲存身分'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.bad),
                    onPressed: () => Navigator.pop(c, (null, false)),
                    child: const Text('停權（不能再登入看這家店）'),
                  ),
                ] else
                  FilledButton(
                    onPressed: () => Navigator.pop(c, (null, true)),
                    child: const Text('恢復權限'),
                  ),
              ]),
            ),
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    final (role, active) = result;
    if (active == false) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('停權'),
          content: Text('停權「${m.displayName}」？他就不能再看這家店的資料。之後可以再恢復。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('停權')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await repo.updateMember(storeId, m.userId, role: role, active: active);
      if (mounted) showMessage(context, active == false ? '已停權' : (active == true ? '已恢復' : '已更新身分'));
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _invite() async {
    final state = AppScope.of(context);
    final ownerStores = state.memberships.where((x) => x.role == Role.owner).toList();
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _InviteScreen(current: widget.membership, ownerStores: ownerStores),
    ));
    if (created == true) _reload();
  }
}

/// 產生邀請碼
class _InviteScreen extends StatefulWidget {
  const _InviteScreen({required this.current, required this.ownerStores});
  final Membership current;
  final List<Membership> ownerStores;
  @override
  State<_InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<_InviteScreen> {
  final _name = TextEditingController();
  Role _role = Role.staff;
  late final Set<String> _stores = {widget.current.storeId};
  bool _busy = false;

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, '請輸入名字', error: true);
      return;
    }
    if (_stores.isEmpty) {
      showMessage(context, '請至少選一家店', error: true);
      return;
    }
    final repo = AppScope.of(context).repo;
    setState(() => _busy = true);
    try {
      final code = await repo.createInvite(_stores.toList(), _role, name);
      if (!mounted) return;
      final storeNames = widget.ownerStores.where((s) => _stores.contains(s.storeId)).map((s) => s.storeName).join('、');
      await _showCode(code, name, storeNames);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCode(String code, String name, String storeNames) {
    final url = '${Uri.base.origin}${Uri.base.path}';
    final text = '$name 你好，邀請你使用$storeNames的營運管理 App（${roleLabel(_role)}）：\n'
        '1. 用手機打開 $url\n'
        '2. 按「第一次使用？用邀請碼建立帳號」\n'
        '3. 輸入你的 Email、設定密碼，邀請碼填 $code\n'
        '邀請碼 14 天內有效，只能用一次。';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('邀請碼已產生'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SelectableText(code,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 2)),
          const SizedBox(height: 12),
          const Text('這組邀請碼只會顯示這一次。按下面的按鈕複製邀請訊息，貼到 LINE 傳給對方。',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('完成')),
          FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('複製邀請訊息'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (c.mounted) showMessage(c, '已複製，貼到 LINE 傳給對方');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('邀請成員')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: '名字（App 裡顯示的名字）', prefixIcon: Icon(Icons.badge_outlined)),
          ),
          const SizedBox(height: 8),
          const Text('身分', style: TextStyle(color: AppColors.muted)),
          for (final r in _invitableRoles)
            RadioListTile<Role>(
              value: r,
              groupValue: _role,
              onChanged: (v) => setState(() => _role = v!),
              title: Text(roleLabel(r)),
              subtitle: Text(_roleHints[r]!, style: const TextStyle(fontSize: 12)),
              contentPadding: EdgeInsets.zero,
            ),
          if (widget.ownerStores.length > 1) ...[
            const SizedBox(height: 8),
            const Text('加入哪幾家店', style: TextStyle(color: AppColors.muted)),
            for (final s in widget.ownerStores)
              CheckboxListTile(
                value: _stores.contains(s.storeId),
                onChanged: (v) => setState(() => v == true ? _stores.add(s.storeId) : _stores.remove(s.storeId)),
                title: Text(s.storeName),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _create,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('產生邀請碼', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 12),
          const Text('不能用邀請碼給「老闆」身分。', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );
}
