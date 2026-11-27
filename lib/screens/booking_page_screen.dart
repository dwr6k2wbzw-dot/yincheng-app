import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../data/booking_profile.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/brand_image.dart';
import '../services/open_external.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _bookBase = 'https://dwr6k2wbzw-dot.github.io/yincheng-app/book/';

/// 訂位頁的樣子（公版階段 2 第 3 步；資料在 ops 0135 booking_profiles，圖在 0145 booking-assets）：
/// logo、封面照、大標、介紹、外語地址、低消、資訊卡、姊妹店。只有老闆能改。
class BookingPageScreen extends StatefulWidget {
  const BookingPageScreen(
      {super.key,
      required this.membership,
      required this.settings,
      this.sisterChoices = const []});
  final Membership membership;
  final ReservationSettings settings;

  /// 可以設成姊妹店的店（同一個人當老闆的其他店）
  final List<Membership> sisterChoices;
  @override
  State<BookingPageScreen> createState() => _BookingPageScreenState();
}

class _LangFields {
  final title = TextEditingController();
  final shortName = TextEditingController();
  final intro = TextEditingController();
  final address = TextEditingController();
  final directions = TextEditingController();
  final minText = TextEditingController();
  void dispose() {
    for (final c in [title, shortName, intro, address, directions, minText]) {
      c.dispose();
    }
  }
}

class _RowFields {
  final label = {
    for (final l in BookingProfile.langsAll) l: TextEditingController()
  };
  final text = {
    for (final l in BookingProfile.langsAll) l: TextEditingController()
  };
  void dispose() {
    for (final c in [...label.values, ...text.values]) {
      c.dispose();
    }
  }
}

