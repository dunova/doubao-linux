# 变更记录

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [2.0.0] - 2026-10-29

从「只装打字」升级为「打字 + 语音 + 外观」的完整套件。安装脚本重构为分阶段模块。

### 新增

- **语音输入**：集成 [Doubao Say](https://github.com/quanru/doubao-say) v1.8.1。
  按其 Python 版本（3.11/3.12/3.13/3.14）选择对应离线包，校验 SHA-256 后调用上游安装器。
- **语音 systemd 单元**：上游不提供，本仓库补 `doubao-say.service`，
  与键盘服务一样随图形会话起停、崩溃自动重试。
- **外观层**：
  - `Doubao-Compact` 主题（纯色不透明候选栏，iOS 蓝 `#0A84FF` 高亮）
  - 候选栏横向排列、屏幕级 DPI、分数缩放修正、CJK 字体自动探测
  - 候选词预测与云拼音参数
  - 语音波形样式与动效强度
- **`scripts/merge_conf.py`**：键级配置合并器。只改目标键，保留用户其余配置、
  注释与自定义节；幂等，可重复执行。
- **安装台账**：所有写入记录到 `~/.cache/doubao-linux/ledger/<时间戳>/`，
  `rollback.sh` 据此逐步还原。
- **安装参数**：`--no-voice`、`--no-appearance`、`--only-appearance`、`--check`。

### 变更

- **官方引擎升级**：`0.9.0.0` → `0.9.2.7`（校验和 `d777027c…c5db`）。
- **桥接源码升级**：`62117ce`（rc.1 后）→ `cfb2af9f`（`0.1.0-rc.2` + 清理 opt-in）。
  该版本包含我们提交的「候选排列跟随全局设置」修复（上游 PR #4）。
- **安装脚本模块化**：`install.sh` 变为编排器，具体步骤拆到 `scripts/10-deps.sh`、
  `20-keyboard.sh`、`30-voice.sh`、`40-appearance.sh`，公共函数在 `lib.sh`。
- **`verify.sh` 扩展**：新增语音与外观两层检查，Fcitx 单元名不再硬编码
  （兼容 `omarchy-fcitx5.service` 与 `fcitx5.service`）。切换引擎后会还原用户原引擎。
- **`rollback.sh` 重写**：优先按台账逆序还原（最精确），再调上游卸载器，
  最后移出残留文件。
- **文档体系**：新增架构、安装、外观、排障、隐私、上游谱系六篇。

## [1.0.0] - 2026-10-13

首个可用版本：只覆盖打字。

### 新增

- 一键部署 Fcitx5 桥接 + 官方豆包 Windows 引擎 `0.9.0.0`（Wine）
- `install.sh` 八步流程，支持 `--dry-run`、`--skip-deps`
- `verify.sh` 端到端验证（真实 broker + 真实引擎集成测试）
- `rollback.sh` 幂等回退，安装前快照
- `verify-deps.sh` 只读依赖检查
- 端到端实测数据：单次按键 1.90 ms（中位）、匿名内存 334 MB
- 官方 RPC 接口面逆向文档（24 个方法）
