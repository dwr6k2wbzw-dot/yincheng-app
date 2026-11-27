import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/onboarding.dart';
import '../data/repository.dart';
import '../services/open_external.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'booking_page_screen.dart';
import 'members_screen.dart';
import 'onboarding_action_bar.dart';
import 'reservations_screen.dart';

/// 開店精靈（公版，ops 0155）：新店建好之後，一步一步把線上訂位設好。
/// ① 基本資料 ② 訂位網址與時段 ③ 訂位頁的樣子 ④ 邀請同事 ⑤ 完成。每一步都可以略過、之後從總覽再回來。
/// 只有老闆會看到（訂位設定、訂位頁本來就只有老闆能改）；隱城、小城外那一份 App 沒有這個畫面。
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

const _stepTitles = ['店的基本資料', '訂位網址與時段', '訂位頁的樣子', '邀請同事', '完成'];

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  OnboardingStatus? _status;
  bool _loading = true, _busy = false;
  String? _loadErr;

  // ① 基本資料
  late final _name = TextEditingController(text: widget.membership.storeName);
  final _address = TextEditingController();
  final _phone = TextEditingController();
  // ② 訂位網址與時段
  late final _slug = TextEditingController(
    text: suggestSlug(widget.membership.storeName),
  );
  final _groups = TextEditingController();
  final _guests = TextEditingController();
  List<String> _slots = [...defaultOnboardingSlots];
  final Set<int> _closed = {};
  final Map<String, String?> _err = {};

  @override
  void initState() {
    super.initState();
    // AppScope 要等第一個畫面掛上去才讀得到
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(jumpToFirstOpen: true));
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _slug, _groups, _guests]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh({bool jumpToFirstOpen = false}) async {
    try {
      final s = await AppScope.of(context).repo
          .onboardingStatus(widget.membership.storeId);
      if (!mounted) return;
      setState(() {
        _status = s;
        _loading = false;
        _loadErr = null;
        // 已經設好訂位的店，直接從還沒做的那一步開始
        if (jumpToFirstOpen && s.booking) {
          _step = !s.page ? 2 : (!s.members ? 3 : 4);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadErr = friendlyError(e);
        });
      }
    }
  }

  void _go(int step) => setState(() {
    _step = step.clamp(0, _stepTitles.length - 1);
    _err.clear();
  });

  // ① → ②：店名一定要有，電話有填就要像電話
  void _nextFromBasics() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    setState(() {
      _err['name'] = name.isEmpty ? '請填訂位頁要顯示的店名' : null;
      _err['phone'] =
          phone.isNotEmpty && !RegExp(r'^[0-9+() -]{6,30}$').hasMatch(phone)
          ? '電話只能有數字、空白和 + ( ) -'
          : null;
    });
    if (_err['name'] == null && _err['phone'] == null) _go(1);
  }

  Future<void> _createBooking() async {
    final slugErr = slugError(_slug.text);
    final (groups, gErr) = parseDayLimit(_groups.text, 500, '每天最多幾組');
    final (guests, pErr) = parseDayLimit(_guests.text, 2000, '每天最多幾位');
    setState(() {
      _err['slug'] = slugErr;
      _err['slots'] = _slots.isEmpty ? '至少要有一個訂位時段' : null;
      _err['weekdays'] = _closed.length == 7 ? '不能每天都公休' : null;
      _err['groups'] = gErr;
      _err['guests'] = pErr;
      _err['other'] = null;
    });
    if ([
      slugErr,
      _err['slots'],
      _err['weekdays'],
      gErr,
      pErr,
    ].any((e) => e != null)) {
      return;
    }
    if (_name.text.trim().isEmpty) {
      _go(0);
      setState(() => _err['name'] = '請先填訂位頁要顯示的店名');
      return;
    }
    setState(() => _busy = true);
    try {
      await AppScope.of(context).repo.setupOnlineBooking(
        widget.membership.storeId,
        slug: _slug.text.trim().toLowerCase(),
        displayName: _name.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        slotTimes: _slots,
        closedWeekdays: (_closed.toList()..sort()),
        maxGroups: groups,
        maxGuests: guests,
      );
      await _refresh();
      if (!mounted) return;
      showMessage(context, '線上訂位建好了');
      _go(2);
    } catch (e) {
      final field = onboardingErrorField(e.toString());
      final msg = friendlyError(e);
      if (!mounted) return;
      if (field == 'name' || field == 'phone' || field == 'address') {
        _go(0);
      }
      setState(() => _err[field == 'limits' ? 'groups' : field] = msg);
      if (e.toString().contains('ONBOARD_EXISTS')) await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSlot() async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
      helpText: '加一個訂位時段',
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() {
      _slots = normalizeSlots([..._slots, '${t.hour}:${t.minute}']);
      _err['slots'] = _slots.length > 48 ? '訂位時段最多 48 個' : null;
    });
  }

  Future<void> _openBookingPage() async {
    final state = AppScope.of(context);
    final settings = await state.repo.reservationSettings(
      widget.membership.storeId,
    );
    if (!mounted || settings == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingPageScreen(
          membership: widget.membership,
          settings: settings,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openBookingSettings() async {
    final state = AppScope.of(context);
    final settings = await state.repo.reservationSettings(
      widget.membership.storeId,
    );
    if (!mounted || settings == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReservationSettingsScreen(
          membership: widget.membership,
          settings: settings,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openMembers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MembersScreen(membership: widget.membership),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('開店設定')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadErr != null
          ? ErrorView(
              message: _loadErr!,
              onRetry: () {
                setState(() => _loading = true);
                _refresh();
              },
            )
          : SafeArea(
              child: Column(
                children: [
                  _StepHeader(step: _step, status: _status!),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: AnimatedSwitcher(
                            duration: AppMotion.fast,
                            child: KeyedSubtree(
                              key: ValueKey(_step),
                              child: _body(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _actions(),
                ],
              ),
            ),
    );
  }

  Widget _body() => switch (_step) {
    0 => _basics(),
    1 => _bookingStep(),
    2 => _pageStep(),
    3 => _membersStep(),
    _ => _doneStep(),
  };

  // ---------------------------------------------------------------- ①
  Widget _basics() {
    final s = _status!;
    if (s.booking) return _alreadyBooked('店名、地址、電話已經跟著線上訂位存好了，要改請到「訂位設定」。');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lead('客人在訂位頁和確認信上會看到這些。地址、電話之後也可以再補。'),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          maxLength: 40,
          textInputAction: TextInputAction.next,
          onChanged: (_) =>
              _err['name'] == null ? null : setState(() => _err['name'] = null),
          decoration: InputDecoration(
            labelText: '訂位頁顯示的店名',
            counterText: '',
            prefixIcon: const Icon(Icons.storefront_outlined),
            errorText: _err['name'],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          maxLength: 200,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: '地址（選填）',
            hintText: '例如：台北市大安區信義路三段 1 號',
            counterText: '',
            prefixIcon: const Icon(Icons.place_outlined),
            errorText: _err['address'],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          maxLength: 30,
          textInputAction: TextInputAction.done,
          onChanged: (_) => _err['phone'] == null
              ? null
              : setState(() => _err['phone'] = null),
          onSubmitted: (_) => _nextFromBasics(),
          decoration: InputDecoration(
            labelText: '訂位電話（選填）',
            hintText: '02-2700-0000',
            counterText: '',
            prefixIcon: const Icon(Icons.call_outlined),
            errorText: _err['phone'],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- ②
  Widget _bookingStep() {
    final s = _status!;
    if (s.booking) return _alreadyBooked('客人用這個網址訂位。時段、公休、名額之後都可以在「訂位設定」改。');
    final slug = _slug.text.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lead('取一個訂位網址代號，選好晚上開放訂位的時段。'),
        const SizedBox(height: 20),
        TextField(
          controller: _slug,
          maxLength: 30,
          autocorrect: false,
          keyboardType: TextInputType.url,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
          ],
          onChanged: (_) => setState(() => _err['slug'] = null),
          decoration: InputDecoration(
            labelText: '訂位網址代號',
            hintText: '例如：lane-bar',
            counterText: '',
            prefixIcon: const Icon(Icons.link),
            helperText: '小寫英文、數字、減號，2～30 個字；建好之後不能改',
            helperMaxLines: 2,
            errorText: _err['slug'],
            errorMaxLines: 2,
          ),
        ),
        if (slug.isNotEmpty && slugError(slug) == null) ...[
          const SizedBox(height: 8),
          Text(
            onboardingBookingUrl(slug),
            style: TextStyle(color: AppColors.muted, fontSize: AppType.caption),
          ),
        ],
        const SizedBox(height: 24),
        _label('開放訂位的時段', '點一下拿掉；客人只能選這些時間'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _slots)
              InputChip(
                label: Text(
                  t,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                onDeleted: () =>
                    setState(() => _slots = [..._slots]..remove(t)),
                deleteButtonTooltipMessage: '拿掉 $t',
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('加時段'),
              onPressed: _addSlot,
            ),
          ],
        ),
        if (_err['slots'] != null) _fieldError(_err['slots']!),
        const SizedBox(height: 24),
        _label('每週固定公休', '這幾天不開放線上訂位'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 1; i <= 7; i++)
              SelectChip(
                label: Text(
                  '週${const ['一', '二', '三', '四', '五', '六', '日'][i - 1]}',
                ),
                selected: _closed.contains(i),
                onSelected: (v) => setState(() {
                  v ? _closed.add(i) : _closed.remove(i);
                  _err['weekdays'] = null;
                }),
              ),
          ],
        ),
        if (_err['weekdays'] != null) _fieldError(_err['weekdays']!),
        const SizedBox(height: 24),
        _label('每天名額', '空白＝不限；電話訂位不受限制'),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _groups,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: '最多幾組',
                  errorText: _err['groups'],
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _guests,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: '最多幾位',
                  errorText: _err['guests'],
                  errorMaxLines: 3,
                ),
              ),
            ),
          ],
        ),
        if (_err['other'] != null) ...[
          const SizedBox(height: 16),
          _fieldError(_err['other']!),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- ③
  Widget _pageStep() {
    final s = _status!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lead('放上 logo、封面照和一句話介紹，客人打開訂位頁就知道是哪一家。'),
        const SizedBox(height: 20),
        _StatusRow(
          done: s.page,
          text: s.page ? '訂位頁已經有圖片或介紹了' : '還沒放 logo、封面照或介紹',
        ),
        const SizedBox(height: 20),
        if (!s.booking)
          Text(
            '要先完成「訂位網址與時段」，才能設定訂位頁。',
            style: TextStyle(color: AppColors.warn, fontSize: AppType.small),
          )
        else
          OutlinedButton.icon(
            onPressed: _openBookingPage,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.palette_outlined),
            label: Text(s.page ? '再改一下訂位頁' : '設定訂位頁的樣子'),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- ④
  Widget _membersStep() {
    final s = _status!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lead('產生邀請碼給同事，他們用自己的帳號加入，就能一起看訂位、班表、交接。'),
        const SizedBox(height: 20),
        _StatusRow(
          done: s.members,
          text: s.members ? '已經有同事或等待加入的邀請' : '目前只有你一個人',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _openMembers,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.group_add_outlined),
          label: const Text('邀請同事'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- ⑤
  Widget _doneStep() {
    final s = _status!;
    final url = s.slug == null ? null : onboardingBookingUrl(s.slug!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lead(
          s.complete
              ? '都設好了。把訂位網址放上 IG、Google 商家、LINE，客人就能直接訂位。'
              : '還有幾項沒做，之後可以從總覽的「開店設定」回來。',
        ),
        const SizedBox(height: 20),
        _StatusRow(done: s.booking, text: '線上訂位'),
        _StatusRow(done: s.page, text: '訂位頁的樣子'),
        _StatusRow(done: s.members, text: '邀請同事'),
        _StatusRow(done: s.staffing, text: '排班人力（在班表頁設定，選做）', optional: true),
        if (url != null) ...[
          const SizedBox(height: 24),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '客人訂位頁',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: AppType.small,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  url,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: AppType.body,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          showMessage(context, '已複製訂位頁網址');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('複製網址'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => openExternal(url),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('打開看看'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- 共用
  Widget _alreadyBooked(String note) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _StatusRow(done: true, text: '線上訂位已經設好：${_status!.slug ?? ''}'),
      const SizedBox(height: 8),
      Text(
        note,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: AppType.small,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: _openBookingSettings,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        icon: const Icon(Icons.tune),
        label: const Text('到訂位設定修改'),
      ),
    ],
  );

  Widget _lead(String text) => Text(
    text,
    style: TextStyle(
      color: AppColors.muted,
      fontSize: AppType.body,
      height: 1.6,
    ),
  );

  Widget _label(String title, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: AppType.title,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        sub,
        style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
      ),
    ],
  );

  Widget _fieldError(String msg) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: AppColors.bad, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(color: AppColors.bad, fontSize: AppType.small),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _actions() {
    final s = _status!;
    final last = _step == _stepTitles.length - 1;
    final (String label, VoidCallback onTap) = switch (_step) {
      0 => (
        '下一步',
        s.booking ? () => _go(1) : _nextFromBasics,
      ),
      1 => (
        s.booking ? '下一步' : '建立線上訂位',
        s.booking ? () => _go(2) : _createBooking,
      ),
      _ when last => ('完成', () => Navigator.of(context).pop()),
      _ => ('下一步', () => _go(_step + 1)),
    };
    return OnboardingActionBar(
      label: label,
      onPrimary: onTap,
      busy: _busy,
      showBack: _step > 0,
      onBack: () => _go(_step - 1),
      showSkip: !last && !(_step <= 1 && s.booking),
      onSkip: () => _go(_step + 1),
    );
  }
}

/// 最上面：第幾步、步驟名稱、五格進度
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.status});
  final int step;
  final OnboardingStatus status;
  @override
  Widget build(BuildContext context) {
    final done = [
      status.booking,
      status.booking,
      status.page,
      status.members,
      status.complete,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第 ${step + 1} 步，共 ${_stepTitles.length} 步',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: AppType.small,
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                header: true,
                child: Text(
                  _stepTitles[step],
                  style: const TextStyle(
                    fontSize: AppType.heading,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < _stepTitles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: AppMotion.fast,
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: i == step
                              ? AppColors.primary
                              : done[i]
                              ? AppColors.primary.withValues(alpha: 0.45)
                              : AppColors.line,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.done,
    required this.text,
    this.optional = false,
  });
  final bool done, optional;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 22,
          color: done
              ? AppColors.good
              : (optional ? AppColors.line : AppColors.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: AppType.body,
              color: done || !optional ? AppColors.text : AppColors.muted,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 總覽最上面的「開店設定」卡片（公版、老闆）：還沒做完才出現；新店第一次進總覽自動打開精靈一次
class OnboardingCard extends StatefulWidget {
  const OnboardingCard({super.key, required this.membership});
  final Membership membership;
  @override
  State<OnboardingCard> createState() => _OnboardingCardState();
}

class _OnboardingCardState extends State<OnboardingCard> {
  static final Set<String> _hiddenThisSession = {};
  OnboardingStatus? _s;
  bool _hidden = false;

  String get _store => widget.membership.storeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(autoOpen: true));
  }

  Future<void> _load({bool autoOpen = false}) async {
    try {
      final repo = AppScope.of(context).repo;
      final s = await repo.onboardingStatus(_store);
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _s = s;
        _hidden =
            _hiddenThisSession.contains(_store) ||
            (prefs.getBool('onboard_hidden_$_store') ?? false);
      });
      // 新店第一次進總覽（還沒設線上訂位、也還沒打開過精靈）→ 自動打開一次
      if (autoOpen &&
          !s.booking &&
          !(prefs.getBool('onboard_opened_$_store') ?? false)) {
        await prefs.setBool('onboard_opened_$_store', true);
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _open());
        }
      }
    } catch (e) {
      // 資料庫還沒更新到 0155（或沒權限）：不顯示卡片
      debugPrint('開店設定卡片讀不到進度：$e');
    }
  }

  Future<void> _open() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(membership: widget.membership),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _hide() async {
    _hiddenThisSession.add(_store);
    setState(() => _hidden = true);
    try {
      (await SharedPreferences.getInstance()).setBool(
        'onboard_hidden_$_store',
        true,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null || s.complete || _hidden) return const SizedBox.shrink();
    final next = !s.booking
        ? '下一步：設定線上訂位'
        : (!s.page ? '下一步：訂位頁的樣子' : '下一步：邀請同事');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '開店設定還沒完成',
                    style: TextStyle(
                      fontSize: AppType.title,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${s.done}／${OnboardingStatus.total}',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: AppType.small,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: LinearProgressIndicator(
                value: s.done / OnboardingStatus.total,
                minHeight: 4,
                color: AppColors.primary,
                backgroundColor: AppColors.line,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              next,
              style: TextStyle(color: AppColors.muted, fontSize: AppType.small),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(onPressed: _open, child: const Text('繼續設定')),
                const SizedBox(width: 8),
                TextButton(onPressed: _hide, child: const Text('先不要提醒')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
