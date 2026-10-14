import 'dart:js_interop';

@JS('window.open')
external JSAny? _windowOpen(JSString url, JSString target);

/// 另開網頁（iPhone 主畫面 App 會開在 Safari 視窗裡，關掉就回到 App）
void openExternal(String url) {
  _windowOpen(url.toJS, '_blank'.toJS);
}
