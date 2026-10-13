# 豆包输入法语音输入（P5）可行性侦察

> 目标：**长按右 Alt 说话 → 文字上屏**。
> 侦察日期：2026-10-13 · 环境：Arch (Omarchy) / Wine 11.19 / 豆包 Windows 0.9.0.0 / ImeService 常驻
> 结论强度标注：`实测`（本机跑过）/ `二进制证据`（符号/字符串/反编译）/ `推测`（合理推断，未验证）。
> **硬约束：语音会把麦克风录音上传到豆包云端，两条路都如此，见各自风险段。**

---

## 0. 结论速览（TL;DR）

| 路线 | 判定 | 证据强度 | 一句话 |
|---|---|---|---|
| **路 A**（官方 SAMI 引擎，让 ImeService 自己识别） | **机制已定位，高价值，尚未端到端实测** | 音频入口=强；触发=中；端到端=未跑通 | ImeService 自己用 Wine 录音，触发走 `RpcPipe_SimpleMessage`，识别走 SAMI；但触发载荷字段 + 预检未完全验证 |
| **路 B**（上游 Linux 录音协调器 + 外部 ASR 适配器） | **自包含、可行，默认不安装** | 架构=强（已读源码）；适配器=只读评估 | `parec` 采音 → 适配器 → 豆包云端 → Fcitx 上屏；依赖第三方适配器，按指示只读评估、默认不装 |

> 团队已确认：语音是**设备级匿名能力，不需要账号**（无 account 字段，`ttnet` 只持久化设备身份；frontier 查询 AID 685343 不依赖登录）。因此**不要往"登录解锁语音"方向用力**。

---

## 1. 路 A 关键问题：音频到底从哪进 ImeService？

**判定：(a) ImeService 自己通过 Wine 音频后端录音。** 不是 RPC 送 PCM，也不是命名管道。

### 证据（全部来自本机二进制）

1. **ImeService.exe 内含完整录音栈 `server::VoiceRecorderWin`**（`二进制证据`，`strings` 提取）：
   ```
   voice recorder waveInOpen failed requested_device_index={} mmresult={}
   [MicList] create MMDeviceEnumerator failed hr=0x{:08x}
   server::VoiceRecorderWin::RestoreCaptureEndpointVolume
   [mic-meter] waveInOpen failed wave_in_index={} mmresult={}
   ```
   → 用 Windows `waveInOpen` / `MMDeviceEnumerator` 采集麦克风，即 **Windows 波形音频 API**。

2. **ImeService.exe 内含完整 ASR 栈 `server::SamiAsrClientWin`**（`二进制证据`）：
   ```
   server::SamiAsrClientWin::FeedPcm16kMono        ← 喂 16k 单声道 PCM
   server::SamiAsrClientWin::StartSession / StopSession
   sami asr session started business={} task_id={} sample_rate={} channel={} frame_time_ms={} chunk_bytes={}
   sami websocket state={} url={} msg={}            ← 走 wss 到 doubao 云
   ```
   → 录音（VoiceRecorderWin）把 PCM 喂给 `FeedPcm16kMono`，再由 SAMI 走 WebSocket 上云识别。

3. **RPC 只暴露"结果侧"，没有"音频入口"**（`二进制证据` + `反编译`）：
   - `rpc.dll` 与 `tsf-oime-core.dll` 的语音 RPC 只有 `RpcPipe_AckVoiceCommit` 和 `RpcPipe_PeekVoiceCommitUtf8`。
   - `rea inspect-native-api` 反编译 `RpcPipe_PeekVoiceCommitUtf8` 签名：
     `int RpcPipe_PeekVoiceCommitUtf8(client, out_buf*, len, flags)` —— 返回 int，把识别文本写进**调用方提供的缓冲区**（与 `GetCommitTextUtf8` 同形态）。**是消费结果，不是喂音频。**
   - 不存在 `RpcPipe_SendVoicePcm` / `StartVoiceSession` 之类的方法（`RPC_API_SURFACE.txt` 全 23 方法已枚举）。

