"""App 內功能許願：檢查 Claude 的修改能不能放行（在 claude-change.yml 的 publish 工作執行）。
- 只能改 lib/、assets/、tool/book/
- 不能夾帶金鑰（service_role、Anthropic 金鑰、GitHub token、JWT…）
用法：python3 check_patch.py   （在已套用修改、git add 過的工作目錄執行）
有問題時印出原因並以 1 結束。
"""
import re
import subprocess
import sys

ALLOWED = ("lib/", "assets/", "tool/book/")
SECRET = [
    (re.compile(r"service_role", re.I), "service_role"),
    (re.compile(r"sk-ant-[A-Za-z0-9_-]{10,}"), "Anthropic 金鑰"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"), "GitHub token"),
    (re.compile(r"github_pat_[A-Za-z0-9_]{20,}"), "GitHub token"),
    (re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\."), "JWT"),
    (re.compile(r"sb_secret_[A-Za-z0-9_-]{10,}"), "Supabase 秘密金鑰"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "私鑰"),
]


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
    added = [l[1:] for l in git("diff", "--cached", "-U0", "--no-color").splitlines()
             if l.startswith("+") and not l.startswith("+++")]
    for line in added:
        for pat, name in SECRET:
            if pat.search(line):
                print(f"修改內容疑似含有{name}，已擋下")
                return 1
    print(f"檢查通過：{len(files)} 個檔案")
    return 0


if __name__ == "__main__":
    sys.exit(main())
