# Coin Coding

**English** | [中文](#中文)

---

## What are you doing while Claude Code is working?

At home, I'm probably scrolling TikTok. At the office, I'm probably just staring at the screen.

So I built a minimal little game to fill the time — **Coin Coding**.

Coin Coding is a macOS menu bar app that syncs in real time with Claude Code's working state. While your agent runs, coins rain down from a floating window. Click to collect them, and compete on the global leaderboard.

Beyond killing time, Coin Coding keeps you passively aware of what your agent is doing — no matter which window you're in.

Tokens burning, coins dropping. Good luck. 🪙

![demo](assets/demo.gif)

---

## How it works

Coin Coding hooks into Claude Code's activity via Claude Code Hooks.

- When Claude starts executing a task: Coin Coding wakes up, the floating window appears, coins start falling
- When Claude goes idle: coins stop

> **Note:** Due to technical limitations, Coin Coding cannot detect when Claude Code is waiting for a **permission prompt** (the dialog asking you to approve a tool use). The game will keep running in those moments, even though your agent is paused.

---

## Features

- Real-time sync with Claude Code working state
- Minimal coin-catching game
- GitHub login + global leaderboard
- Transparent floating window — drag anywhere, resize the window freely
- Custom coin art (Coinface) and click sound presets
- Zero configuration after install, launches at login

---

## Install

Requires **macOS** and **Claude Code**. Windows is not supported. Takes about 30 seconds.

```bash
curl -fsSL https://raw.githubusercontent.com/xueyan1024-bot/coin-coding/main/install.sh | bash
```

This will:
- Download and install the app to `/Applications`
- Wire up Claude Code hooks so the app knows when your agent is active
- Set the app to launch at login

After install, look for the `$` icon in your menu bar.

---

## Uninstall

```bash
rm -rf '/Applications/Coin Coding.app' ~/.coincoding ~/Library/LaunchAgents/com.coincoding.app.plist
```

Then remove the hooks block from `~/.claude/settings.json`.

---
---

# 中文

## 当 Claude Code 工作的时候你在做什么？

如果在家，我可能在刷抖音；如果在公司，我可能在盯着他发呆。

所以我做了一款可以消磨 token 消耗时间的极简小游戏 —— **Coin Coding**。

Coin Coding 是一个 macOS 菜单栏应用，和 Claude Code 的工作状态实时同步。Agent 干活时，金币会从一个悬浮小窗口的顶部持续落下。点击收集金币，可参与全球拾金排名。

Coin Coding 不仅可以消磨时间，还可以让你在任何窗口都能对 Agent 的工作状态保持一种轻度感知。

token 在跑，金币在爆，祝您发财！🪙

![demo](assets/demo.gif)

---

## 工作原理

Coin Coding 通过 Claude Code Hooks 感知 Agent 的工作状态。

- 当 Claude 开始执行任务时：Coin Coding 被唤醒、悬浮窗口自动出现、金币开始下落
- 当 Claude 进入空闲状态时：金币停止下落

> **注意：** 由于技术限制，Coin Coding 暂时无法检测 Claude Code 在等待 **Permission prompt**（弹出让你批准操作的确认弹窗）的状态。出现弹窗时，游戏会继续运行，即使 Agent 实际上已暂停。

---

## 功能特性

- 实时感知 Claude Code 工作状态
- 极简集金币小游戏
- GitHub 登录与全球排行榜
- 透明背景，随意拖动，随意更改窗口大小
- 自定义金币图案（Coinface）和点击音效
- 安装后几乎无需配置，开机自动启动

---

## 安装

需要 **macOS** 和 **Claude Code**，暂不支持 Windows。约 30 秒完成。

```bash
curl -fsSL https://raw.githubusercontent.com/xueyan1024-bot/coin-coding/main/install.sh | bash
```

安装脚本会自动完成：
- 下载并安装 app 到 `/Applications`
- 配置 Claude Code hooks，让 app 感知 Agent 状态
- 设置开机自启

安装完成后，菜单栏会出现 `$` 图标。

---

## 卸载

```bash
rm -rf '/Applications/Coin Coding.app' ~/.coincoding ~/Library/LaunchAgents/com.coincoding.app.plist
```

然后手动从 `~/.claude/settings.json` 里删掉 hooks 相关配置。