4. **命名管道无语音专用通道**（`二进制证据`）：ImeService 只开
   `\\.\pipe\ObricIme\oime-server`、`\oime-server-tsf-log`、`\DoubaoIme\UpdateHealth\`、`\DoubaoIme\settings-rpc`。无音频管道。

→ **结论：音频入口 = (a) ImeService 自身经 Wine waveIn 录音。** 排除 (b) RPC 送 PCM、(c) 命名管道。

### 1.1 路 A 的触发（如何让它开始录音）

`voice_start` 经 **`RpcPipe_SimpleMessage` → `server::Controller::slot_SimpleMessage`** 进入 ImeService（`二进制证据`：ImeService.exe 含 `server::Controller::slot_SimpleMessage` 与 `voice_start` / `input_voiceinput_startfrom` 字符串）。即触发可通过已文档化的 RPC `RpcPipe_SimpleMessage`（在 23 方法清单内）送达，并非只能靠 Windows RAlt 热键钩子。

**未完全验证（中强度）**：`slot_SimpleMessage` 里哪个 `event_name` 字段值映射到 `voice_start`、以及 `voice_start` 的**预检**条件，尚未反编译确认。已知存在 `network_precheck`（需联网，ImeService 已在维护云端连接，应通过）和 `enableGlobalVoiceShortcut`（当前**关**，仅 `enableVoiceShortcut` 开）——后者可能只影响 RAlt 全局热键路径，不一定挡 SimpleMessage 触发，但需运行时确认。

### 1.2 路 A 的音频后端（本机 Wine 能否吃到麦克风）

- 本机音频栈：**PipeWire 运行中**（`pipewire` + `pipewire-pulse`），`pactl info` 正常，PulseAudio socket `/run/user/1000/pulse/native` 存在（`实测`）。
- **真实麦克风存在**（`pactl list sources`）：USB C-Media 单声道麦、DJI 无线麦、主板内置 Mic1/Mic2（`实测`）。
- Wine 的 `HKCU\Software\Wine\Drivers` 音频键**未显式固定**（`二进制证据`：reg 中无该键）→ Wine 自动探测；宿主提供 pipewire-pulse（PulseAudio 协议），Wine 默认 pulse 驱动会绑定它。**推论**：ImeService 的 `waveInOpen` 能路由到真实麦克风（**待运行时确认**）。
- ImeService 日志去向：unit `doubao-imeservice.service` 的 `ExecStart=%h/.local/bin/doubao-imeservice` 无日志重定向 → 进 **journald**，可 `journalctl --user -u doubao-imeservice.service -f` 观察 `voice start` / `sami asr session started` / `voice start rejected`。

### 1.3 路 A 实现计划（下一步，尚未执行）

```
bridge/voice_host (Wine, mingw) 或复用 doubao-rpc-host：
  LoadLibrary("rpc.dll") → CreateRpcClient(NULL)
  RpcPipe_EnsureServerRunning
  RpcPipe_FocusIn            # 注册焦点/会话（预检可能要）
  RpcPipe_SimpleMessage{event_name="voice_start", ...}   # 触发（字段待反编译 slot_SimpleMessage 确认）
  loop: RpcPipe_PeekVoiceCommitUtf8 → 打印识别文本
```
同时 `journalctl -f` 看是否 `voice start` 被接受、SAMI 会话是否起、`FeedPcm16kMono` 是否收到数据。

**路 A 当前状态：未端到端跑通。** 阻塞点 = 触发载荷的 `event_name` 字段（需反编译 `slot_SimpleMessage`）+ 预检是否放行（需运行时看日志）。这两步不做完，不能声称"路 A 已打通"。

---

## 2. 路 B：上游 Linux 录音协调器（只读评估 + 默认不安装）

### 2.1 架构（已读源码 `bridge/daemon.py`、`bridge/audio.py`、`scripts/provider.py`）

```
右 Alt 长按(Fcitx doubaovoice 插件) → D-Bus shortcut → org.doubaoime.Voice1 (daemon.py)
  → audio.py: parec --raw --format=s16le --rate=16000 --channels=1   ← Linux 原生采音
  → 16k 单声道 PCM 以 JSONL {type:audio,audio_base64} 喂给 provider.py(stdin)
  → provider.py 加载外部适配器 entry.py → wss://frontier-audio-ime-ws.doubao.com  ← 豆包云端 ASR
  → 结果 JSONL 回传 → Fcitx org.fcitx.Fcitx5.DoubaoDictation1 上屏
```
- 完全 Linux 原生，麦克风走 `parec`（PulseAudio），**不依赖 Wine / ImeService 的语音栈**。
- 缓存上限 20s PCM（连接未建立前只留内存），最长录音 120s；流式预览经 Fcitx 预编辑。

### 2.2 本机就绪度（只读核查）

| 项 | 状态 |
|---|---|
| `build/fcitx/doubaovoice.so` | **已编译**，但**未装入** fcitx5 addon 目录（`~/.local/share/fcitx5/addon` 为空） |
| `fcitx5/doubaovoice.conf` | 源码在，未部署 |
| `doubao-voice.service` | 单元存在，**disabled / inactive**（未启用） |
| `libopus.so` | 存在（适配器 doubaoime/streaming 需要 `VINPUT_ASR_LIBOPUS_PATH`） |
| `parec` / `gi+Gio` | 存在（可用） |
| `config.local.json` | 存在，但**无 `asr_entry`**（仅 `asr_ipv4_only`）→ 适配器未接线 |

→ 路 B 接近可启用，缺：适配器文件 + `asr_entry` 配置 + 装入/启用 fcitx 插件与服务。

### 2.3 外部 ASR 适配器（第三方，只读安全评估，**默认不安装**）

团队指定固定修订 `38e203e328118e5575722d2d4dd74dd736b6c8d8` 的 `vinput-registry` 的 `doubaoime/streaming`：

- **获取方式**：从 `https://raw.githubusercontent.com/xifan2333/vinput-registry/.../doubaoime/streaming/entry.py` 网络拉取（**本机未安装此适配器**，仅 `doubao/streaming` 在本地）。
- **联网行为**（`registry` 元数据 `二进制证据`）：`provider.doubaoime.streaming` 要求 `VINPUT_ASR_LIBOPUS_PATH`（opus 编解码）与 `VINPUT_ASR_CREDENTIAL_PATH`（凭据文件，首次使用**自动注册设备**）。连接端点即 `frontier-audio-ime-ws.doubao.com`（与 ImeService SAMI 同域，appKey 疑似 `OrnqKvSSrs`）。
- **做了什么**：把麦克风录音（opus 编码）上传到豆包语音云做流式 ASR，回传文本。
- **信任边界**：第三方非官方代码，会**自动注册并持久化设备凭据**（`work/private/`，0700），并与云端通信。**按团队指示默认不安装**；若启用，须先只读审阅其 `requirements`/网络行为并落盘台账。

