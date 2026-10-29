# 架构

三部分、四类进程、两条 socket。这篇讲清楚它们怎么连起来，以及出问题该看哪个环节。

---

## 组件清单

### 打字

| 组件 | 位置 | 职责 |
|---|---|---|
| Fcitx5 插件 `doubaoime.so` | `~/.local/lib/fcitx5/` | 接收按键，维护预编辑状态，把候选画到 Fcitx 的候选栏，提交文字 |
| `keyboard_broker.py` | 上游 `bridge/` | 插件与 Wine 宿主之间的协议中转（Unix socket） |
| `keyboard-host.exe` | 上游 `build/` | MinGW 编译的 Windows 侧宿主，通过 RPC 调用引擎 DLL |
| `rpc.dll` | 私有 Wine prefix | 官方豆包键盘引擎，生成候选 |
| `ImeService.exe` | 私有 Wine prefix | 官方主服务：云候选、账号、词库同步、语音 ASR |
| addon / inputmethod 描述 | `~/.local/share/fcitx5/` | 告诉 Fcitx5 有个叫「豆包」的引擎 |

### 语音

| 组件 | 位置 | 职责 |
|---|---|---|
| `doubao_input`（Python） | `~/.local/share/doubao-say/app/` | GTK4 主程序：录音、流式识别、润色、注入 |
| 录制 | PipeWire / PortAudio | 采集麦克风 |
| 识别 | 豆包云（默认）或火山引擎 API | 流式 ASR |
| 注入 | `wl-copy`/`wtype`（Wayland）或 `xdotool`/`xclip`（X11） | 把文字送到当前光标 |

### 外观

| 组件 | 位置 | 职责 |
|---|---|---|
| `theme.conf` | `~/.local/share/fcitx5/themes/Doubao-Compact/` | 候选栏配色、边距、圆角 |
| `classicui.conf` | `~/.config/fcitx5/conf/` | 排列方向、DPI、分数缩放、字体 |
| `pinyin.conf` | `~/.config/fcitx5/conf/` | 预测、候选数量、云拼音 |
| `settings.json` | `~/.config/doubao-say/` | 波形样式、动效强度 |

---

## 数据流

### 打字一次按键

```
你按下 n
   ↓
Fcitx5（WAYLAND/XIM 前端）→ doubaoime.so
   ↓  Unix socket（$XDG_RUNTIME_DIR/…/keyboard.sock）
keyboard_broker.py
   ↓  stdio 管道
keyboard-host.exe（Wine 内）
   ↓  RPC（\\.\pipe\ObricIme\oime-server）
rpc.dll（官方引擎）→ 返回候选 JSON
   ↑  原路返回：候选、预编辑、提交文本
Fcitx5 候选栏渲染
```

关键点：**引擎是进程外调用**，不是链接进 Fcitx5 的库。这样做的好处是引擎崩溃不会带崩输入法框架；代价是每次按键多一次 socket 往返（实测 1.90 ms 中位）。

### 语音一次识别

```
按下触发键
   ↓
doubao_input 录音（PipeWire）
   ↓  WebSocket（流式）
豆包云 ASR → 增量文本
   ↓  可选：OpenAI 兼容接口润色（如 DeepSeek）
   ↓  Fcitx 焦点校验（确认光标还在原来的窗口）
注入：wl-copy 粘贴 / wtype 直打
```

**焦点校验**是必要的：识别要几百毫秒到几秒，这段时间你可能切了窗口。把文字打到错误的窗口比不打更糟。

---

## 进程模型

| 进程 | 由谁拉起 | 生命周期 |
|---|---|---|
| `doubao-keyboard.service` | systemd user | 随图形会话 |
| `doubao-imeservice.service` | systemd user | 随图形会话；单例，重复启动会自己退出 |
| `doubao-say.service` | systemd user | 随图形会话 |
| `Xvfb` | keyboard 服务内部 | 服务存续期间 |
| `wineserver` | Wine | 由内核对象引用计数管理 |

### 为什么一定要 Xvfb

Wine 的 `winex11` 驱动需要一个可用的 `DISPLAY`，哪怕是虚拟的。没有它，`keyboard-host.exe` 起不来，broker 的 socket 根本不会进入监听状态，插件连上去就是 `ConnectionRefused`。

实测过去掉 Xvfb 能省约 35 MB 内存——**但那条路走不通**，省不掉。别重复这个尝试。

用 Xvfb 而不是复用你的 `DISPLAY`，是为了不往你的桌面塞隐藏窗口、不污染窗口管理器状态。

---

## Fcitx5 集成点

Fcitx5 只有一个引擎注册表：`~/.config/fcitx5/profile`。

```
[Groups/0]
DefaultIM=doubao            ← 默认引擎（脚本不改这个）
[Groups/0/Items/0]
Name=keyboard-us
[Groups/0/Items/1]
Name=doubao                 ← 脚本只追加这一块
```

所有输入法必须挤在这一个文件里，这是框架设计决定的，无法隔离。安装脚本的处理是：

- 只在缺失时**追加**引擎槽，编号自动取当前最大值 +1
- **不改** `DefaultIM`——装完不等于立刻切过去，用哪个由你按 `Ctrl+Space` 决定
- **不重启** Fcitx——正在打字时被重启的体验很差

---

## 版本钉定的理由

四个组件各自迭代，任何一方的不兼容更新都会让整套东西罢工。所以全部钉死：

| 组件 | 值 | 校验方式 |
|---|---|---|
| 官方引擎 | `0.9.2.7` | 安装包 SHA-256 |
| `rpc.dll` | 随引擎 | 上游 `prepare.py` 内置 SHA-256 |
| 桥接源码 | `cfb2af9f` | git commit |
| Wine Mono | `11.3.0` | MSI SHA-256 |
| Doubao Say | `v1.8.1` | 离线包 SHA-256（按 Python 版本四种） |

校验和写死在 `install.sh` 顶部。上游换包而不改版本号的情况真实发生过——所以校验失败即中止，不做"尽力继续"。
