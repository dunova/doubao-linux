# doubao-linux

**在 Linux 上复刻豆包输入法：打字、语音、外观，一条命令装齐。**

**v2.0.0** · Linux x86_64 · 非官方

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey.svg)](#前置条件)
[![Engine](https://img.shields.io/badge/engine-0.9.2.7-informational.svg)](#版本钉定)
[![Voice](https://img.shields.io/badge/voice-doubao--say%20v1.8.1-informational.svg)](THIRD_PARTY.md)

> **非官方项目。** 与字节跳动、豆包无隶属关系，未获其背书。
> 官方引擎与词库**不随本仓库分发**，安装时从官方 CDN 下载并校验 SHA-256。
> 本项目只提供 Linux 侧的桥接、编排与外观，不破解、不修改官方二进制。

---

## 这是什么

豆包输入法只有 Windows 版。它在 Linux 上没法直接用，而 Linux 自带拼音的手感、候选词质量和语音体验都差一截。

本项目把三件事拼成一个可用的整体：

```
  ┌─ 打字 ────────────────────────────────────────────────────┐
  │  按键 → Fcitx5 原生插件 → Unix socket → Wine RPC 宿主     │
  │              ← 预编辑、候选词、提交 ← 官方豆包引擎        │
  └───────────────────────────────────────────────────────────┘
  ┌─ 语音 ────────────────────────────────────────────────────┐
  │  麦克风 → 豆包云流式识别 → 可选文字润色 → 注入当前光标    │
  └───────────────────────────────────────────────────────────┘
  ┌─ 外观 ────────────────────────────────────────────────────┐
  │  Doubao-Compact 主题 · 横向候选栏 · 分数缩放修正 · 波形动效│
  └───────────────────────────────────────────────────────────┘
```

打字走的是**官方引擎本体**（不是重写的拼音算法），所以候选词、词频、长句切分与 Windows 版同源。代价是必须用 Wine 跑那个 x86 DLL。

---

## 三部分构成

| 部分 | 你得到什么 | 本仓库提供 | 上游项目 | 许可 |
|---|---|---|---|---|
| **打字** | Fcitx5 里的「豆包」输入法，候选由官方引擎生成 | 部署编排、版本钉定、校验、systemd 集成 | [royess/doubao-ime-linux](https://github.com/royess/doubao-ime-linux) | MIT |
| **语音** | 按住/点按说话，文字落到光标处 | 版本钉定、离线包分发、systemd 单元 | [quanru/doubao-say](https://github.com/quanru/doubao-say) | MIT |
| **外观** | 像豆包的候选栏与动效 | 主题文件、配置补丁、键级合并器 | 本项目原创 | MIT |

三者**互相独立**：可以不装语音，也可以不套外观。装哪个由命令行参数决定。

---

## 一键安装

### 前置条件

- **Linux x86_64**（官方引擎是 x86 DLL；ARM 需模拟层，本项目未覆盖）
- **Arch 系发行版**（脚本用 pacman 装系统包；其他发行版见 [docs/INSTALL.md](docs/INSTALL.md)）
- **Fcitx5** 已在用
- 约 **6 GB** 磁盘（Wine + 引擎 + 运行时）
- 当前用户需在 **input 组**（用于 evdev 快捷键与文字注入）

```bash
sudo usermod -aG input "$USER"   # 若还没在 input 组
# 注销并重新登录
```

### 安装

```bash
git clone https://github.com/dunova/doubao-linux.git
cd doubao-linux

./verify-deps.sh         # 只读检查：缺什么、磁盘够不够、Python 版本对不对
./install.sh --dry-run   # 先看它打算做什么
./install.sh             # 真装
```

`install.sh` 只在装系统包时调用一次 `sudo pacman`，其余全部以当前用户身份完成。它会：

1. 补齐缺失的系统包（只装缺的，已装的不动）
2. 拉取桥接源码并钉在指定 commit
3. 构建 `innoextract`（解官方安装包用）
4. 从官方 CDN 下载引擎安装包，**校验 SHA-256 不匹配就中止**
5. 编译 Fcitx5 插件与 Windows RPC 宿主
6. 建**全新私有 Wine prefix**（不碰你已有的 Wine 环境）
7. 装语音组件（从上游 Release 下载离线包，同样校验）
8. 套用外观（键级合并，**不覆盖**你已有的其它配置）
9. 注册 systemd 服务与 Fcitx 引擎槽

### 装完之后

```bash
systemctl --user restart fcitx5
# 按 Ctrl+Space 切到「豆包」，输入 nihao 验证
./verify.sh        # 端到端验证：引擎、Fcitx、语音、外观四层
```

首次用语音需要登录豆包账号（或在设置里填火山引擎 API Key）。

### 常用参数

| 参数 | 作用 |
|---|---|
| `--check` | 只读检查，不动系统 |
| `--dry-run` | 打印每一步，不执行 |
| `--skip-deps` | 跳过 pacman（依赖已就绪） |
| `--no-voice` | 不装语音，只装打字 |
| `--no-appearance` | 不套外观，保留你自己的主题 |
| `--only-appearance` | 只重套外观（打字/语音已装好时用） |

---

## 版本钉定

本项目**刻意钉死版本**。输入法这种每天都用的东西，上游一次不兼容更新就能让人一整天打不了字，所以宁可手动升级。

| 组件 | 钉定值 | 校验 |
|---|---|---|
| 官方引擎 | `0.9.2.7` | `d777027c…c5db` |
| 桥接源码 | `cfb2af9f…106b`（0.1.0-rc.2） | git commit |
| Wine Mono | `11.3.0` | `df2dfc16…18d3` |
| Doubao Say | `v1.8.1` | 按 Python 版本分四个 SHA-256 |

升级方式：改 `install.sh` 顶部的常量并同步校验和，或等本仓库发版。**不要直接 `git pull` 上游再重跑**，版本不匹配时校验会拒绝执行——这是刻意的。

---

## 上游与依赖谱系

这个项目的代码大部分不是我们写的，说清来源比说清功能更重要。

```
doubao-linux（本仓库，MIT）
├── 打字桥接 ← royess/doubao-ime-linux（MIT）
│   └── 架构参考 ← xdqi/rime-winime（未复制代码，仅参考思路）
├── 语音 ← quanru/doubao-say（MIT）
│   └── 语音/登录组件 ← wurong98/doubao-input-for-linux
│       └── 再上游 ← lilong7676/doubao-murmur（MIT，2026）
├── 解包工具 ← UserUnknownFactor/innoextract_win
└── 外观主题（原创）
```

**Doubao Say 的完整传承链**（它的 NOTICE 里写得很清楚，这里转述）：`lilong7676/doubao-murmur` → 被导入 `wurong98/doubao-input-for-linux`（导入时未保留 Git 历史）→ `quanru/doubao-say`。原始许可为 MIT，Copyright (c) 2026 lilong7676。

各依赖的许可与分发状态见 [THIRD_PARTY.md](THIRD_PARTY.md)。**不随仓库分发**的东西：官方引擎 EXE/DLL、词库、Wine、字体、账号数据。

---

## 外观

三处改动，全部是可逆的配置项：

**1. 主题** `assets/themes/Doubao-Compact/theme.conf`

纯色不透明候选栏，iOS 蓝 `#0A84FF` 高亮，紧凑边距。刻意不带 SVG 背景、`ScaleWithDPI=False`——否则高 DPI 下边距会被放大到失控。这是实测踩出来的，不是审美偏好。

**2. 候选栏** `~/.config/fcitx5/conf/classicui.conf`

```ini
Vertical Candidate List=False    # 横向排列
PerScreenDPI=True                # 多屏各自 DPI
EnableFractionalScale=True       # 分数缩放(如 1.6)下防偏移
Font="PingFang SC 11"            # 脚本会探测；无苹方则退回 Noto Sans CJK SC
```

`EnableFractionalScale` 那条是修 bug 的：1.6 倍缩放下候选窗口会漂移，根因是 classicui 走了 `wl_output.scale(2)` 而不是 `wp_fractional_scale(1.6)`。

**3. 语音动效** `~/.config/doubao-say/settings.json`

```json
{ "waveform_style": "bars", "reduced_motion": false }
```

波形条样式 + 完整动效。想要省电或晕动敏感就设 `reduced_motion=true`。

**合并策略**：只改上表这些键。你原有的其它键、注释、自定义节原样保留，改动前整文件备份。这是 `scripts/merge_conf.py` 存在的原因——整文件覆盖会把用户手工调过的配置抹掉。

想恢复：`./rollback.sh --apply` 按台账逐条还原。

---

## 隔离设计

只写下列路径，与机器上其他输入法（rime / fcitx5 自带拼音 / 其它桥接）**数据面隔离**：

| 类别 | 路径 |
|---|---|
| Fcitx5 插件 | `~/.local/lib/fcitx5/doubaoime.so` |
| addon / inputmethod 描述 | `~/.local/share/fcitx5/{addon,inputmethod}/doubao*.conf` |
| 主题 | `~/.local/share/fcitx5/themes/Doubao-Compact/` |
| 启动器 | `~/.local/bin/doubao-{keyboard,settings}` |
| systemd 用户服务 | `~/.config/systemd/user/doubao-{keyboard,say}.service` |
| Wine prefix 与运行数据 | 源码目录 `work/`（本项目独占） |
| 变更台账 | `~/.cache/doubao-linux/ledger/<时间戳>/` |

**唯一共享点**：`~/.config/fcitx5/profile`。Fcitx 只有一个引擎注册表，所有输入法必须共存于此，这是框架架构决定的，绕不过去。脚本只**追加**引擎槽，不自动改默认输入法、不自动重启 Fcitx。

---

## 已知边界

诚实清单，别指望它没有的东西：

| 项 | 状态 |
|---|---|
| **官方引擎联网** | 引擎可能自行联网；官方 `ImeService.exe` 可在 Wine 下运行并联互联网（已实测）。介意隐私请自查上游 `docs/privacy.md` |
| **账号同步 / 云词库** | 接通的是官方服务栈；AI 联想等高级特性未逐个验证 |
| **Windows 版全部功能** | **不是**完整移植。外观页面、部分快捷键尚未迁移 |
| **Wayland 专项回归** | 在 Hyprland/Wayland 下实测可用，但未对所有合成器逐一验证 |
| **ARM / 非 Arch** | 不支持 / 需手动适配 |
| **性能数据** | v1 在引擎 0.9.0.0 上实测：单次按键 1.90 ms（中位）、匿名内存 334 MB。v2 换到 0.9.2.7 后未重测，量级应相近 |
| **一条被否掉的优化** | 省掉 Xvfb 能省 35 MB 内存，但**不可行**：无 `DISPLAY` 时 Wine 宿主起不来，broker socket 根本不建立。Xvfb 是硬依赖 |

---

## 回退

```bash
./rollback.sh --dry-run    # 先看会做什么
./rollback.sh --apply      # 执行
```

顺序是刻意的：先按台账**逆序还原**被合并的配置（最精确的一层），再调上游卸载器，最后把残留文件移入 `removed/`（只移不删）。系统包只报告、不擅自卸载——`pacman -Rns wine` 可能连带影响你别的软件。

建议装之前先拍快照：

```bash
./rollback.sh --snapshot
```

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 三部分的组件清单、数据流、进程模型 |
| [docs/INSTALL.md](docs/INSTALL.md) | 非 Arch 发行版的包名对照、手动安装步骤 |
| [docs/APPEARANCE.md](docs/APPEARANCE.md) | 外观逐项说明与自定义方法 |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | 常见故障与排查路径 |
| [docs/PRIVACY.md](docs/PRIVACY.md) | 数据流向：什么上传、什么留着本地 |
| [docs/PROTOCOL.md](docs/PROTOCOL.md) | RPC 协议契约（实测确认） |
| [docs/OFFICIAL-RPC.md](docs/OFFICIAL-RPC.md) | 官方 24 个 RPC 方法全清单与反汇编签名 |
| [docs/FULL-VERSION.md](docs/FULL-VERSION.md) | 为什么某些 Windows 特性还没通，以及怎么通 |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | 延迟/内存实测与两条被否掉的优化 |
| [THIRD_PARTY.md](THIRD_PARTY.md) | 全部依赖的许可与分发状态 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 如何提交改动 |
| [CHANGELOG.md](CHANGELOG.md) | 版本变更 |
| [tools/README.md](tools/README.md) | 研究工具：RPC 探测、命名管道探测（安装流程不依赖） |

---

## 许可

本仓库的脚本、文档、主题：**MIT**。

上游桥接（royess/doubao-ime-linux）与语音（quanru/doubao-say）：MIT，保留其原始版权声明。

**豆包官方引擎、词库、设置程序、商标、云服务**：归字节跳动所有，不随本仓库分发，不受 MIT 约束。安装脚本仅从官方渠道下载并校验，用户需自行遵守其服务条款。

详见 [LICENSE](LICENSE) 与 [THIRD_PARTY.md](THIRD_PARTY.md)。
