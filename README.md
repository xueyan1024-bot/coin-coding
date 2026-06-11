# Coin Coding

**English** | [中文](#中文)

---

## What are you doing while your agent is coding?

You kicked off a task in Claude Code and walked away. Or maybe you're in another window, pretending to be productive. The agent is running — but you have no idea if it finished, got stuck, or is still going.

**Coin Coding** is a macOS menu bar app that syncs with Claude Code's activity. While your agent works, coins fall from the top of a floating window. Catch them by clicking. Miss them, and they're gone.

It's a small game. But it also keeps you loosely aware of what's happening — coins are falling means the agent is still working. Coins stopped means it's done (or waiting on you).

![screenshot placeholder]

### A note on awareness

Coin Coding can tell when Claude Code is **working** or **idle**. What it can't detect yet is when Claude Code is waiting for a **permission prompt** — the popup asking you to approve a tool use. In that case, coins will stop falling, same as idle. We're looking into a way to distinguish this in a future update.

---

## Install

Requires macOS. Takes about 30 seconds.

```bash
curl -fsSL https://raw.githubusercontent.com/xueyan1024-bot/coin-coding/main/install.sh | bash
```

This will:
- Download and install the app to `/Applications`
- Wire up Claude Code hooks so the app knows when your agent is active
- Set the app to launch at login

After install, look for the `$` icon in your menu bar.

---

## How to use

1. Start a task in Claude Code as usual
2. The floating `$` window appears automatically while the agent works
3. Click falling coins to collect them
4. Sign in with GitHub to save your score and appear on the leaderboard
5. Customize your coin in the **Coinface** menu (`$` → Coinface)

---

## Uninstall

```bash
rm -rf '/Applications/Coin Coding.app' ~/.coincoding ~/Library/LaunchAgents/com.coincoding.app.plist
```

Then remove the hooks block from `~/.claude/settings.json`.

---

---

# 中文

## Agent 在写代码的时候，你在干嘛？

你在 Claude Code 里发出了一个任务，然后切走了。或者盯着另一个窗口发呆。Agent 在跑——但你根本不知道它跑完了没有，还是卡住了，还是还在继续。

**Coin Coding** 是一个 macOS 菜单栏应用，和 Claude Code 的工作状态实时同步。Agent 干活时，金币从一个悬浮小窗口的顶部往下掉。点击收集，漏接就没了。

是个小游戏。但它也让你对 Agent 的状态保持一种轻度感知——金币在掉，说明 Agent 还在跑；金币停了，说明跑完了（或者在等你）。

![截图占位]

### 关于状态感知的说明

Coin Coding 目前能识别 Claude Code 的**工作中**和**空闲**两种状态。暂时无法检测的是 Claude Code 在等待**权限确认弹窗**的状态——就是 Claude 要执行某个操作、弹出来让你批准的那个窗口。这种情况下金币会停止下落，和空闲表现一样。后续版本会尝试区分这两种状态。

---

## 安装

需要 macOS。大约 30 秒完成。

```bash
curl -fsSL https://raw.githubusercontent.com/xueyan1024-bot/coin-coding/main/install.sh | bash
```

安装脚本会自动完成：
- 下载并安装 app 到 `/Applications`
- 配置 Claude Code hooks，让 app 感知 Agent 状态
- 设置开机自启

安装完成后，菜单栏会出现 `$` 图标。

---

## 使用方式

1. 像平时一样在 Claude Code 里发任务
2. Agent 开始工作时，悬浮 `$` 小窗口自动出现，金币开始下落
3. 点击金币收集
4. 用 GitHub 登录，保存分数并出现在排行榜
5. 在 **Coinface** 菜单里自定义你的金币图案（`$` → Coinface）

---

## 卸载

```bash
rm -rf '/Applications/Coin Coding.app' ~/.coincoding ~/Library/LaunchAgents/com.coincoding.app.plist
```

然后手动从 `~/.claude/settings.json` 里删掉 hooks 相关配置。
