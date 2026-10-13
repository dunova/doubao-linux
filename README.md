# doubao-linux

在 Linux 上用**豆包输入法官方引擎**打字 —— 一键部署、可验证、可回退。

> **非官方项目**。本仓库**不包含**豆包官方引擎、安装包或任何字节跳动的二进制文件；
> 安装时由脚本从**官方渠道**下载并校验 SHA-256。
> 上游桥接：[royess/doubao-ime-linux](https://github.com/royess/doubao-ime-linux)（MIT）。

---

## 这是什么

`royess/doubao-ime-linux` 把**豆包 Windows 输入法 0.9.0.0 的键盘引擎**通过 Wine 桥接进 Fcitx 5，
候选词由**官方引擎**生成。它做得很好，但部署是**多步手工构建**：装 7 个系统包、编译两个工具、
准备 Wine prefix、校验官方安装包、初始化、安装、注册引擎。

**本仓库把这套流程固化成一条命令**，并把实测数据、隔离设计、回退方案一并落盘。

```
按键 → Fcitx5 插件 → Unix socket → Wine RPC 宿主 → 官方豆包引擎
            ← 预编辑、候选词、文字提交 ←
```

---

## 实测数据（Arch Linux / Hyprland / Wayland / i5-1135G7）

### 引擎可用性
| 检查 | 结果 |
|---|---|
| 端到端组件测试（真实 broker + 真实官方引擎） | **11/11 PASS** |
| 关键项 `official candidates include 你好` | ✅ 官方引擎确实返回候选 |
| Fcitx5 侧 | `Loaded addon doubaoime`，引擎槽 `doubao` 可切换 |

### 性能
| 指标 | 值 |
|---|---|
| **单次按键事件延迟** | **1.90 ms**（中位） |
| 一键往返（按下+松开＝2 次连接） | 3.8 ms（min 2.5 / p90 7.0 / max 11.8） |
| 真实匿名内存（anon） | **334 MB** |
| 页缓存（可回收） | 43 MB |
| 服务启动到 active | 约 6 秒 |

> **对比**：另一条路（QEMU 模拟 ARM64 跑微信输入法 Android 引擎）是 **35–66 ms/键**。
> 本方案快 20–30 倍，因为豆包引擎是 **Wine 下的 x86 原生 DLL**，没有指令翻译开销。

### 一条不成立的优化（已实测否定，写在这里避免后人重做）
**省掉 Xvfb 可以省 35 MB —— 但不可行。** 无 `DISPLAY` 时 Wine host 无法启动，
broker socket 根本不建立（`integration_keyboard.py` 报 `ConnectionRefused`）。
Xvfb 是硬依赖。

---

## 快速开始（Arch Linux）

```bash
git clone https://github.com/dunova/doubao-linux.git
cd doubao-linux
./verify-deps.sh        # 只读检查依赖与磁盘，不改任何东西
sudo ./install.sh       # 装依赖 + 构建 + 部署（需 sudo 仅用于 pacman）
```

装完重启 Fcitx5，在输入法配置里添加「豆包」。

**回退**：
```bash
./rollback.sh --apply
```

---

## 隔离设计

本方案**只**写下列路径，与 machine 上其他输入法（rime / fcitx5 自带拼音 / 其他桥接）
**数据面完全隔离**：

| 类别 | 路径 |
|---|---|
| Fcitx5 插件 | `~/.local/lib/fcitx5/doubaoime.so` |
| addon / inputmethod 描述 | `~/.local/share/fcitx5/{addon/doubaoime.conf,inputmethod/doubao.conf}` |
| 启动器 | `~/.local/bin/doubao-{keyboard,settings}` |
| systemd 用户服务 | `~/.config/systemd/user/doubao-keyboard.service` |
| **Wine prefix 与全部运行数据** | **源码目录 `<repo>/work/`（本项目独占）** |

**唯一共享点**：`~/.config/fcitx5/profile`。Fcitx 只有一个引擎注册表，所有输入法必须共存于此，
这是框架架构决定的。安装脚本**不自动重启 Fcitx、不改默认输入法、遇同名文件会停止**。

---

## 已知边界（诚实清单）

| 项 | 状态 |
|---|---|
| **键盘在 Wayland 下** | 上游集成测试用私有 **X11** 显示；本机在 **Hyprland/Wayland** 装成并可切换，但**未做 Wayland 专项回归** |
| 账号同步 / 云词库 / AI 联想 | **未接通**（上游明示）。拿到的是**本地引擎**的候选与字频。**为什么、以及通往完全版的完整接口清单，见 [docs/FULL-VERSION.md](docs/FULL-VERSION.md) 与 [docs/OFFICIAL-RPC.md](docs/OFFICIAL-RPC.md)** —— 已实测：官方 `ImeService.exe`（含字节 ttnet 网络栈、设备注册、SAMI 语音、以及 `\\.\pipe\ObricIme\oime-server` RPC 通道）**能在 Wine 下运行并联互联网**，且官方 **24 个 `RpcPipe_*` 方法**已全部枚举出来 |
| 语音输入 | 上游有桥接，需另配外部 ASR 适配器 |
| **候选词直连官方引擎** | ✅ **已打通（实测，v1.1.0）**：从 `\\.\pipe\ObricIme\oime-server` 可取回非空候选（`nihao` → `你好`）。**尚未接入 Fcitx5 前端**——宿主目前只输出 JSON。见 [docs/RPC_FRAME_FINDINGS.md](docs/RPC_FRAME_FINDINGS.md) |
| **微信中候选窗黑屏** | ⚠️ 未解决（候选数据有效但画面全黑）。根因方向：Hyprland `xwayland:force_zero_scaling=true` 造成坐标/缩放空间错配。见 [docs/CANDIDATE-WINDOW-XWAYLAND.md](docs/CANDIDATE-WINDOW-XWAYLAND.md) |
| 官方设置窗口 | 可用（Wine Mono），但仅映射键盘相关选项 |
| 官方引擎联网 | 引擎可能自行联网；详见上游 `docs/privacy.md` |
| 版本固定 | 只支持豆包 Windows **0.9.0.0**（脚本校验 SHA-256，拒绝其他版本） |

---

## 依赖

`fcitx5` `json-c` `cmake` `base-devel` `python` `wine` `xorg-server-xvfb` `mingw-w64-gcc` `boost`
（语音另需 `python-gobject` `opus` `libpulse`）

安装后约 **2.0 GB**。构建 innoextract 另需 `boost`。

---

## 许可

本仓库的脚本与文档：MIT。
上游桥接：MIT（royess/doubao-ime-linux）。
豆包官方引擎与词库：归字节跳动所有，**不随本仓库分发**，安装时从官方渠道下载并校验。

---

## 文档索引

| 文档 | 内容 |
|---|---|
| [docs/ROADMAP.md](docs/ROADMAP.md) | **最终版路线图**：P0–P7 阶段计划、目标架构、已知未知、隔离与回退 |
| [docs/PROTOCOL.md](docs/PROTOCOL.md) | **RPC 协议契约**（实测确认）：客户端调用形态、14 个 protobuf 消息、方法↔参数映射 |
| [docs/OFFICIAL-RPC.md](docs/OFFICIAL-RPC.md) | 官方 RPC 接口面全清单、24 个方法与反汇编签名、施工路线 |
| [docs/FULL-VERSION.md](docs/FULL-VERSION.md) | 为什么现在拿不到云、官方服务栈在 Wine 下的实测记录 |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | 延迟/内存实测，以及两条被否掉的优化 |
| [docs/RPC_API_SURFACE.txt](docs/RPC_API_SURFACE.txt) · [docs/EXPORTS.txt](docs/EXPORTS.txt) · [docs/PROTOBUF_SCHEMA.txt](docs/PROTOBUF_SCHEMA.txt) | 原始提取数据 |
| [docs/RPC_FRAME_FINDINGS.md](docs/RPC_FRAME_FINDINGS.md) | **候选取回打通报告**（v1.1.0）：根因、真实 ABI、实测候选原文 |
| [docs/V091_VERSION_TRACKING.md](docs/V091_VERSION_TRACKING.md) | 0.9.2.7 追版：账号/同步子系统新增，仍无登录入口 |
| [docs/CANDIDATE-WINDOW-XWAYLAND.md](docs/CANDIDATE-WINDOW-XWAYLAND.md) | 微信候选窗黑屏排查（含 GUI 截图验证与被证伪的假设） |

## 工具

| 工具 | 用途 |
|---|---|
| [tools/pipe_probe.c](tools/pipe_probe.c) | 探测 `\\.\pipe\ObricIme\oime-server` 可连性 |
| [tools/doubao-rpc-probe.c](tools/doubao-rpc-probe.c) | 枚举可 `GetProcAddress` 的 `RpcPipe_*`，试调 `CreateRpcClient` |
| [tools/doubao-rpc-live.c](tools/doubao-rpc-live.c) | 实测 RPC 活性（`EnsureServerRunning`）并抓 protobuf 证据 |
| [tools/doubao-imeservice](tools/doubao-imeservice) | ImeService 常驻启动器（systemd 用） |
| [tools/doubao-rpc-host.c](tools/doubao-rpc-host.c) | **可用**的候选 RPC 宿主（v1.1.0 修复）：向官方引擎发键并取回候选 |
| [tools/wechat-wayland-test.sh](tools/wechat-wayland-test.sh) | 微信 Wayland 原生启动测试（**不替换**原启动器，用于验证黑屏假设） |
