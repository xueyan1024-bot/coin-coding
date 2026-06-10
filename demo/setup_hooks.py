#!/usr/bin/env python3
"""把 Coin Coding 的状态通知 hooks 写入 Claude Code 配置（自动备份原配置）。"""
import json, os, shutil, sys

SETTINGS = os.path.expanduser("~/.claude/settings.json")
STATE_DIR = os.path.expanduser("~/.coincoding")
HOOK = os.path.join(STATE_DIR, "hook.sh")

os.makedirs(STATE_DIR, exist_ok=True)
with open(HOOK, "w") as f:
    f.write('#!/bin/bash\necho "$1" > ~/.coincoding/state.txt\n')
os.chmod(HOOK, 0o755)

settings = {}
if os.path.exists(SETTINGS):
    shutil.copy(SETTINGS, SETTINGS + ".coincoding-backup")
    with open(SETTINGS) as f:
        settings = json.load(f)

def entry(state, matcher=None):
    e = {"hooks": [{"type": "command", "command": f"{HOOK} {state}"}]}
    if matcher is not None:
        e["matcher"] = matcher
    return [e]

hooks = settings.setdefault("hooks", {})
hooks["UserPromptSubmit"] = entry("working")
hooks["PreToolUse"] = entry("working", "*")
hooks["PostToolUse"] = entry("working", "*")
hooks["Notification"] = entry("paused")
hooks["Stop"] = entry("idle")

with open(SETTINGS, "w") as f:
    json.dump(settings, f, ensure_ascii=False, indent=2)
print("hooks 已写入", SETTINGS, "（原配置已备份为 settings.json.coincoding-backup）")
