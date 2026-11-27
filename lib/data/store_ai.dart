/// 店家接自己的 AI（ops 0157，公版）：選哪一家（Claude／OpenAI／Gemini）、模型、貼金鑰。
/// 金鑰存進資料庫的加密保管庫，App 永遠拿不到原文，只看得到末 4 碼和上次驗證時間。
/// 接了之後，訂位 AI 助理、送貨單辨識（之後班表照片、排班助理）都改用店家的 AI，不受平台每天次數限制。
library;

enum StoreAiProvider { anthropic, openai, gemini }

class StoreAiProviderInfo {
  const StoreAiProviderInfo({
    required this.provider,
    required this.label,
    required this.models,
    required this.keyHint,
    required this.whereToGet,
  });
  final StoreAiProvider provider;
  final String label;

  /// 建議的模型（第一個是預設；也可以自己打）。要能看圖：送貨單、班表照片辨識會傳照片
  final List<String> models;
  final String keyHint;
  final String whereToGet;
}

const storeAiProviders = <StoreAiProviderInfo>[
  StoreAiProviderInfo(
    provider: StoreAiProvider.anthropic,
    label: 'Claude',
    models: ['claude-sonnet-5-5', 'claude-haiku-5-5', 'claude-opus-5-5'],
    keyHint: 'sk-ant-…',
    whereToGet: '到 console.anthropic.com 的 API Keys 建立一把',
  ),
  StoreAiProviderInfo(
    provider: StoreAiProvider.openai,
    label: 'OpenAI',
    models: ['gpt-5-mini', 'gpt-5', 'gpt-4.1-mini'],
    keyHint: 'sk-…',
    whereToGet: '到 platform.openai.com 的 API keys 建立一把',
  ),
  StoreAiProviderInfo(
    provider: StoreAiProvider.gemini,
    label: 'Gemini',
    models: ['gemini-2.5-flash', 'gemini-2.5-pro'],
    keyHint: 'AIza…',
    whereToGet: '到 aistudio.google.com 的 Get API key 建立一把',
  ),
];

StoreAiProviderInfo storeAiInfo(StoreAiProvider p) =>
    storeAiProviders.firstWhere((i) => i.provider == p);

StoreAiProvider? storeAiProviderFrom(String? s) => switch (s) {
  'anthropic' => StoreAiProvider.anthropic,
  'openai' => StoreAiProvider.openai,
  'gemini' => StoreAiProvider.gemini,
  _ => null,
};

/// 這家店目前的設定（沒有＝用平台內建的 AI）
class StoreAiSetting {
  const StoreAiSetting({
    required this.provider,
    required this.model,
    required this.keyLast4,
    this.verifiedAt,
    this.lastError,
  });
  final StoreAiProvider provider;
  final String model;
  final String keyLast4;
  final DateTime? verifiedAt;
  final String? lastError;

  static StoreAiSetting? fromRow(Map<String, dynamic> r) {
    final p = storeAiProviderFrom(r['provider'] as String?);
    if (p == null) return null;
    return StoreAiSetting(
      provider: p,
      model: '${r['model'] ?? ''}',
      keyLast4: '${r['key_last4'] ?? ''}',
      verifiedAt: r['verified_at'] == null
          ? null
          : DateTime.parse(r['verified_at'] as String),
      lastError: r['last_error'] as String?,
    );
  }
}

/// 存金鑰、測試連線的結果（失敗的原因是給老闆看的中文）
class StoreAiResult {
  const StoreAiResult.ok({this.last4}) : ok = true, error = null;
  const StoreAiResult.fail(this.error) : ok = false, last4 = null;
  final bool ok;
  final String? error;
  final String? last4;
}

/// 模型名稱：英文、數字、. _ : / -（跟資料庫同一套；開頭的 models/ 拿掉）
String? storeAiModelProblem(String model) {
  final m = model.trim().replaceFirst(RegExp(r'^models/'), '');
  if (m.isEmpty) return '請選或填一個模型';
  if (m.length > 80 || !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]*$').hasMatch(m)) {
    return '模型名稱只能有英文、數字和 . _ : / -';
  }
  return null;
}

/// 金鑰：整串、不能有空白（跟資料庫同一套）
String? storeAiKeyProblem(String key) {
  final k = key.trim();
  if (k.isEmpty) return '請貼上金鑰';
  if (k.length < 20 || k.length > 400 || !RegExp(r'^[!-~]+$').hasMatch(k)) {
    return '金鑰格式不對，請整串貼上（不要有空白或換行）';
  }
  return null;
}
