#!/bin/bash
set -e

INSTALL_DIR="$HOME/.coincoding"
BIN="$INSTALL_DIR/CoinCoding"
SETTINGS="$HOME/.claude/settings.json"

echo "==> installing Coin Coding..."

# 1. 创建目录
mkdir -p "$INSTALL_DIR"

# 2. 下载二进制（从 GitHub Releases）
RELEASE_URL="https://github.com/xueyan1024-bot/coin-coding/releases/latest/download/CoinCoding"
echo "==> downloading binary..."
curl -fsSL "$RELEASE_URL" -o "$BIN"
chmod +x "$BIN"

# 3. 写入 Claude Code hooks（合并到已有 settings.json，不覆盖其他配置）
echo "==> configuring Claude Code hooks..."
mkdir -p "$HOME/.claude"

python3 - <<'PYEOF'
import json, os, sys

path = os.path.expanduser("~/.claude/settings.json")
cfg = {}
if os.path.exists(path):
    try:
        cfg = json.loads(open(path).read())
    except Exception:
        pass

hooks = cfg.setdefault("hooks", {})

state_dir = os.path.expanduser("~/.coincoding")
working_cmd = f"mkdir -p {state_dir} && echo working > {state_dir}/state.txt"
idle_cmd    = f"mkdir -p {state_dir} && echo idle > {state_dir}/state.txt"

def ensure_hook(event, cmd):
    entries = hooks.setdefault(event, [])
    for e in entries:
        for h in e.get("hooks", []):
            if "coincoding" in h.get("command", ""):
                return  # 已存在，跳过
    entries.append({"hooks": [{"type": "command", "command": cmd}]})

ensure_hook("PreToolUse", working_cmd)
ensure_hook("PostToolUse", idle_cmd)
ensure_hook("Stop", idle_cmd)

open(path, "w").write(json.dumps(cfg, indent=2))
print("    hooks written to", path)
PYEOF

# 4. 启动
echo "==> launching Coin Coding..."
"$BIN" &

echo ""
echo "✓ done. look for the \$ icon in your menu bar."
echo "  to uninstall: rm -rf ~/.coincoding"
