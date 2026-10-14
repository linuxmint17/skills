#!/usr/bin/env bash
# analyze-deps.sh — 实测 ELF 依赖：NEEDED 链接库 + dlopen 候选字符串
# 用法: analyze-deps.sh <ELF文件...>
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <ELF文件...>" >&2
  exit 1
fi

for f in "$@"; do
  echo "== $(basename "$f")"
  if command -v ldd >/dev/null 2>&1; then
    echo "-- NEEDED (ldd):"
    ldd "$f" 2>/dev/null | awk '$1 ~ /^lib/ {print "  " $1}' | sort -u || true
  fi
  echo "-- dlopen candidates (strings):"
  strings "$f" 2>/dev/null \
    | grep -oE 'lib[a-zA-Z0-9_+.-]+\.so(\.[0-9]+)*' \
    | sort -u | sed 's/^/  /' || true
  echo "-- not found:"
  ldd "$f" 2>/dev/null | grep 'not found' | sed 's/^/  /' || true
done

echo
echo "判断规则:"
echo "  ldd 有、Depends 无        -> 补进 Depends (NEEDED 缺失会直接启动失败)"
echo "  strings 有、ldd 无        -> dlopen，保留在 Depends (libnotify/libsecret 类)"
echo "  ldd 与 strings 均无        -> 可移除 (libxss1/libxtst6/libuuid1 类)"
echo "  被已声明依赖链传递带入     -> 可移除 (apt-cache depends <库> 核实)"
