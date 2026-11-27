/// 店家接自己的 LINE 官方帳號（ops 0160，公版；只有老闆）。
/// channel secret、access token 存進加密保管庫，App 只拿得到末 4 碼和要貼到 LINE 的 Webhook 網址。
library;

/// 目前的狀態（store_line_status）
class StoreLineStatus {
  const StoreLineStatus({
    required this.connected,
    this.botName,
    this.basicId,
    this.secretLast4,
    this.tokenLast4,
    this.verifiedAt,
    this.lastError,
    this.webhookPath,
    this.groupBound = false,
    this.groupVia,
  });

  /// 還沒接上
  static const none = StoreLineStatus(connected: false);

  final bool connected;
  final String? botName;
  final String? basicId;
  final String? secretLast4;
  final String? tokenLast4;
  final DateTime? verifiedAt;
  final String? lastError;
  final String? webhookPath;
  final bool groupBound;

  /// 群組透過哪個帳號綁的：'store'＝這個官方帳號、'platform'＝平台的、null＝還沒綁
  final String? groupVia;

  bool get groupViaStore => groupBound && groupVia == 'store';

  /// 要貼到 LINE Developers 的 Webhook 網址（接在這個環境的 Supabase 網址後面）
  String? webhookUrl(String supabaseUrl) {
    final p = webhookPath;
    if (p == null || p.isEmpty) return null;
    return supabaseUrl.replaceFirst(RegExp(r'/+$'), '') + p;
  }

  factory StoreLineStatus.fromJson(Map<String, dynamic> j) => StoreLineStatus(
        connected: j['connected'] == true,
        botName: j['bot_name'] as String?,
        basicId: j['basic_id'] as String?,
        secretLast4: j['secret_last4'] as String?,
        tokenLast4: j['token_last4'] as String?,
        verifiedAt: j['verified_at'] == null
            ? null
            : DateTime.parse(j['verified_at'] as String),
        lastError: j['last_error'] as String?,
        webhookPath: j['webhook_path'] as String?,
        groupBound: j['group_bound'] == true,
        groupVia: j['group_via'] as String?,
      );
}

/// 接上／測試的結果（失敗的原因是給老闆看的中文）
class StoreLineResult {
  const StoreLineResult.ok({
    this.verified = true,
    this.webhookSet = true,
    this.webhookUrl,
    this.warning,
  })  : ok = true,
        error = null;
  const StoreLineResult.fail(this.error)
      : ok = false,
        verified = false,
        webhookSet = false,
        webhookUrl = null,
        warning = null;
  final bool ok;
  final String? error;

  /// 存好了，而且 LINE 的 Webhook 測試通過（channel secret 也對）
  final bool verified;

  /// Webhook 網址已經自動填進 LINE Developers
  final bool webhookSet;
  final String? webhookUrl;

  /// 存好了但還要老闆處理的事（例如 Use webhook 沒打開、secret 不對）
  final String? warning;
}

/// Channel secret：32 個英數字（跟資料庫同一套）
String? storeLineSecretProblem(String secret) {
  final s = secret.trim();
  if (s.isEmpty) return '請貼上 Channel secret';
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(s)) {
    return 'Channel secret 格式不對（應該是 32 個英數字），請到 LINE Developers 的 Basic settings 複製';
  }
  return null;
}

/// Channel access token：整串、不能有空白（跟資料庫同一套）
String? storeLineTokenProblem(String token) {
  final t = token.trim();
  if (t.isEmpty) return '請貼上 Channel access token';
  if (t.length < 40 || t.length > 600 || !RegExp(r'^[!-~]+$').hasMatch(t)) {
    return 'Channel access token 格式不對，請整串貼上（不要有空白或換行）';
  }
  return null;
}

/// 一步一步的說明（畫面上照順序列）
const storeLineSteps = <(String, String)>[
  (
    '申請 LINE 官方帳號',
    '到 LINE Official Account Manager 用店的名字開一個官方帳號（免費方案就可以，訊息則數算你自己的）。',
  ),
  (
    '打開 Messaging API',
    '官方帳號的「設定」→「Messaging API」→ 啟用，會建立一個 LINE Developers 的 channel。',
  ),
  (
    '複製 Channel secret',
    '到 LINE Developers → 你的 channel →「Basic settings」，複製 Channel secret（32 個英數字）。',
  ),
  (
    '發一組 Channel access token',
    '同一個 channel 的「Messaging API」分頁最下面，按「Issue」發 long-lived 的 Channel access token。',
  ),
  (
    '貼到下面驗證',
    '把兩組貼到下面按「驗證並接上」。成功後會試著幫你把 Webhook 網址填好；沒填好就照畫面把網址貼到「Webhook URL」。',
  ),
  (
    '打開 Use webhook、允許加入群組',
    'Messaging API 分頁打開「Use webhook」；官方帳號的回應設定關掉「自動回應訊息」，帳號設定打開「允許被加入群組」。',
  ),
  ('拉進群組、綁定', '把官方帳號拉進店裡的工作群組，按下面「產生群組綁定代碼」，在群組打「綁定 店名 代碼」。'),
];
