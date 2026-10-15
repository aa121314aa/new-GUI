#!/usr/bin/env bash
# NewGUI 本地/CI 验证脚本
# 用法: bash ci/verify.sh   (需要 python3 + pip install lupa)
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== 1/3 语法检查 =="
python3 make.py check

echo "== 2/3 打包 =="
python3 tools/build.py

echo "== 3/3 端到端模拟(在线 / 离线 / 自带启动) =="
python3 tools/sim.py
python3 tools/sim.py --offline
python3 tools/sim.py --autostart

echo "全部通过 ✓"
