import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

/// 訂位頁的 logo、封面照（ops 0145）：從相簿選圖、縮小（JS ycPickBrandImage，在 tool/patch_index.py）
@JS('ycPickBrandImage')
external JSPromise<JSAny?> _ycPickBrandImage(JSString kind);

class PickedImage {
  final Uint8List bytes;
  final String contentType; // image/png、image/jpeg、image/webp
  const PickedImage(this.bytes, this.contentType);
}

/// kind：logo（保留透明背景）／hero（封面照）。取消時回傳 null；讀不到、太大、太小會丟錯（訊息是中文）
Future<PickedImage?> pickBrandImage(String kind) async {
  final r = await _ycPickBrandImage(kind.toJS).toDart;
  if (r == null) return null;
  return decodeDataUrl((r as JSString).toDart);
}

/// data:image/png;base64,xxxx → 圖片內容和格式
PickedImage decodeDataUrl(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  final head = dataUrl.substring(0, comma);
  final type =
      RegExp(r'^data:(image/(?:png|jpeg|webp))').firstMatch(head)?.group(1) ??
          'image/jpeg';
  return PickedImage(base64Decode(dataUrl.substring(comma + 1)), type);
}
