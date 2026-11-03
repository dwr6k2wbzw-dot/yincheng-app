# 隱城營運 App（Flutter web）
完整交接說明在私人 repo `dwr6k2wbzw-dot/yincheng-ops` 的 `CLAUDE.md`，接手前先讀那份。
- 這個 repo 是公開的：**不可放真實營收或帳務資料**、不可放任何密鑰（publishable key 可以）。
- push 到 main → `.github/workflows/deploy.yml` 建置並發佈到 https://dwr6k2wbzw-dot.github.io/yincheng-app/
- 店家設定在 `lib/config.dart`（Excel 同步店家、小城外四項營收、銷貨單分頁）。
- App 內「功能許願」（2026-10-27）：`.github/workflows/claude-change.yml` 由 Supabase Edge Function 派工，Claude 依 `tool/change_request/prompt.md` 修改，結果放 `cr/<代號>` 分支＋PR＋預覽 `…/preview/<代號>/`；只有老闆在 App 按「上線」才合併。**不要直接在 GitHub 合併 cr/ 開頭的 PR。**
