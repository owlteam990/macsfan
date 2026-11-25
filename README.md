# MacFans

免费的 macOS 风扇控制工具，功能对齐 [Macs Fan Control](https://crystalidea.com/macs-fan-control)，**自定义预设 / 传感器曲线等 Pro 功能全部免费**。

> 已在 **MacBookPro16,1**（Intel）与 **Mac16,10**（Apple M4）上验证；写入需一次性安装权限助手（root）。

## 下载

从 [Releases](https://github.com/owlteam990/macsfan/releases) 下载最新 `MacFans-x.y.z.dmg`。

**Intel 与 Apple Silicon（M 芯片）共用同一个包**，无需分别下载。DMG 内为 universal 二进制（`x86_64` + `arm64`），运行时自动按机型选择写入路径。

## 功能

- 实时显示风扇转速（最低 / 当前 / 最大）与温度传感器
- 控制策略：
  - **自动**：交还系统 SMC 控制
  - **固定转速**：手动设定 RPM
  - **传感器控制**：按温度曲线调节（原 Pro 功能）
- **预设管理**：创建 / 保存 / 重命名 / 快速切换（原 Pro 功能，免费）
- 菜单栏快捷切换预设
- 登录启动（可选）
- **跨架构写入**：
  - 自动探测模式键 `F*Md` / `F*md`
  - Apple Silicon（M3/M4）：需要时通过 `Ftst` 解锁后再写目标转速
  - Intel：`FS!` 位掩码或直写 SMC

## 要求

- macOS 13+
- Intel 或 Apple Silicon Mac（均走 AppleSMC）
- 无风扇机型仅可查看传感器

## 编译与运行

```bash
cd macfans
xcodebuild -project MacFans.xcodeproj -scheme MacFans -configuration Debug \
  -derivedDataPath build/DerivedData build

open build/DerivedData/Build/Products/Debug/MacFans.app
```

或用 Xcode 打开 `MacFans.xcodeproj` 后 Run。

## 打包 DMG

```bash
./scripts/package-dmg.sh
```

产物：`build/dist/MacFans-<version>.dmg`（universal，含 `.app`、Applications 快捷方式与安装说明）。一份 DMG 即可同时分发给 Intel 与 M 芯片用户。

## 首次控制风扇

1. 打开应用（可先查看转速与温度，无需权限）
2. 点击底部 **安装权限助手…**，输入管理员密码（仅一次）
3. 助手以 LaunchDaemon 方式运行，之后切换预设 / 调转速不再弹窗

卸载助手：

```bash
# 或在应用内扩展；命令行：
sudo launchctl bootout system /Library/LaunchDaemons/com.macfans.helper.plist
sudo rm -f /Library/LaunchDaemons/com.macfans.helper.plist \
  /Library/PrivilegedHelperTools/com.macfans.FanWriteTool
```

## 安全说明

- 强制高转速会增加噪音与功耗；长期全速运行可能缩短风扇寿命。
- 退出前建议切回「自动」预设；助手退出时会尝试交还系统控制并清除 `Ftst`。
- Apple Silicon 上休眠唤醒后可能需重新应用预设（固件会重置诊断标志）。
- 本项目与 CrystalIDEA / Macs Fan Control 无关，为独立实现。

## 许可

免费使用，可自由修改与分发。
