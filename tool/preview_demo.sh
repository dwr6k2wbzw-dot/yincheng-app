#!/usr/bin/env bash
# 本機示範預覽：一律用示範資料（DEMO=true）建置，不會連到正式的登入或資料庫。
#   tool/preview_demo.sh [埠號，預設 8766]
# 建好後開 http://localhost:<埠號>/phone.html（390×780 手機框）；示範帳號：email 含 manager＝店長、含 staff＝員工，其他＝老闆。
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

cat > build/web/phone.html <<'EOF'
<!doctype html><html><body style="margin:0;background:#333"><iframe id="f" src="/" style="width:390px;height:780px;border:0;display:block"></iframe></body></html>
EOF

if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "示範版已建好；埠 $port 已經有伺服器在跑，直接重新整理 http://localhost:$port/phone.html"
else
  echo "示範版已建好：http://localhost:$port/phone.html（Ctrl+C 結束）"
  exec python3 -m http.server "$port" --directory build/web
fi
