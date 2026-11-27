# 隱城營運 App（Flutter web）
完整交接說明在私人 repo `dwr6k2wbzw-dot/yincheng-ops` 的 `CLAUDE.md`，接手前先讀那份。
- 這個 repo 是公開的：**不可放真實營收或帳務資料**、不可放任何密鑰（publishable key 可以）。
- push 到 main → `.github/workflows/deploy.yml` 建置並發佈到 https://dwr6k2wbzw-dot.github.io/yincheng-app/
- 客人訂位頁的正式網址是 https://booking.barcitynorth.com/xcw/ 、/yincheng/（2026-11-24）：deploy.yml 的 `booking` 工作把 `book/` 推到 repo `dwr6k2wbzw-dot/yincheng-booking`（GitHub Pages 掛這個網域，DNS 在 Cloudflare、只做 DNS），不要直接改那個 repo。舊網址 …/yincheng-app/book/ 照樣保留（Google 商家、IG、確認信還連著）。員工 App 網址不變。
- 客人訂位頁的 Google Analytics 4（2026-11-24，官網執行計畫 B5）：repo 變數 `BOOKING_GA4_ID`（G- 開頭）有填，部署時 `tool/book/ga.py` 才把 GA4 放進訂位頁；沒填就什麼都不載入、不送。訂位成功送 `booking_complete`，**只帶人數**，不送姓名、電話、Email、日期時間等任何訂位內容；取消頁（網址帶取消碼）不放；送出的網址只留 `s`、`lang`、`ref`、`gclid`、`utm_*`，來源網址同網站清理、外站只留網域；清理過的網址要用 `gtag('set')` 在 `js` 之前給，給在 `config` 會被正式的評估 ID 略過（2026-11-24 正式站實測，假 ID 測不出來，所以檢查用正式 ID、請求全攔下）。跨網域和官網 barcitynorth.com 同一個資料串流。檢查：`tool/book_check/ga_check.cjs`。
- 每家店的功能開關（班表分頁、以日報表為準、營收四項、銷貨單、班別代碼、logo）在資料庫 `store_features`（0116），App 用 `StoreFeatures.of(店名)` 讀（`lib/data/store_features.dart`）；**不要再用店名判斷功能**。班表可用的記號、班別時數也只看資料庫（功能開關 `shiftCodes`＋`shift_mark_options`，見 `lib/data/shift_marks.dart`），App 不內建任何一家店的班別表。
- 訂位頁上每家店自己的內容（logo、封面照、大標、介紹、外語地址、低消、資訊卡的列、姊妹店）在資料庫 `booking_profiles`（ops 0135），訂位頁讀 `reservation_availability` 回的 `profile`；**不要再寫死在 `tool/book/`**。`stores.json` 的 `profile` 是部署時的快照（第一個畫面、搜尋引擎看的靜態資訊卡），以資料庫為準。檢查：`tool/book_check/profile_check.cjs`。
- 訂位頁的樣子（公版階段 2 第 2、3 步，ops 0145，2026-11-27）：訂位設定 → 「訂位頁的樣子」（`lib/screens/booking_page_screen.dart`，只有老闆）改 logo、封面照（含取景）、語言、大標、簡稱、介紹、外語地址與交通、低消金額與說明、資訊卡的列、姊妹店；上面有即時預覽。選圖用 `ycPickBrandImage`（`tool/patch_index.py`：logo 長邊 800 存 PNG 保留透明、封面照長邊 2400 存 JPEG，壓到 2.8MB 以內），存檔時才上傳到公開檔案區 `booking-assets`（`{店的 id}/logo-xxxx.png`，每次新檔名），存好後刪掉換掉的舊上傳圖。訂位頁 `YC.asset()` 看到 `{uuid}/…` 就換成公開檔案區網址（`tool/book_check/profile_check.cjs` 有檢查）。測試：`test/booking_profile_test.dart`、`test/booking_page_screen_test.dart`（要 `--platform chrome`）。
- 訂位頁的機器人驗證（公版階段 2 第 4 步，ops 0146，2026-11-27）：資料庫 `reservation_availability` 回 `captcha`（只有打開 `store_features.booking_captcha` 的店；隱城、小城外沒打開）才載入 Cloudflare Turnstile；送出前用 token 跟 Edge Function `booking-captcha` 換通行證（`YC.captcha`），`book_reservation` 帶 `p_captcha`。沒打開的店什麼都不載入、流程不變。檢查：`tool/book_check/captcha_check.cjs`。
- 用講的改訂位設定（公版階段 2 第 7 步，ops 0147，2026-11-27）：訂位設定 →「用講的改訂位設定（AI）」（`lib/screens/booking_assistant_screen.dart`，只有老闆）。Edge Function `booking-assistant` 只提出建議（改前 → 改後），老闆按確認才呼叫 `booking_assist_apply`；右上角「最近的修改」可以整筆改回去。模型在 `lib/data/booking_assist.dart`。示範版不連 AI，只認得幾種說法。測試：`test/booking_assistant_test.dart`（要 `--platform chrome`）。
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
