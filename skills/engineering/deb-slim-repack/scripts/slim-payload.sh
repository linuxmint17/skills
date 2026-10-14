#!/usr/bin/env bash
# slim-payload.sh — 裁剪解包后的 Electron 应用载荷（对照 slim 版做法）
# 用法: slim-payload.sh <解包根目录>      例如 slim-payload.sh ~/work/extracted
# 操作: 1) locales 只留 en-GB/en-US/zh-CN/zh-TW  2) 删除非 linux-x64 的 .node/dll 载荷
#        3) 删除构建中间产物。源码/头文件不动。
set -euo pipefail

root="${1:?usage: $root <解包根目录>}"
app_dir="$(find "$root/opt" -maxdepth 1 -mindepth 1 -type d | head -1)"
[ -n "$app_dir" ] || { echo "no /opt/<App> found under $root" >&2; exit 1; }
U="$app_dir/resources/app.asar.unpacked"

echo "app: $app_dir"

# 1) locales
if [ -d "$app_dir/locales" ]; then
  before=$(ls "$app_dir/locales" | wc -l)
  (cd "$app_dir/locales" && ls | grep -vE '^(en-GB|en-US|zh-CN|zh-TW)\.pak$' | xargs -r rm -f) || true
  echo "locales: $before -> $(ls "$app_dir/locales" | wc -l)"
fi

if [ -d "$U" ]; then
  # 2) 跨平台 .node / dll 载荷
  # 保留: linux-x64 (x64-linux, linux-x64, linux_x64), build/Release, better-sqlite3/bin
  while IFS= read -r f; do
    rm -f "$f"
    echo "rm $f"
  done < <(find "$U" \( -name '*.node' -o -name '*.dll' -o -name '*.dylib' \) -type f \
            | grep -viE 'linux[-_]?x64|x64-linux|build/Release|better-sqlite3/bin' || true)

  # 纯 win/mac 的 prebuilds 目录（常见: weixinpay prebuilds 只有 darwin/win32）
  while IFS= read -r d; do
    rm -rf "$d"
    echo "rm-dir $d"
  done < <(find "$U" -type d -name 'prebuilds' \
            | while read -r d; do
                # 目录下没有任何 linux 载荷才算纯跨平台
                find "$d" -type f \( -name '*.node' -o -name '*.dll' -o -name '*.dylib' \) \
                  | grep -qiE 'linux[-_]?x64|x64-linux' || echo "$d"
              done || true)

  # 3) 构建中间产物
  find "$U" -type d -name 'obj.target' -prune -exec rm -rf {} + 2>/dev/null || true
fi

echo
echo "残留非 linux-x64 的 .node (应为空):"
find "$root/opt" -name '*.node' | grep -viE 'linux[-_]?x64|x64-linux|build/Release|better-sqlite3/bin' || echo "  (none)"
