import 'dart:js_interop';

/// 載入速度記錄（老闆 2026-10-14「登入很慢」）：記下各階段完成時間（從打開網頁起算），
/// 在「⋯ → 載入速度」顯示，方便截圖判斷慢在哪一段。只記第一次。
@JS('ycMark')
external void _ycMark(JSString name);

@JS('ycLoadReport')
external JSString _ycLoadReport();

void markLoad(String name) {
  try {
    _ycMark(name.toJS);
  } catch (_) {}
}

String loadReport() {
  try {
    return _ycLoadReport().toDart;
  } catch (_) {
    return '讀不到載入紀錄';
  }
}
