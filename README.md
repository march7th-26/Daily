# Daily

简洁的桌面待办。支持 Windows 和 macOS，数据保存在本机，不跨设备同步。

## 下载

| 平台 | 系统要求 | 下载 |
| --- | --- | --- |
| Windows | Windows 10 / 11，.NET Framework 4.8 | [Daily.exe](https://github.com/march7th-26/Daily/releases/latest) |
| macOS | macOS 13+，Intel / Apple Silicon | [PKG](https://github.com/march7th-26/Daily/releases/download/macos-v1.6.1/Daily-macOS-1.6.1.pkg) · [ZIP](https://github.com/march7th-26/Daily/releases/download/macos-v1.6.1/Daily-macOS-1.6.1.zip) |

Windows 双击运行；macOS 安装到“应用程序”。macOS 包尚未做 Apple 公证，首次打开说明见 [macOS 文档](macos/README.md#下载与安装)。

## 使用

- 输入事项，按回车添加。
- 点击圆圈完成，再点一次取消；点击 × 删除。
- 待办自动保存，跨天不清空。
- Windows 支持置顶、托盘、贴边收纳、双击编辑、归档历史和应用内更新；macOS 支持待办编辑、归档历史、菜单栏面板、通知中心小组件和明暗主题。

## 构建

Windows（PowerShell）：

```powershell
.\build.ps1
```

macOS（需要完整 Xcode）：

```bash
cd macos
./build.sh
```

[Windows 详细说明](WINDOWS.md) · [macOS 详细说明](macos/README.md)
