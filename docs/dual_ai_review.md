# 雙 AI 程式審查流程（App repo）

完整說明在私有 repo `yincheng-ops` 的 `docs/dual_ai_review.md`。這裡只放 App（公開 repo）的差異：

- 角色與鐵則同 ops：Claude Code 開發 → Codex 審查程式／架構 → ChatGPT 審查功能 → 老闆核准合併。
- App 的 PR 會觸發 `pr-check.yml`（只編譯測試、不發佈）。
- 合併到 `main` 才會由 `deploy.yml` 發佈到 GitHub Pages。
- 這個 repo 是公開的：PR 內不可放真實營收／帳務資料、不可放任何金鑰（publishable key 可以）。