class _BookingPageScreenState extends State<BookingPageScreen> {
  bool _loading = true;
  bool _started = false;
  String? _loadError;
  BookingProfile _orig = const BookingProfile();
  final Set<String> _langs = {'zh'};
  String _tab = 'zh';
  final _fields = {for (final l in BookingProfile.langsAll) l: _LangFields()};
  final _minSpend = TextEditingController();
  final List<_RowFields> _rows = [];
  String? _logo, _hero; // 資料庫裡的路徑（存檔後才換）
  PickedImage? _newLogo, _newHero; // 剛選、還沒存的圖
  bool _removeLogo = false, _removeHero = false;
  double _posX = 0.5, _posY = 0.5;
  String? _sister;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    for (final r in _rows) {
      r.dispose();
    }
    _minSpend.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await AppScope.of(context)
              .repo
              .bookingProfile(widget.membership.storeId) ??
          const BookingProfile();
      if (!mounted) return;
      setState(() {
        _orig = p;
        _langs
          ..clear()
          ..addAll({'zh', ...p.langs});
        for (final l in BookingProfile.langsAll) {
          final f = _fields[l]!;
          f.title.text = p.title[l] ?? '';
          f.shortName.text = p.shortName[l] ?? '';
          f.intro.text = p.intro[l] ?? '';
          f.address.text = p.address[l] ?? '';
          f.directions.text = p.directions[l] ?? '';
          f.minText.text = p.minSpendText[l] ?? '';
        }
        _minSpend.text = p.minSpend?.toString() ?? '';
        for (final row in p.infoRows) {
          final r = _RowFields();
          for (final l in BookingProfile.langsAll) {
            r.label[l]!.text = row.label[l] ?? '';
            r.text[l]!.text = row.text[l] ?? '';
          }
          _rows.add(r);
        }
        _logo = p.logoUrl;
        _hero = p.heroUrl;
        final (x, y) = parseHeroPos(p.heroPos);
        _posX = x;
        _posY = y;
        _sister = p.sisterStoreId;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = friendlyError(e));
    }
  }

  String? _url(String? path) => bookingAssetUrl(path,
      supabaseUrl: AppConfig.supabaseUrl, bookBase: _bookBase);

  /// 預覽用的圖：剛選的（還沒存）優先，其次資料庫裡的
  ImageProvider? _image(PickedImage? picked, String? path, bool removed) {
    if (picked != null) return MemoryImage(picked.bytes);
    if (removed) return null;
    final u = _url(path);
    return u == null ? null : NetworkImage(u);
  }

  Future<void> _pick(String kind) async {
    setState(() => _error = null);
    try {
      final img = await pickBrandImage(kind);
      if (img == null || !mounted) return;
      setState(() {
        if (kind == 'logo') {
          _newLogo = img;
          _removeLogo = false;
        } else {
          _newHero = img;
          _removeHero = false;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Map<String, String> _collect(
          TextEditingController Function(_LangFields f) pick) =>
      {
        for (final l in _langs) l: pick(_fields[l]!).text,
      };

  String? _check() {
    if (_fields['zh']!.title.text.trim().isEmpty &&
        widget.settings.displayName.trim().isEmpty) {
      return '請填中文大標';
    }
    final m = _minSpend.text.trim();
    if (m.isNotEmpty) {
      final v = int.tryParse(m);
      if (v == null || v < 1 || v > 100000) return '低消金額要是 1～100000 的整數，或留白';
    }
    for (final (i, r) in _rows.indexed) {
      if (r.label['zh']!.text.trim().isEmpty &&
          _langs.any((l) => r.text[l]!.text.trim().isNotEmpty)) {
        return '資訊卡第 ${i + 1} 列要有中文標題';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final bad = _check();
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = AppScope.of(context).repo;
    final store = widget.membership.storeId;
    final uploaded = <String>[];
    try {
      // 先把新的圖傳上去（資料庫會檢查圖真的存在），再存資料
      var logo = _removeLogo ? null : _logo;
      var hero = _removeHero ? null : _hero;
      if (_newLogo != null) {
        logo = await repo.uploadBookingAsset(
            store, 'logo', _newLogo!.bytes, _newLogo!.contentType);
        uploaded.add(logo);
      }
      if (_newHero != null) {
        hero = await repo.uploadBookingAsset(
            store, 'hero', _newHero!.bytes, _newHero!.contentType);
        uploaded.add(hero);
      }
      final p = BookingProfile(
        langs: [
          for (final l in BookingProfile.langsAll)
            if (_langs.contains(l)) l
        ],
        title: _collect((f) => f.title),
        shortName: _collect((f) => f.shortName),
        intro: _collect((f) => f.intro),
        address: _collect((f) => f.address),
        directions: _collect((f) => f.directions),
        minSpend: int.tryParse(_minSpend.text.trim()),
        minSpendText: _collect((f) => f.minText),
        infoRows: [
          for (final r in _rows)
            BookingInfoRow(
              label: {for (final l in _langs) l: r.label[l]!.text},
              text: {for (final l in _langs) l: r.text[l]!.text},
            ),
        ],
        logoUrl: logo,
        heroUrl: hero,
        heroPos: hero == null ? null : heroPosText(_posX, _posY),
        sisterStoreId: _sister,
      );
      await repo.saveBookingProfile(store, p);
      // 換掉的舊圖（自己上傳的）順手刪掉；內建的圖不動
      for (final old in [_orig.logoUrl, _orig.heroUrl]) {
        if (isUploadedBookingAsset(old) && old != logo && old != hero) {
          await repo.deleteBookingAsset(old!);
        }
      }
      if (!mounted) return;
      setState(() {
        _orig = p;
        _logo = logo;
        _hero = hero;
        _newLogo = _newHero = null;
        _removeLogo = _removeHero = false;
        _saving = false;
      });
      showMessage(context, '已儲存訂位頁，客人重新整理就看得到');
    } catch (e) {
      for (final u in uploaded) {
        await repo.deleteBookingAsset(u); // 存檔失敗：剛傳的圖不要留著占名額
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('訂位頁的樣子')),
        body: Center(
            child: Text(_loadError!, style: TextStyle(color: AppColors.bad))),
      );
    }
    if (_loading) {
      return Scaffold(
          appBar: AppBar(title: const Text('訂位頁的樣子')),
          body: const Center(child: CircularProgressIndicator()));
    }
    final langs = [
      for (final l in BookingProfile.langsAll)
        if (_langs.contains(l)) l
    ];
    if (!_langs.contains(_tab)) {
      _tab = 'zh';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('訂位頁的樣子')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _preview(),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openExternal(
                    '$_bookBase?s=${Uri.encodeQueryComponent(widget.settings.slug)}'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('打開客人看到的訂位頁（存檔後才會更新）'),
              ),
            ),
            const SizedBox(height: 8),
            _imagesCard(),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('語言',
                        style: TextStyle(
                            fontSize: AppType.title,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('訂位頁右上角可以切換的語言；中文一定會有，沒開的語言不會出現。',
                        style: TextStyle(
                            color: AppColors.muted, fontSize: AppType.small)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final l in BookingProfile.langsAll)
                        SelectChip(
                          label: Text(BookingProfile.langNames[l]!),
                          selected: _langs.contains(l),
                          // 中文一定開著（資料庫也要求），點了不會關掉
                          onSelected: (v) => setState(() =>
                              l == 'zh' ? null : (v ? _langs.add(l) : _langs.remove(l))),
                        ),
                    ]),
                  ]),
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('文字',
                              style: TextStyle(
                                  fontSize: AppType.title,
                                  fontWeight: FontWeight.w600))),
                      if (langs.length > 1)
                        SegmentedButton<String>(
                          segments: [
                            for (final l in langs)
                              ButtonSegment(
                                  value: l,
                                  label: Text(BookingProfile.langNames[l]!))
                          ],
                          selected: {_tab},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) =>
                              setState(() => _tab = s.first),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    ..._textFields(_tab),
                  ]),
            ),
            const SizedBox(height: 12),
            _rowsCard(),
            if (widget.sisterChoices.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sisterCard(),
            ],
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: TextStyle(
                        color: AppColors.bad, fontSize: AppType.body)),
              ),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: Text(_saving ? '儲存中…' : '儲存'),
            ),
          ]),
    );
  }

  /// 訂位頁最上面那一塊的樣子（封面照＋logo＋大標），照目前填的內容即時顯示。
  /// 介紹不在這裡：訂位頁本身不顯示，只出現在另一家店的姊妹店卡片上（Codex P2）
  Widget _preview() {
    final hero = _image(_newHero, _hero, _removeHero);
    final logo = _image(_newLogo, _logo, _removeLogo);
    final f = _fields[_tab]!;
    final title = f.title.text.trim().isNotEmpty
        ? f.title.text.trim()
        : (_fields['zh']!.title.text.trim().isNotEmpty
            ? _fields['zh']!.title.text.trim()
            : widget.settings.displayName);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(fit: StackFit.expand, children: [
          if (hero != null)
            Image(
              image: hero,
              fit: BoxFit.cover,
              alignment: Alignment(_posX * 2 - 1, _posY * 2 - 1),
              errorBuilder: (_, __, ___) =>
                  ColoredBox(color: AppColors.cardHigh),
            )
          else
            ColoredBox(color: AppColors.cardHigh),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xCC000000)],
                stops: [0.35, 1],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (logo != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Image(
                        image: logo,
                        height: 56,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppType.heading,
                          fontWeight: FontWeight.w700,
                          height: 1.25)),
                ]),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(999)),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text('預覽',
                    style: TextStyle(
                        color: Colors.white, fontSize: AppType.caption)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _imagesCard() {
    final hasHero = _image(_newHero, _hero, _removeHero) != null;
    Widget row(String kind, String title, String note, ImageProvider? img,
            VoidCallback? onRemove) =>
        Row(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: AppColors.cardHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line)),
            clipBehavior: Clip.antiAlias,
            child: img == null
                ? Icon(Icons.image_outlined, color: AppColors.muted)
                : Image(
                    image: img,
                    fit: kind == 'logo' ? BoxFit.contain : BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: AppType.body, fontWeight: FontWeight.w600)),
              Text(note,
                  style: TextStyle(
                      color: AppColors.muted, fontSize: AppType.caption)),
            ]),
          ),
          TextButton(
              onPressed: _saving ? null : () => _pick(kind),
              child: Text(img == null ? '選圖' : '換圖')),
          if (onRemove != null)
            IconButton(
                onPressed: _saving ? null : onRemove,
                tooltip: '拿掉',
                icon: const Icon(Icons.close)),
        ]);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('圖片',
            style: TextStyle(
                fontSize: AppType.title, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        row(
            'logo',
            'Logo',
            '去背的 PNG 最好看；沒有就只顯示店名',
            _image(_newLogo, _logo, _removeLogo),
            _image(_newLogo, _logo, _removeLogo) == null
                ? null
                : () => setState(() {
                      _newLogo = null;
                      _removeLogo = true;
                    })),
        const SizedBox(height: 12),
        row(
            'hero',
            '封面照',
            '橫的照片，至少 1600 像素寬',
            _image(_newHero, _hero, _removeHero),
            !hasHero
                ? null
                : () => setState(() {
                      _newHero = null;
                      _removeHero = true;
                    })),
        if (hasHero) ...[
          const SizedBox(height: 12),
          Text('封面照取景（拖拉看上面的預覽）',
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          Row(children: [
            const SizedBox(
                width: 44,
                child: Text('左右', style: TextStyle(fontSize: AppType.small))),
            Expanded(
                child: Slider(
                    value: _posX, onChanged: (v) => setState(() => _posX = v))),
          ]),
          Row(children: [
            const SizedBox(
                width: 44,
                child: Text('上下', style: TextStyle(fontSize: AppType.small))),
            Expanded(
                child: Slider(
                    value: _posY, onChanged: (v) => setState(() => _posY = v))),
          ]),
        ],
      ]),
    );
  }

  List<Widget> _textFields(String l) {
    final f = _fields[l]!;
    final zh = l == 'zh';
    void touch(_) => setState(() {});
    return [
      TextField(
        controller: f.title,
        maxLength: 40,
        onChanged: touch,
        decoration: InputDecoration(
            labelText: '大標',
            hintText: zh ? widget.settings.displayName : null,
            helperText: zh ? '空白＝用訂位設定的店名' : null),
      ),
      TextField(
          controller: f.shortName,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '簡稱（姊妹店卡片上用；空白＝大標）')),
      TextField(
          controller: f.intro,
          maxLength: 80,
          decoration: const InputDecoration(
              labelText: '一句話介紹（姊妹店卡片上用）',
              helperText: '顯示在另一家店訂位頁的「姊妹店」卡片上，這家店自己的訂位頁不顯示')),
      if (!zh) ...[
        TextField(
            controller: f.address,
            maxLength: 120,
            decoration: const InputDecoration(labelText: '地址（這個語言）')),
        TextField(
            controller: f.directions,
            maxLength: 120,
            decoration: const InputDecoration(labelText: '交通說明（這個語言）')),
      ] else
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('中文地址、電話在「訂位設定」裡改。',
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        ),
      if (zh)
        TextField(
          controller: _minSpend,
          keyboardType: TextInputType.number,
          onChanged: touch,
          decoration: const InputDecoration(labelText: '低消金額（每人；空白＝不顯示低消）'),
        ),
      const SizedBox(height: 8),
      TextField(
        controller: f.minText,
        maxLength: 200,
        minLines: 2,
        maxLines: 4,
        onChanged: touch,
        decoration: const InputDecoration(
          labelText: '低消說明',
          helperText: '寫 {amount} 的地方會換成上面的金額',
          helperMaxLines: 2,
        ),
      ),
      if (f.minText.text.trim().isNotEmpty) _minSample(l, f.minText.text.trim()),
    ];
  }

  /// 客人在訂位頁上看到的低消說明（{amount} 換成金額，同訂位頁 i18n.js 的 minAmount）
  Widget _minSample(String l, String text) {
    final n = int.tryParse(_minSpend.text.trim());
    final amount = n == null
        ? '（沒填金額）'
        : switch (l) { 'en' => 'NT\$$n per person.', 'ja' => 'お一人様 $n 元', _ => '每人 $n 元' };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: AppColors.cardHigh, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('客人看到', style: TextStyle(color: AppColors.muted, fontSize: AppType.caption)),
        const SizedBox(height: 2),
        Text(text.replaceAll('{amount}', amount), style: const TextStyle(fontSize: AppType.small, height: 1.5)),
      ]),
    );
  }

  Widget _rowsCard() => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('資訊卡',
                    style: TextStyle(
                        fontSize: AppType.title, fontWeight: FontWeight.w600))),
            if (_rows.length < 8)
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(_RowFields())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增一列'),
              ),
          ]),
          Text(
              '地址、電話、低消下面多加的列，例如營業時間、注意事項（最多 8 列；現在編輯的是「${BookingProfile.langNames[_tab]}」）。',
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          for (final (i, r) in _rows.indexed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
              decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: r.label[_tab],
                      maxLength: 12,
                      decoration: InputDecoration(
                          labelText: _tab == 'zh' ? '標題（中文必填）' : '標題'),
                    ),
                  ),
                  IconButton(
                    tooltip: '刪除這一列',
                    onPressed: () =>
                        setState(() => _rows.removeAt(i).dispose()),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextField(
                      controller: r.text[_tab],
                      maxLength: 300,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: '內容')),
                ),
              ]),
            ),
          ],
        ]),
      );

  Widget _sisterCard() => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('姊妹店',
              style: TextStyle(
                  fontSize: AppType.title, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('訂位頁下面會出現「也可以訂另一家」的卡片；那一天滿了也會推薦客人改訂這家。',
              style:
                  TextStyle(color: AppColors.muted, fontSize: AppType.small)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: widget.sisterChoices.any((m) => m.storeId == _sister)
                ? _sister
                : null,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('不顯示')),
              for (final m in widget.sisterChoices)
                DropdownMenuItem<String?>(
                    value: m.storeId, child: Text(m.storeName)),
            ],
            onChanged: (v) => setState(() => _sister = v),
          ),
        ]),
      );
}

/// 讓測試用：把剛選的圖換成指定內容（不經過瀏覽器的選檔視窗）
@visibleForTesting
PickedImage testPickedImage(Uint8List bytes, [String type = 'image/png']) =>
    PickedImage(bytes, type);
