#!/bin/bash
set -e

SETTINGS="$HOME/.claude/settings.json"
APP_DIR="/Applications/Coin Coding.app"
ZIP_URL="https://github.com/xueyan1024-bot/coin-coding/releases/latest/download/CoinCoding.app.zip"

echo "==> installing Coin Coding..."

# 1. 下载并解压 .app 到 /Applications
TMP=$(mktemp -d)
echo "==> downloading app..."
curl -fsSL "$ZIP_URL" -o "$TMP/app.zip"
unzip -q "$TMP/app.zip" -d "$TMP"
rm -rf "$APP_DIR"
mv "$TMP/CoinCoding.app" "$APP_DIR"
# 去掉网络下载隔离标记，避免“无法打开”弹窗
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

# 2. 写入 Claude Code hooks（合并到已有 settings.json，不覆盖其他配置）
echo "==> configuring Claude Code hooks..."
mkdir -p "$HOME/.claude" "$HOME/.coincoding"

cat > "$HOME/.coincoding/hook.sh" <<'EOF'
#!/bin/bash
echo "$1" > ~/.coincoding/state.txt
EOF
chmod +x "$HOME/.coincoding/hook.sh"

python3 - <<'PYEOF'
import json, os

path = os.path.expanduser("~/.claude/settings.json")
cfg = {}
if os.path.exists(path):
    try:
        cfg = json.loads(open(path).read())
    except Exception:
        pass

hooks = cfg.setdefault("hooks", {})
cmd = os.path.expanduser("~/.coincoding/hook.sh")

def ensure_hook(event, arg, matcher=None):
    entries = hooks.setdefault(event, [])
    for e in entries:
        for h in e.get("hooks", []):
            if "coincoding" in h.get("command", ""):
                return
    entry = {"hooks": [{"type": "command", "command": f"{cmd} {arg}"}]}
    if matcher is not None:
        entry["matcher"] = matcher
    entries.append(entry)

ensure_hook("UserPromptSubmit", "working")
ensure_hook("PreToolUse", "working", "*")
ensure_hook("PostToolUse", "working", "*")
ensure_hook("Stop", "idle")

open(path, "w").write(json.dumps(cfg, indent=2))
print("    hooks written to", path)
PYEOF

# 3. 写入 Trae 全局 hooks（兼容国内版和国际版）
echo "==> configuring Trae hooks..."
python3 - <<'PYEOF'
import json, os

HOOKS = {
    "version": 1,
    "hooks": {
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "mkdir -p ~/.coincoding && echo working > ~/.coincoding/state.txt", "timeout": 10}]}],
        "Stop":             [{"hooks": [{"type": "command", "command": "mkdir -p ~/.coincoding && echo idle > ~/.coincoding/state.txt",    "timeout": 10}]}]
    }
}

for trae_dir in ["~/.trae-cn", "~/.trae"]:
    path = os.path.expanduser(trae_dir)
    hooks_file = os.path.join(path, "hooks.json")
    if not os.path.isdir(path):
        continue
    cfg = {}
    if os.path.exists(hooks_file):
        try:
            cfg = json.loads(open(hooks_file).read())
        except Exception:
            pass
    # 已有 coincoding 配置则跳过
    already = any(
        "coincoding" in h.get("command", "")
        for entries in cfg.get("hooks", {}).values()
        for e in entries
        for h in e.get("hooks", [])
    )
    if not already:
        for event, entries in HOOKS["hooks"].items():
            cfg.setdefault("hooks", {}).setdefault(event, []).extend(entries)
        open(hooks_file, "w").write(json.dumps(cfg, indent=2))
        print(f"    Trae hooks written to {hooks_file}")
PYEOF

# 4. 注册开机自启
echo "==> enabling launch at login..."
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$HOME/Library/LaunchAgents/com.coincoding.app.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.coincoding.app</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$APP_DIR</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
launchctl unload "$HOME/Library/LaunchAgents/com.coincoding.app.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/com.coincoding.app.plist"

# 4. 启动
echo "==> launching..."
open "$APP_DIR"

echo ""
echo "✓ done. look for the \$ icon in your menu bar."
echo "  relaunch anytime: Spotlight (⌘Space) → Coin Coding"
echo "  uninstall: rm -rf '$APP_DIR' ~/.coincoding ~/Library/LaunchAgents/com.coincoding.app.plist"
