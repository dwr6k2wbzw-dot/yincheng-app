import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

/// 選一個檔案（訂位搬家，ops 0148；JS ycPickFile 在 tool/patch_index.py）。取消回 null；太大、讀不到會丟錯（中文訊息）
@JS('ycPickFile')
external JSPromise<JSAny?> _ycPickFile(JSString accept);

class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

Future<PickedFile?> pickFile(String accept) async {
  final r = await _ycPickFile(accept.toJS).toDart;
  if (r == null) return null;
  final j = jsonDecode((r as JSString).toDart) as Map<String, dynamic>;
  final data = j['data'] as String;
  return PickedFile(j['name'] as String, base64Decode(data.substring(data.indexOf(',') + 1)));
}
