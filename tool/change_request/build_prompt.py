"""App 內功能許願（claude-change.yml）：把需求與之前的對話組成給 Claude 的指示。
用法：python3 build_prompt.py request.json prompt.txt [--fresh]
--fresh：之前的修改接不上最新版 App，這次要從最新版重新做一次。
"""
import json
import pathlib
import sys

KIND = {"request": "需求", "followup": "再改一次", "claude": "Claude 的回覆", "system": "系統"}


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    fresh = "--fresh" in sys.argv[3:]
    req = json.loads(pathlib.Path(src).read_text(encoding="utf-8"))
    lines = []
    for m in req.get("messages", []):
        who = m.get("author") or ""
        head = f"### {KIND.get(m.get('kind'), m.get('kind'))}" + (f"（{who}，{m.get('at', '')}）" if who else "")
        lines.append(head)
        lines.append(str(m.get("body", "")).strip())
        lines.append("")
    history = "\n".join(lines).strip()
    if req.get("run_count", 1) > 1 and not fresh:
        history += ("\n\n（之前已經照上面的對話改過一版，程式碼裡就是那一版。"
                    "請依照最後一則「再改一次」或「老闆退回」的內容繼續修改。）")
    if fresh:
        history += ("\n\n（注意：之前改的那一版和最新版 App 接不上，程式碼已經換回最新版。"
                    "請依照上面全部的對話，從頭重新做一次。）")
    tpl = (pathlib.Path(__file__).parent / "prompt.md").read_text(encoding="utf-8")
    out = tpl.replace("{{STORE}}", str(req.get("store") or "")).replace("{{HISTORY}}", history)
    pathlib.Path(dst).write_text(out, encoding="utf-8")


if __name__ == "__main__":
    main()
