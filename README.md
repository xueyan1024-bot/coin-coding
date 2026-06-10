# Coin Coding

Claude Code 在干活时，屏幕上掉金币，点击收集，和全球开发者比拼。产品定义见 [PRD.md](PRD.md)。

## 当前进度

- ✅ PRD V1.1 定稿
- ✅ 网页演示版（`demo/`）：验证核心玩法 + hooks 状态联动
- 🚧 Swift 原生版（`native/`）：代码已完成，待在有 Xcode 命令行工具的电脑上编译验证

## 运行原生版（菜单栏应用 + 悬浮窗）

```bash
python3 demo/setup_hooks.py   # 每台新电脑先装一次 hooks
bash native/build.sh          # 编译并启动，菜单栏出现 🪙 图标
```

## 运行演示版

```bash
python3 demo/setup_hooks.py   # 第一次运行：把状态通知装进 Claude Code（自动备份原配置）
python3 demo/server.py        # 启动本地服务器
```

然后浏览器打开 http://localhost:17777 。Claude Code 开始干活时金币自动掉落；也可以点右下角"测试模式"立刻体验。

恢复 Claude Code 原配置：用 `~/.claude/settings.json.coincoding-backup` 覆盖回 `settings.json`。
