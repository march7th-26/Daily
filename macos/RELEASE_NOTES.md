Daily macOS 1.6.2


Daily 的原生 macOS 版本，与仓库现有 Windows 版本独立发布。

### 下载

- **PKG**：安装到 `/Applications/Daily.app`。
- **ZIP**：解压后将 `Daily.app` 拖入“应用程序”。
- `SHA256SUMS.txt`：上述文件的 SHA-256 校验值。

最低 **macOS 13**；应用和小组件均包含 **Intel x86_64 / Apple Silicon arm64** 架构。更新前请先退出 Daily，待办数据会保留。

### 功能

- 圆圈勾选与取消、手动删除、本地保存，跨天不清空。
- 日间白绿、夜间深灰配紫色；可调整窗口大小，最小内容尺寸 280 × 320。
- 标题下方每日一言，底部完成进度条。
- 菜单栏快捷面板与通知中心小组件。macOS 13 中点击小组件打开应用操作。

### 当前限制

本发行包是 **ad-hoc 本地签名**，没有 Developer ID 签名与 Apple 公证；首次启动可能受到 Gatekeeper 限制，请先确认文件来源，再按系统“隐私与安全性”中的官方流程打开。

已在 Intel / macOS 13.7.8 上构建、运行并检查。Apple Silicon 仅完成交叉编译，未进行真机测试；通知中心实际刷新由系统调度。当前没有跨平台同步或后台自动更新功能。

[macOS 使用与构建说明](https://github.com/march7th-26/Daily/tree/main/macos) · [Windows 下载](https://github.com/march7th-26/Daily/releases/latest)
