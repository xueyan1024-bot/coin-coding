#!/bin/bash
set -e
cd "$(dirname "$0")"
swiftc -O Auth.swift API.swift PixelEditor.swift main.swift -o CoinCoding \
  -framework AppKit -framework AVFoundation -framework Network
echo "编译完成，启动中…（菜单栏出现 $ 图标）"
./CoinCoding
