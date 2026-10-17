#!/bin/bash
# 在 Linux（装了 swiftlang）上：1) 检查界面代码的语法  2) 编译并运行核心逻辑检查。
set -e
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
APP="$REPO/ios/Kai"
cd "$REPO"
node ios/tools/linux-check/dump_prompt.mjs "$REPO" > /tmp/kai_expected_prompt.txt
swiftc -parse "$APP"/*.swift
echo "通过  全部 Swift 文件语法检查"
swiftc -O -o /tmp/kai_check "$APP/Models.swift" "$APP/Persona.swift" "$APP/ZhipuClient.swift" \
  "$APP/ChatStore.swift" "$APP/PingPlanner.swift" "$REPO/ios/tools/linux-check/Shims.swift" \
  "$REPO/ios/tools/linux-check/main.swift"
set -a; [ -f ~/.kai_zhipu.env ] && . ~/.kai_zhipu.env; set +a
/tmp/kai_check "$REPO" /tmp/kai_expected_prompt.txt
