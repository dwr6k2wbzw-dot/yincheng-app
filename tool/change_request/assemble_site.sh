#!/usr/bin/env bash
# 組合 GitHub Pages 網站：正式版（web-build 分支或剛建好的資料夾）＋各功能許願的預覽（previews 分支 → preview/<代號>/）
# 只放還有對應 cr/<代號> 分支（還沒上線或取消）的預覽；用完的會自動消失。
# 用法：assemble_site.sh <正式版資料夾> <輸出資料夾>
set -euo pipefail
main_dir="$1"; out="$2"
rm -rf "$out"; mkdir -p "$out"
cp -a "$main_dir"/. "$out"/
rm -rf "$out/.git"
tmp="$(mktemp -d)"
if git fetch -q --depth 1 origin previews:refs/remotes/origin/previews 2>/dev/null; then
  git archive origin/previews | tar -x -C "$tmp"
  live=$(git ls-remote --heads origin 'cr/*' | sed 's#.*refs/heads/cr/##')
  mkdir -p "$out/preview"
  n=0
  for d in "$tmp"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    if echo "$live" | grep -qx "$name"; then
      cp -a "$d" "$out/preview/$name"; n=$((n + 1))
    fi
  done
  echo "預覽：$n 個"
else
  echo "還沒有預覽"
fi
rm -rf "$tmp"
