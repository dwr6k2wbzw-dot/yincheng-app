# 隱城營運 App（Flutter）

> 狀態：**原型，尚未編譯驗證**。開發環境無法連到 pub.dev 與 Flutter SDK，程式碼沒有實際執行過 `flutter analyze`／`flutter run`。
> 第一次在你的電腦建置時，若有編譯錯誤，把錯誤訊息貼回來即可修正。

## 包含的畫面
| 畫面 | 內容 |
|---|---|
| 登入 | Email＋密碼（Supabase Auth） |
| 店家切換 | 標題列「隱城 ▾」，記住上次選擇；顯示你在該店的角色 |
| 營運總覽 | 老闆／店長：本月營收、目標達成、來客、客單（含／不含活動）、酒水／餐食／總進貨成本率、近 14 天營收、營運警報（一致性檢查）、零用金。員工：只有零用金與說明（營收由資料庫權限隱藏） |
| 進貨 | 最近 30 筆、標示零用金／Excel 匯入／已核銷；老闆／店長可點勾勾核銷 |
| 新增進貨 | 日期（預設營業日，凌晨 6 點前算前一天）、類別、廠商、金額、退貨（負數）、廠商請款／零用金、摘要；防重送 |
| 盤點 | 列表＋明細；草稿 → 送出 → 店長核准／退回；老闆可作廢（填原因）；店長不能核准自己的盤點 |

權限全部由資料庫判斷（RLS＋觸發器），App 只負責顯示按鈕；就算畫面上按得到，資料庫也會擋。

## 第一次建置（需要 Mac＋Xcode 才能跑 iPhone；Android 用 Android Studio）
```bash
# 1. 安裝 Flutter：https://docs.flutter.dev/get-started/install
cd app
flutter create --org tw.yincheng --platforms=ios,android .   # 產生 ios/、android/（不會覆蓋 lib/）
flutter pub get

# 2a. 示範資料模式（不連線，先看畫面）
flutter run --dart-define=DEMO=true

# 2b. 連 Staging（預設已填入 Staging 網址與 publishable key）
flutter run
```

## Staging 準備
1. Supabase SQL Editor 依序執行 `deploy/staging/01_schema.sql`、`02_seed.sql`、`03_test_data.sql`、`08_sample_products.sql`
2. Authentication → Users → Add user 建立帳號，再用 `07_add_member.sql` 加入店家
3. （建議）執行 `04–06_smoke_*.sql`，確認全部 PASS
