# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.1.0] — 2026-10-13

**从官方引擎取回候选词，打通「候选链路」这一硬关口。**

### 新增
- **RPC 候选取回打通（实测）**：修复后的 `tools/doubao-rpc-host.c` 可向官方 ImeService 的
  `\\.\pipe\ObricIme\oime-server` 发送按键，取回**非空候选**。
  `nihao` → `["你好","👋","ヾ(=^▽^=)ノ","你号","拟好","泥嚎",…]`，逐键 `preedit`
  从 `n` 演进到 `ni'hao`。详见 `docs/RPC_FRAME_FINDINGS.md`。
- `docs/V091_VERSION_TRACKING.md`：0.9.2.7 追版分析。确认该版本**新增账号/同步子系统**
  （`sync_user_dict` / `UserAccountInfoState` / `SyncTaskManager` 等），但**仍无登录入口**。
- `docs/CANDIDATE-WINDOW-XWAYLAND.md`：微信候选窗黑屏排查记录，含真实 GUI 截图验证。
- `tools/wechat-wayland-test.sh`：微信 Wayland 原生启动测试入口（**不替换**原启动器）。

### 修复
- **移除孤儿 `CreateRpcClient(NULL)` 调用**。该调用返回的 client 指针被作为
  `RpcPipe_*` 第一参数传入，而该参数实为**管道地址 C 字符串**（反汇编 helper `0x180014390`
  对 `rcx` 做 `strlen` + `std::string::assign`）。传指针导致后台连接线程读坏内存、
  `CreateFile` 报 `gle=123`(ERROR_INVALID_NAME)、进程 `exit 5`。删除后 stderr 干净。
- **替换 JSON 输出构造器**。原 `obuf`/`ojstr` 对**非 null 结尾**的候选字符串调用
  `lstrlenA`，越界写坏静态区，表现为无限刷 `result:1`（`exit 124`）或随机崩溃（`exit 1`）。
  改为有界直接 `WriteFile` 的 `jwrite`/`jquoted`/`jcands`。

### 订正（推翻此前文档中的错误结论）
- ❌ **旧结论**：「候选为空，按键需按 protobuf `oime.KeyCode` 序列化」——**实测推翻**。
  按键直接传 packed VK 即为正确用法，无需自组帧。
- ❌ **旧结论**：`host.out` 中的 `result=1` 曾被视为「调用结构正确」——**实为宿主 `F` 分支
  硬编码的常量**。真实 `KeyDown` 返回 `-1`。
- ❌ **旧结论**：「0.9.1 追版」——**该版本不存在**。官方 release 通道当前仅 0.9.2.7
  （`version_code=90207`）；`history_version=true` 与 `false` 返回完全相同。
- ❌ **本次过程中的假设**：「`MacOS-Dark` 主题 SVG 背景导致黑屏」——**实测证伪**。
  在 Wayland 原生应用下该主题渲染正常。

### 已知问题
- 微信（CEF/XWayland）中 fcitx5 候选窗渲染为黑屏，候选数据有效但不可读。
  根因方向：Hyprland `xwayland:force_zero_scaling=true` 造成 XWayland 与 Wayland 原生表面
  坐标/缩放空间错配。修复路径见 `docs/CANDIDATE-WINDOW-XWAYLAND.md`，**待目视验收**。
- 候选已可取回，但**尚未接入 Fcitx5 前端**（宿主目前只输出 JSON）。

## [1.0.0] — 2026-10-13

首个版本：一条命令在 Linux 上部署豆包输入法官方引擎（Wine + Fcitx5），
含实测数据、隔离设计与回退方案。
