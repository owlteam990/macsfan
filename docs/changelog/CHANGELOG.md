# Changelog

## [1.1.0] - 2026-11-25

### 模块：macfans（风扇控制）

**变动类型：** 新增

**变动描述：**
- 版本：1.1.0（build 2）
- 背景：本机为 Apple M4（Mac16,10），原 README 声明 Apple Silicon 暂不支持写入
- 新增 `FanHardwareControl`：探测 `F*Md`/`F*md`、Intel `FS! `、Apple Silicon `Ftst` 解锁与重试
- 修复 SMC bridge：校验协议 `result` 字节，避免把 NotFound(0x84) 当成键存在
- 手动判定改为仅 mode==1（mode 3 为系统托管，不再误判为手动）
- 传感器目录补充 Apple Silicon 温度键（`Tp*`/`Te*`/`Tg*`/`TH*` 等），默认曲线传感器按本机可用键选择
- Helper 退出（SIGTERM/SIGINT）时交还风扇控制

**影响范围：**
- `MacFans/SMC/smc_bridge.{c,h}`、`SMC.swift`、`FanHardwareControl.swift`、`SensorCatalog.swift`
- `MacFans/Helper/main.swift`、`Services/FanController.swift`、`Models/FanModels.swift`
- `README.md`

**变动人：** Auto
