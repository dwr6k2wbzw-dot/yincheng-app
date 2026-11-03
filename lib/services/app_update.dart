import 'dart:js_interop';

/// App 新版本檢查（小鈴鐺）：比對網頁內的版本號與伺服器上的 version.txt（JS 在 tool/patch_index.py）
@JS('ycCheckUpdate')
external JSPromise<JSBoolean> _ycCheckUpdate();
@JS('ycReload')
external void _ycReload();

Future<bool> checkAppUpdate() async {
  try {
    return (await _ycCheckUpdate().toDart).toDart;
  } catch (_) {
    return false; // 本機開發或網路不通：當作沒有新版
  }
}

/// 重新載入成最新版（網址加時間參數，避開手機暫存的舊網頁）
void reloadApp() {
  try {
    _ycReload();
  } catch (_) {}
}
