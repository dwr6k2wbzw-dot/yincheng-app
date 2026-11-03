# 雙 AI 程式審查流程（App repo）

完整說明在私有 repo `yincheng-ops` 的 `docs/dual_ai_review.md`。這裡只放 App（公開 repo）的差異：

- 角色與鐵則同 ops。**Codex／ChatGPT 審查逐案決定（老闆 2026-10-11 調整）：預設不跑，老闆交辦每項時決定要不要。** 無論有沒有審查，Claude 一律開分支、加測試、本機跑綠才開 PR，合併與部署只由老闆核准。
- App 的 PR 會觸發 `pr-check.yml`（只編譯測試、不發佈）。
- 合併到 `main` 才會由 `deploy.yml` 發佈到 GitHub Pages。
- 這個 repo 是公開的：PR 內不可放真實營收／帳務資料、不可放任何金鑰（publishable key 可以）。
