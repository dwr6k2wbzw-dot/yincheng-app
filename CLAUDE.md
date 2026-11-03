# 隱城營運 App（Flutter web）
完整交接說明在私人 repo `dwr6k2wbzw-dot/yincheng-ops` 的 `CLAUDE.md`，接手前先讀那份。
- 這個 repo 是公開的：**不可放真實營收或帳務資料**、不可放任何密鑰（publishable key 可以）。
- push 到 main → `.github/workflows/deploy.yml` 建置並發佈到 https://dwr6k2wbzw-dot.github.io/yincheng-app/
- 店家設定在 `lib/config.dart`（Excel 同步店家、小城外四項營收、銷貨單分頁）。
- App 內「功能許願」（2026-10-27）：`.github/workflows/claude-change.yml` 由 Supabase Edge Function 派工，Claude 依 `tool/change_request/prompt.md` 修改，結果放 `cr/<代號>` 分支＋PR＋預覽 `…/preview/<代號>/`；只有老闆在 App 按「上線」才合併。**不要直接在 GitHub 合併 cr/ 開頭的 PR。**

## UI UX Pro Max（只在本專案）
- `.claude/skills/ui-ux-pro-max/` 是 UI UX Pro Max skill（MIT，來源 nextlevelbuilder/ui-ux-pro-max-skill，版本記在 `skills-lock.json`），只裝在這個 repo，不影響官網與活動頁。
- **只用它的易用性規則**：觸控大小、表單與錯誤提示、導覽、無障礙、載入狀態、圖表選擇、Flutter 實作（`--stack flutter`）。
- **不要用它挑風格、配色、字體**：品牌外觀一律沿用 App 現有設計（深色底 #0A0A09、現代黑體搭配字重對比、一句話說明），兩者衝突時以現有設計為準。
