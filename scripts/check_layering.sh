#!/usr/bin/env bash
# KeyDrop_Piano 分层强制约束自检（Version 验收文档 V1 的执行器）。
#
# 检查 app/lib/domain/ 下所有 Dart 文件的 import 黑名单：
#   package:flutter/  package:flutter_riverpod/  dart:ui
#   dart:html  dart:js  package:keydrop_piano/platform/
# 全部通过时输出 "Layering check passed." 并以退出码 0 结束。
#
# 用法（仓库根目录）：bash scripts/check_layering.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOMAIN_DIR="$ROOT/app/lib/domain"

BLACKLIST=(
  "package:flutter/"
  "package:flutter_riverpod/"
  "dart:ui"
  "dart:html"
  "dart:js"
  "package:keydrop_piano/platform/"
)

violations=0
scanned=0

if [ ! -d "$DOMAIN_DIR" ]; then
  echo "Layering check passed."
  exit 0
fi

while IFS= read -r -d '' file; do
  scanned=$((scanned + 1))
  line_no=0
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    trimmed="$(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
    case "$trimmed" in
      import\ * | export\ *)
        for banned in "${BLACKLIST[@]}"; do
          case "$trimmed" in
            *"$banned"*)
              rel="${file#"$ROOT/"}"
              echo "LAYERING VIOLATION: $rel:$line_no: $banned"
              violations=$((violations + 1))
              ;;
          esac
        done
        ;;
    esac
  done < "$file"
done < <(find "$DOMAIN_DIR" -name '*.dart' -print0)

if [ "$violations" -eq 0 ]; then
  echo "Layering check passed."
  exit 0
fi

echo "Layering check failed: $violations violation(s) in $scanned file(s)."
exit 1
