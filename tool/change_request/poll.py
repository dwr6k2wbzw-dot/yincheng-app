"""App 內功能許願：每 5 分鐘處理排隊的工作（cr-poll.yml 執行，不需要額外的 GitHub 金鑰）
1. 排隊中的需求 → 派工 claude-change.yml
2. 老闆核准上線的 → 合併 PR（squash）、刪分支、觸發 deploy.yml 正式發佈
3. 取消的 → 關閉 PR、刪分支
需要環境變數：CR_URL、CR_AUDIENCE、ACTIONS_ID_TOKEN_REQUEST_URL／TOKEN（GitHub OIDC）、GH_TOKEN、REPO
"""
import json
import os
import subprocess
import urllib.error
import urllib.request

REPO = os.environ["REPO"]


def oidc() -> str:
    url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=" + os.environ["CR_AUDIENCE"]
    req = urllib.request.Request(url, headers={"Authorization": "bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["value"]


def cr(op: str, **body):
    data = json.dumps({"op": op, **body}).encode()
    req = urllib.request.Request(os.environ["CR_URL"], data=data, method="POST", headers={
        "Authorization": "Bearer " + oidc(), "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def gh(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["gh", *args], capture_output=True, text=True)


CONFLICT = "這段時間 App 有其他更新，修改接不上，請按「再改一次」讓後臺重新套用"


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], capture_output=True, text=True)


def merge(n, branch) -> str | None:
    """合併成功回傳 None，失敗回傳給老闆看的原因"""
    if n:
        info = gh("api", f"repos/{REPO}/pulls/{n}")
        if info.returncode == 0:
            pr = json.loads(info.stdout)
            if pr.get("merged"):
                return None
            if pr.get("state") == "open":
                m = gh("api", "-X", "PUT", f"repos/{REPO}/pulls/{n}/merge",
                       "-f", "merge_method=squash", "-f", f"sha={pr['head']['sha']}")
                return None if m.returncode == 0 else CONFLICT
    if not branch:
        return "找不到這次的修改，請按「再改一次」重新產生"
    # 沒有 PR：把分支壓成一個提交接到 main 上
    for _ in range(2):
        f = git("fetch", "-q", "--depth", "50", "origin", "+refs/heads/main:refs/remotes/origin/main",
                f"+refs/heads/{branch}:refs/remotes/origin/{branch}")
        if f.returncode != 0:
            return "找不到這次的修改，請按「再改一次」重新產生"
        git("checkout", "-q", "-B", "merge-work", "origin/main")
        git("reset", "-q", "--hard", "origin/main")
        if git("merge", "--squash", f"origin/{branch}").returncode != 0:
            git("merge", "--abort")
            git("reset", "-q", "--hard")
            return CONFLICT
        if git("diff", "--cached", "--quiet").returncode == 0:
            return None  # 已經合併過
        short = branch.split("/")[-1]
        git("-c", "user.email=claude-change@noreply", "-c", "user.name=Claude（App 功能許願）",
            "commit", "-qm", f"App 功能許願 {short}（老闆在 App 核准上線）")
        if git("push", "-q", "origin", "HEAD:main").returncode == 0:
            return None
        git("reset", "-q", "--hard")  # main 剛好有新提交，重來一次
    return CONFLICT


def main() -> None:
    for c in cr("poll_claim") or []:
        r = gh("workflow", "run", "claude-change.yml", "-R", REPO, "--ref", "main",
               "-f", f"request_id={c['id']}", "-f", f"nonce={c['nonce']}")
        if r.returncode != 0:
            print(f"::warning::派工失敗 {c['id']}: {r.stderr.strip()[:200]}")
            cr("poll_dispatch_failed", id=c["id"], nonce=c["nonce"], error="GitHub 派工失敗，請按「再試一次」")
        else:
            print(f"::notice::已派工 {c['id']}")

    deploy = False
    for p in cr("poll_pending") or []:
        n, branch = p.get("pr_number"), p.get("branch")
        if p["status"] == "approved":
            err = merge(n, branch)
            if err:
                print(f"::warning::合併失敗 {branch}: {err}")
                cr("poll_merged", id=p["id"], ok=False, error=err)
                continue
            if branch:
                gh("api", "-X", "DELETE", f"repos/{REPO}/git/refs/heads/{branch}")
            cr("poll_merged", id=p["id"], ok=True)
            deploy = True
            print(f"::notice::已上線 {branch}")
        elif p["status"] == "cancelled":
            if n:
                gh("pr", "close", str(n), "-R", REPO)
            if branch:
                gh("api", "-X", "DELETE", f"repos/{REPO}/git/refs/heads/{branch}")
            cr("poll_closed", id=p["id"])
            print(f"::notice::已關閉 {branch}")

    # 用 Actions 自己的權限合併不會自動觸發 deploy.yml，要手動觸發一次
    if deploy:
        r = gh("workflow", "run", "deploy.yml", "-R", REPO, "--ref", "main")
        print("::notice::已觸發正式發佈" if r.returncode == 0 else f"::error::觸發發佈失敗：{r.stderr.strip()[:200]}")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        # Edge Function 還沒部署、暫時錯誤：下一輪再試，不要讓排程一直失敗寄信
        print(f"::warning::change-request 回應 {e.code}，下一輪再試")
    except urllib.error.URLError as e:
        print(f"::warning::連不到 change-request（{e.reason}），下一輪再試")
