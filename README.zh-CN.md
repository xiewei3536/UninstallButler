<div align="center">

<img src="docs/icon.png" width="128" alt="卸载管家图标">

# 卸载管家 Uninstall Butler

**细心又彻底的 Mac 卸载工具 —— 找出 App 留在系统各处的每一个文件，一次清干净。**

[English](README.md) | [繁體中文](README.zh-TW.md) | **简体中文**

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Architecture](https://img.shields.io/badge/Intel%20%7C%20Apple%20Silicon-Universal-8A2BE2)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

<img src="docs/screenshot.png" width="860" alt="卸载管家主窗口">

</div>

---

## 为什么需要它

把 App 拖进废纸篓，只是删掉了 App 本身；它的偏好设置、缓存、支持文件、沙盒容器、后台程序、安装收据……全都还留在系统里，日积月累就是好几 GB。卸载管家会把这些全部找出来，清楚告诉你找到了什么、为什么判定属于这个 App，然后一次移除。

## 功能

- 🔍 **真正彻底的扫描** —— 针对每个 App 检查 `~/Library` 与 `/Library` 下 40 多个位置：Application Support、偏好设置（含 ByHost）、缓存、沙盒容器、群组容器、窗口状态、HTTPStorages / WebKit / Cookies、日志、崩溃记录、LaunchAgents、LaunchDaemons、特权辅助工具、`pkgutil` 安装收据、快速查看 / 聚焦 / 音频插件、Application Scripts、最近文件列表、`/usr/local/bin` 命令行快捷方式，以及用户专属的 `/var/folders` 缓存与临时文件夹
- 🎯 **精准归属，不靠猜** —— 依 bundle ID 匹配（主程序加上每一个内嵌的辅助程序、XPC、扩展与特权工具）、依代码签名的声明（App Groups、Team ID）、依指向 App 内部的 launchd plist、依指向 App 的 symlink、依沙盒容器的元数据。名称匹配只作为退路并清楚标注；两个已安装 App 同名时一律不用名称匹配
- 🛡 **知道什么是共享的** —— 同开发者其他 App 也在用的群组容器、多个 App 都内嵌的辅助程序（Office、Google 更新器……）会标注“也被这些 App 使用”并默认不勾选；若这是该开发者在你 Mac 上唯一的 App，它的共享更新器会一并列出并标注“同开发者”
- ✨ **残留文件扫描** —— 找出很久以前删掉的 App 留下的文件（以反向域名命名、却没有任何已安装 App、插件、输入法、后台服务或 Launch Services 认领），分为“可放心移除”与“请先确认”
- 🧹 **干净的移除流程** —— 先退出 App 与其辅助程序、卸载登录启动项（`launchctl bootout`）、把所有项目移到废纸篓（或永久删除）、清除安装收据、顺手移除变空的厂商文件夹。系统级的项目只需输入一次管理员密码
- 🧭 **智能列表** —— 很久没用、大型 App、仅 Intel 版（Rosetta）、App Store、运行中；可依名称、大小、最后使用、加入日期排序；每个 App 都标注架构（通用 / Intel / Apple 芯片）
- 👐 **以人为本的界面** —— 每个项目都显示路径、大小与“为什么算它的”；“保留设置与个人数据”开关方便重新安装；鼠标悬停有白话说明；多选 App 可批量卸载
- 🔒 **从设计上就安全** —— 硬性的路径白名单，已知的 Library / 应用程序 / 收据位置以外的东西绝对碰不到，根目录本身永远不会被删；受 SIP 保护的 App 显示锁头。默认移到废纸篓，全部可恢复
- 🌐 **三语界面** —— 简体中文、繁體中文、English，App 内即时切换
- 🚀 **通用二进制** —— Intel 与 Apple 芯片原生运行，macOS 13 Ventura 以上，约 5 MB，无依赖，数据不会离开你的 Mac

## 安装

1. 从最新 Release 下载 `UninstallButler.dmg`
2. 把 **Uninstall Butler** 拖进“应用程序”
3. 第一次打开：**在 App 上右键 → 打开**（未经 Apple 公证，Gatekeeper 会问一次）
4. 建议授权“**完全磁盘访问**”（系统设置 → 隐私与安全性），管家才能连 Cookies 与容器元数据等受保护的文件夹一起检查。不授权也能用，只是略少一点

## 匹配原理

| 依据 | 示例 | 把握度 |
| --- | --- | --- |
| App 或其内嵌辅助程序的 bundle ID | `~/Library/Preferences/com.google.Chrome.plist`、`~/Library/Containers/com.microsoft.Word.widgetextension` | 高 |
| launchd plist 的可执行文件位于 App 内 | `~/Library/LaunchAgents/…` → `/Applications/Foo.app/Contents/MacOS/agent` | 高 |
| 签名声明的 App Group / Team ID | `~/Library/Group Containers/UBF8T346G9.Office` | 高，共享时会标注 |
| 沙盒容器元数据指向 App | `~/Library/Containers/LINE.AudioService` | 高（需完全磁盘访问） |
| 指向 App 的 symlink | `/usr/local/bin/code` | 高 |
| 厂商文件夹 + 产品名 | `~/Library/Application Support/Google/Chrome` | 高 |
| 开发者前缀（该开发者唯一的 App 时） | `~/Library/LaunchAgents/com.google.keystone.agent.plist` | 标注“同开发者” |
| 纯名称 | `~/Library/Logs/Spotify` | 标注“仅依名称匹配” |

若另一个已安装的 App 有“更长”的 bundle ID 前缀匹配（Chrome 与 Chrome Canary），该项目会归给那个 App。

## 从源码构建

只需要 Command Line Tools（不需要 Xcode）：

```bash
git clone https://github.com/xiewei3536/UninstallButler.git
cd UninstallButler
./build.sh            # → dist/UninstallButler.app 与 dist/UninstallButler.dmg（通用）
```

开发用钩子（以下都不会删除任何文件）：

```bash
UNINSTALLBUTLER_SELFTEST=1 UNINSTALLBUTLER_SELFTEST_APP="Google Chrome" .build/debug/UninstallButler
UNINSTALLBUTLER_SNAPSHOT=/tmp/ub.png UNINSTALLBUTLER_LANG=zh-Hans .build/debug/UninstallButler
UNINSTALLBUTLER_DRYRUN=1 .build/debug/UninstallButler     # 完整界面，但移除只是模拟
swift test                                                # 单元测试（需要 Xcode 的 XCTest）
```

## 许可

MIT
