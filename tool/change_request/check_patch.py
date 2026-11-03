"""App 內功能許願：檢查 Claude 的修改能不能放行（在 claude-change.yml 的 publish 工作執行）。
- 只能改 lib/、assets/、tool/book/；但不能改連線設定（lib/config.dart、tool/book/common.js）
- 不能夾帶金鑰（service_role、Anthropic 金鑰、GitHub token、JWT…）
- 新增的程式不能出現白名單以外的網址（健檢 2026-11-01：以前一則許願就能把資料送到外部網址，預覽版用真資料且公開）
用法：python3 check_patch.py   （在已套用修改、git add 過的工作目錄執行）
有問題時印出原因並以 1 結束。
"""
import re
import subprocess
import sys

ALLOWED = ("lib/", "assets/", "tool/book/")
# 連線設定（Supabase 網址、金鑰、訂位頁的 API 位址）：只有老闆直接改，功能許願不能動
PROTECTED = ("lib/config.dart", "tool/book/common.js", "tool/book/theme.js")
# 金鑰（Codex 審查 PR #137：上一版改網址檢查時不小心刪掉了，會讓每一則功能許願都在檢查這步出錯）
SECRET = [
    (re.compile(r"service_role", re.I), "service_role"),
    (re.compile(r"sk-ant-[A-Za-z0-9_-]{10,}"), "Anthropic 金鑰"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"), "GitHub token"),
    (re.compile(r"github_pat_[A-Za-z0-9_]{20,}"), "GitHub token"),
    (re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\."), "JWT"),
    (re.compile(r"sb_secret_[A-Za-z0-9_-]{10,}"), "Supabase 秘密金鑰"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "私鑰"),
]

# 新增的程式裡出現網址時，只接受這些網域（App 自己的後端、GitHub Pages、字型、CDN、地圖、LINE）
# Supabase 只允許我們自己的專案：寫成「任何 .supabase.co」的話，別人開一個 Supabase 專案就能收資料（健檢 2026-11-01）
ALLOWED_HOSTS = {
    "yfulcyeoqavqarpfnznw.supabase.co", "dwr6k2wbzw-dot.github.io", "github.com",
    "fonts.googleapis.com", "fonts.gstatic.com", "www.gstatic.com",
    "cdn.jsdelivr.net", "unpkg.com", "cdnjs.cloudflare.com",
    "maps.google.com", "www.google.com", "goo.gl", "maps.app.goo.gl", "line.me", "lin.ee", "liff.line.me",
    "www.w3.org", "schema.org", "ogp.me",
}
# 任何 「//主機」：含 https:// ws:// 等所有 scheme、沒有 scheme 的 //evil.com、JS 跳脫的 \/\/evil.com（先還原再比）
AUTH_RE = re.compile(r"//([^/\s'\"`?#\\<>()\[\]{},;]+)")


def normalize(line: str) -> str:
    """把常見的跳脫寫法還原成 /（\\/、\\x2f、\\u002f、%2f），避免用跳脫繞過網址檢查"""
    t = line.replace("\\/", "/")
    t = re.sub(r"\\x2f|\\u002f|\\u\{2f\}|%2f", "/", t, flags=re.I)
    return t


def hosts_in(line: str) -> list[str]:
    """抓出一行裡所有網址的真正主機名（去掉帳密 user@、連接埠、結尾的點）"""
    out = []
    for m in AUTH_RE.finditer(normalize(line)):
        auth = m.group(1)
        host = auth.rsplit("@", 1)[-1]          # https://github.com@evil.com → evil.com
        host = host.split(":", 1)[0].strip(".").lower()
        # 只看像網域或 IP 的（含點）；Dart 的 //註解、//TODO 不算
        if "." in host:
            out.append(host)
    return out


def host_ok(host: str) -> bool:
    return host.lower().strip(".") in ALLOWED_HOSTS


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def main() -> int:
    files = [f for f in git("diff", "--cached", "--name-only", "--no-renames").splitlines() if f]
    if not files:
        print("Claude 沒有改到任何程式")
        return 1
    bad = [f for f in files if not f.startswith(ALLOWED)]
    if bad:
        print("改到不允許的檔案：" + "、".join(bad[:5]))
        return 1
    locked = [f for f in files if f in PROTECTED]
    if locked:
        print("連線設定只能由老闆直接改，功能許願不能動：" + "、".join(locked))
        return 1
    added = [l[1:] for l in git("diff", "--cached", "-U0", "--no-color").splitlines()
             if l.startswith("+") and not l.startswith("+++")]
    for line in added:
        for pat, name in SECRET:
            if pat.search(line):
                print(f"修改內容疑似含有{name}，已擋下")
                return 1
        for host in hosts_in(line):
            if not host_ok(host):
                print(f"修改內容出現不在白名單的網址（{host}），已擋下；需要新網域請老闆直接改")
                return 1
    print(f"檢查通過：{len(files)} 個檔案")
    return 0


if __name__ == "__main__":
    sys.exit(main())
