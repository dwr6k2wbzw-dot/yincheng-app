# 隱城營運 App（Flutter web）
完整交接說明在私人 repo `dwr6k2wbzw-dot/yincheng-ops` 的 `CLAUDE.md`，接手前先讀那份。
- 這個 repo 是公開的：**不可放真實營收或帳務資料**、不可放任何密鑰（publishable key 可以）。
- push 到 main → `.github/workflows/deploy.yml` 建置並發佈到 https://dwr6k2wbzw-dot.github.io/yincheng-app/
- 每家店的功能開關（班表分頁、以日報表為準、營收四項、銷貨單、班別代碼、logo）在資料庫 `store_features`（0116），App 用 `StoreFeatures.of(店名)` 讀（`lib/data/store_features.dart`）；**不要再用店名判斷功能**。班表可用的記號、班別時數也只看資料庫（功能開關 `shiftCodes`＋`shift_mark_options`，見 `lib/data/shift_marks.dart`），App 不內建任何一家店的班別表。
- 自助註冊（ops 0119，2026-11-17）：只有公版那一份 App 才有，建置時加 `--dart-define=SELF_SIGNUP=true`（`AppConfig.selfSignup`）。登入頁可以不用邀請碼建立帳號（「我要開店／我有邀請碼」），登入後沒有任何店 → `lib/screens/create_store_screen.dart` 幫店取名字 → `signup_create_store`。**隱城／小城外這一份不加這個參數**（資料庫的開關也是關的）。公版的產品名稱、標誌還沒決定，登入頁先放中性的圖示。畫面預覽：`--dart-define=DEMO=true --dart-define=SELF_SIGNUP=true`，網址 `?auto=1&as=new@demo`（示範帳號含 new＝還沒有任何店）。
- App 內「功能許願」（2026-10-27）：`.github/workflows/claude-change.yml` 由 Supabase Edge Function 派工，Claude 依 `tool/change_request/prompt.md` 修改，結果放 `cr/<代號>` 分支＋PR＋預覽 `…/preview/<代號>/`；只有老闆在 App 按「上線」才合併。**不要直接在 GitHub 合併 cr/ 開頭的 PR。**

## UI UX Pro Max（只在本專案）
- `.claude/skills/ui-ux-pro-max/` 是 UI UX Pro Max skill（MIT，來源 nextlevelbuilder/ui-ux-pro-max-skill，版本記在 `skills-lock.json`），只裝在這個 repo，不影響官網與活動頁。
- **只用它的易用性規則**：觸控大小、表單與錯誤提示、導覽、無障礙、載入狀態、圖表選擇、Flutter 實作（`--stack flutter`）。
- **不要用它挑風格、配色、字體**：品牌外觀一律沿用 App 現有設計（深色底 #0A0A09、現代黑體搭配字重對比、一句話說明），兩者衝突時以現有設計為準。

## Claudex Loop（Claude 寫計畫、Codex 挑毛病，只在本專案）
- `.claude/skills/` 下的 `claudex-loop`、`codex-review`、`codex-build`、`claudex-route`，來源 chaseai-yt/claudex-loop（MIT，commit 53cddc4，2026-11-04 加入）。
- **只用在大功能**：POS 結帳、訂金／金流、權限、資料庫結構、訂位核心流程這類一出錯就影響營收或客人的改動；先跑 claudex-loop 把計畫審到 Codex 同意，再動手。改文字、顏色、小 UI 不要用。
- 需要能執行 Codex CLI 且已 `codex login` 的環境（老闆的 Mac）；沒有 Codex 時不要硬跑，照一般流程做並說明。
- **「功能許願」自動派工（`claude-change.yml`）不要使用這四個 skill。**

## 寫程式守則（Karpathy 四原則）
- 來源：multica-ai/andrej-karpathy-skills（MIT），2026-11-04 加入；整理自 Andrej Karpathy 對 AI 寫程式常見毛病的觀察（不是他本人寫的）。
- 和本檔其他規則衝突時，以本專案規則為準。
- 無人在場時（例如「功能許願」自動派工）：不要停下來等人回答，把假設和取捨寫進 PR 說明。

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
