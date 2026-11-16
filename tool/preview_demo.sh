#!/usr/bin/env bash
# 本機示範預覽：一律用示範資料（DEMO=true）建置，不會連到正式的登入或資料庫。
#   tool/preview_demo.sh [埠號，預設 8766]
# 建好後開腳本最後印出的網址（/phone.html 是 390×780 手機框）；示範帳號：email 含 manager＝店長、含 staff＝員工，其他＝老闆。
# 打卡用帳號（4 位數密碼打卡）：網址加 ?auto=1&as=kiosk（隱城）或 ?auto=1&as=kiosk-xc（小城外，打卡沒開）；示範密碼 1234＝阿明、5678＝小魚。
# 只給本機預覽用；正式部署（deploy.yml）自己建置，不經過這支腳本。
set -euo pipefail
cd "$(dirname "$0")/.."
port="${1:-8766}"

if [ ! -d web ]; then flutter create --platforms web --project-name yincheng_ops --org tw.yincheng . >/dev/null; fi
python3 tool/patch_index.py
flutter build web --release --pwa-strategy=none --dart-define=DEMO=true

# 防呆：示範資料只會編進示範版，找不到就代表這份建置會連正式環境，不能拿來預覽
if ! grep -q 'demo-no-rate' build/web/main.dart.js*; then
  echo "錯誤：build/web 不是示範版（沒有示範資料），不能拿來預覽。請用這支腳本重新建置。" >&2
  exit 1
fi

cat > build/web/phone.html <<'HTML'
<!doctype html><html><body style="margin:0;background:#333"><iframe id="f" src="/" style="width:390px;height:780px;border:0;display:block"></iframe></body></html>
HTML

# 已經有服務在跑的埠不沿用：無法保證它提供的是這次的示範版（可能是另一份正式建置），改找下一個空埠
busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
want="$port"
while busy "$port"; do
  port=$((port + 1))
  if [ "$port" -gt $((want + 20)) ]; then
    echo "錯誤：埠 $want–$port 都被占用，找不到空埠。請指定其他埠：tool/preview_demo.sh <埠號>" >&2
    exit 1
  fi
done
[ "$port" != "$want" ] && echo "埠 $want 已有其他服務在跑（不確定是不是示範版，不使用），改用埠 $port"

# 從這次的示範目錄啟動自己的伺服器
python3 -m http.server "$port" --bind 127.0.0.1 --directory build/web >/dev/null 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT INT TERM
base="http://127.0.0.1:$port"
for _ in $(seq 1 50); do
  curl -sf -o /dev/null "$base/" && break
  kill -0 "$server" 2>/dev/null || { echo "錯誤：埠 $port 的伺服器沒有啟動成功。" >&2; exit 1; }
  sleep 0.2
done

# 給網址前確認：這個網址回傳的程式檔和這次建置的示範版一模一樣
for f in build/web/main.dart.js*; do
  if ! curl -sf "$base/${f#build/web/}" | cmp -s - "$f"; then
    echo "錯誤：$base 提供的 ${f#build/web/} 和這次的示範版不一樣，不能拿來預覽。" >&2
    exit 1
  fi
done

echo "示範版已建好並確認過：$base/phone.html（Ctrl+C 結束）"
wait "$server"
