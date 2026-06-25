# Coin Coding

**English** | [中文](#中文)

![banner](assets/banner_en.png)

---

## What are you doing while your AI is working?

At home, I'm probably scrolling TikTok. At the office, I'm probably just staring at the screen.

So I built a minimal little game to fill the time — **Coin Coding**.

Coin Coding is a macOS menu bar app that syncs in real time with your AI agent's working state. While your agent runs, coins rain down from a floating window. Click to collect them.

Beyond killing time, Coin Coding keeps you passively aware of what your agent is doing — no matter which window you're in.

Tokens burning, coins dropping. Good luck. 🪙

Supports **Claude Code** and **Trae**.

![demo](assets/demo.gif)

---

## How it works

Coin Coding hooks into your AI agent's activity. When your agent starts working, coins fall. When it goes idle, they stop.

**Claude Code** — uses Claude Code Hooks, configured automatically by the install script.

> **Note:** Coin Coding cannot detect when Claude Code is waiting for a **permission prompt**. The game keeps running in those moments.

**Trae** — uses Trae's built-in Hooks system. See the Trae section under Install below.

---

## Features

- Real-time sync with Claude Code and Trae working state
- Minimal coin-catching game
- Transparent floating window — drag anywhere, resize freely
- Custom coin art (Coinface) and click sound presets
- Global leaderboard — coming soon
- Zero configuration after install, launches at login

---

## Install

Requires **macOS**. Windows is not supported.

### Claude Code

```bash
curl -fsSL https://raw.githubusercontent.com/xueyan1024-bot/coin-coding/main/install.sh | bash
```

This will:
- Download and install the app to `/Applications`
- Wire up Claude Code hooks so the app knows when your agent is active
- Set the app to launch at login

After install, look for the `$` icon in your menu bar.

### Trae

**Step 1** — Run the same install script:

```bash
curl -fsSL https://raw.githubusercontent.com/xueyan1024-bot/coin-coding/main/install.sh | bash
```

**Step 2** — Enable in Trae settings:

1. Open Trae **Settings → Hooks**
2. Turn on **导入 CLAUDE 中的 Hooks 配置** (Import Claude hooks config)
3. Make sure the run mode is set to **本地自动运行 (Run locally)**

Done. Send a message to your agent and watch coins fall.

---

## Uninstall

```bash
rm -rf '/Applications/Coin Coding.app' ~/.coincoding ~/Library/LaunchAgents/com.coincoding.app.plist
```

Then remove the hooks block from `~/.claude/settings.json`.

---
---

# 中文

![banner](assets/banner_zh.png)

## 当 AI 工作的时候你在做什么？

如果在家，我可能在刷抖音；如果在公司，我可能在盯着他发呆。

所以我做了一款可以消磨 token 消耗时间的极简小游戏 —— **Coin Coding**。

Coin Coding 是一个 macOS 菜单栏应用，和 AI Agent 的工作状态实时同步。Agent 干活时，金币会从一个悬浮小窗口的顶部持续落下。点击收集金币。

Coin Coding 不仅可以消磨时间，还可以让你在任何窗口都能对 Agent 的工作状态保持一种轻度感知。

token 在跑，金币在爆，祝您发财！🪙

支持 **Claude Code** 和 **Trae**。

![demo](assets/demo.gif)

---

## 工作原理

Coin Coding 通过 hooks 感知 Agent 的工作状态。Agent 开始工作时金币下落，进入空闲时停止。

**Claude Code** — 使用 Claude Code Hooks，安装脚本自动配置。

> **注意：** Coin Coding 暂时无法检测 Claude Code 等待 **Permission prompt** 的状态，出现确认弹窗时游戏会继续运行。

**Trae** — 使用 Trae 内置的 Hooks 系统。详见下方 Trae 安装步骤。

---

## 功能特性

- 实时感知 Claude Code / Trae 工作状态
- 极简集金币小游戏
- 透明背景，随意拖动，随意更改窗口大小
- 自定义金币图案（Coinface）和点击音效
- 全球排行榜 — 即将上线
- 安装后几乎无需配置，开机自动启动

---

## 安装

需要 **macOS**，暂不支持 Windows。

### Claude Code

```bash
curl -fsSL https://raw.githubusercontent.com/xueyan1024-bot/coin-coding/main/install.sh | bash
```

安装脚本会自动完成：
- 下载并安装 app 到 `/Applications`
- 配置 Claude Code hooks，让 app 感知 Agent 状态
- 设置开机自启

安装完成后，菜单栏会出现 `$` 图标。

### Trae

**第一步** — 运行同一个安装脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/xueyan1024-bot/coin-coding/main/install.sh | bash
```

**第二步** — 在 Trae 里开启：

1. 打开 Trae **设置 → Hooks**
2. 打开 **导入 CLAUDE 中的 Hooks 配置**
3. 确认运行方式为 **本地自动运行**

完成。向 Agent 发一条消息，金币就会开始掉落。

---

## 卸载

```bash
rm -rf '/Applications/Coin Coding.app' ~/.coincoding ~/Library/LaunchAgents/com.coincoding.app.plist
```

然后手动从 `~/.claude/settings.json` 里删掉 hooks 相关配置。
