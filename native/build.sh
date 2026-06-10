#!/bin/bash
# 编译并运行 Coin Coding 原生版（需要 Xcode 命令行工具）
set -e
cd "$(dirname "$0")"
swiftc -O main.swift -o CoinCoding
echo "编译完成，启动中…（菜单栏会出现 🪙 图标）"
./CoinCoding