> ⚠️ **本地现存可疑物（勿用）**：`/home/dunova/.local/share/vinput/providers/doubao/streaming` 是**另一个后端**（`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`，火山引擎），与"豆包输入法语音"不是同一端点；且被**补丁硬编码了一个 `X-Api-Key: 2c6a95d4-...`**（diff `streaming.orig` vs `streaming` 可见）。这是预存在（10-11）的改动，非本项目所为，**安全性不明，禁止使用**。

### 2.4 路 B 启用 / 回退步骤（仅在团队确认后执行）

```
启用：
  1. 只读审阅并落盘台账：拉取 doubaoime/streaming@38e203e entry.py，检查依赖/网络
  2. config.local.json 加 asr_entry=<entry.py 绝对路径>；设 VINPUT_ASR_LIBOPUS_PATH、VINPUT_ASR_CREDENTIAL_PATH
  3. 部署 doubaovoice.so + doubaovoice.conf 到 fcitx5；doubaovoice.conf 设 EnableHotkeys=True, HoldThresholdMs=250
  4. systemctl --user daemon-reload && enable --now doubao-voice.service
  5. 重启 Fcitx 使插件生效
回退：
  systemctl --user disable --now doubao-voice.service
  移除 doubaovoice.so/conf；还原 config.local.json（删 asr_entry）
  busctl ... ReloadAddonConfig doubaovoice（或重启 Fcitx）
```
> 启用会新增 `doubao-voice.service` 并改动 Fcitx 配置；按硬约束须先落盘台账 + 回退脚本，不动现有 `doubao-keyboard/imeservice` 服务。

---

## 3. 风险

- **隐私（两条路共同）**：麦克风录音都会上传到豆包云端（`frontier-audio-ime-ws.doubao.com` 或 `openspeech.bytedance.com`）。文档使用者须知。
- **路 A**：Wine waveIn 能否稳定吃到麦克风待运行时确认；`voice_start` 预检（联网 / 焦点 / `enableGlobalVoiceShortcut`）可能拦截；SAMI 握手指纹（appKey、`protocol_type=3`）随版本可能变。
- **路 B**：第三方适配器不可信、自动注册设备凭据；本机现存被硬编码 key 的 `doubao/streaming` 禁止使用。
- **协议私有**：RPC / SAMI 无公开文档，官方升级会破坏兼容。

---

## 4. 未解明项

1. `slot_SimpleMessage` 中触发 `voice_start` 的确切 `event_name` 字段值 + protobuf 布局（需反编译）。
2. `voice_start` 预检在"经 RPC 触发、无前台编辑控件"场景下是否放行（需运行时看 journal）。
3. Wine pulse 驱动在运行时是否真把 `waveInOpen` 绑定到真实麦克风（需实测 `sami feed chunk` 有非零字节）。
4. 路 B 适配器 `38e203e` 的完整依赖与网络行为（需只读审阅后落盘）。
5. `keyboard.enableGlobalVoiceShortcut=关` 是否影响 SimpleMessage 触发的语音会话（待 1/2 实测）。

---

## 5. 证据索引（本机可复现）

- 二进制：`/home/dunova/src/doubao-ime-linux/work/app/versions/v0.9.0.0/{ImeService.exe,tsf-oime-core.dll,rpc.dll}`
- 反编译产物：`/mnt/nas/quantgo/outputs/doubao_ime_linux_20261013/{peek_voice.json,slot_simplemsg.json}`
- 上游源码：`royess/doubao-ime-linux` 的 `bridge/{daemon.py,audio.py,control.py}`、`scripts/provider.py`、`docs/voice.md`、`fcitx5/doubaovoice.conf`
- 本仓既有：`docs/OFFICIAL-RPC.md`、`docs/PROTOCOL.md`、`docs/RPC_API_SURFACE.txt`、`docs/PROTOBUF_SCHEMA.txt`
- 适配器官方元数据：`/home/dunova/.cache/vinput/registry/providers.json`；本地代码：`/home/dunova/.local/share/vinput/providers/doubao/streaming`
