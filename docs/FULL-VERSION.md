# 「完全版」可行性侦察：登录 / 云词库 / 多机同步 / AI 联想 / 语音

> 结论：**技术上可达，但属于架构级改造**。本文记录已实测的边界，避免重复劳动。
> 环境：Arch Linux (Omarchy) · Hyprland/Wayland · Wine 11.19 · 豆包 Windows `0.9.0.0` · 上游提交 `62117ce`

---

## 1. 为什么现在拿不到云 —— 诊断结论

**键盘引擎 `rpc.dll` 根本没有网络能力。**

对 `work/app/versions/v0.9.0.0/rpc.dll` 做导入表检查：

```
依赖 DLL: ADVAPI32.dll, KERNEL32.dll, SHELL32.dll, USER32.dll,
          WTSAPI32.dll, dbghelp.dll
```

没有任何 `winhttp / wininet / ws2_32 / crypt32`。

**所以"账号同步未接通"不是"没登录"，而是桥接所依赖的那个组件里压根没有云这条路径。**
上游桥接的做法是「直接加载 `rpc.dll` 调键盘引擎」，天然绕开了官方 IME 的服务层。

---

## 2. 但官方服务层在 Wine 下是活的 —— 已实测

官方安装包解出来的是**完整的 Windows 输入法**，不只是键盘引擎：

```
ImeService.exe                        IME 主服务
ime_net_sdk.dll                       网络 SDK
sscronet.dll                          字节 Cronet 网络栈
TTNetDownloaderCrossPlatform.dll      下载器
QRCoder.dll                           二维码
tsf-oime.dll / tsf-oime-core.dll      TSF 输入核心
DoubaoImeSettings.exe + *.Settings.*  WPF 设置界面
sami_asr_client_win（内嵌）           语音 ASR 客户端
```

直接在隔离的 Wine prefix 里跑 `ImeService.exe`，**它正常启动并持续运行**：

```
[server_main.cpp:2459] server start. [pid=32].
[applog-runtime] process=ImeService appid=685343 app_version=0.9.0 channel=release
[did-compare] current did=1184641541794139                  ← 持久设备 ID 已生成
[TtnetEngine.cpp:238] [ttnet] opaque data store enable=true cert_count=145 api_ready=true
[ttnet-runtime] init result=1
[controller.cpp:2535] voice connection pool warmup trigger
                      env_enable_cloud=1 client_ready=1      ← 云开关是开的
[CronetFrontierClient.cpp:146] frontier query:
    aid=685343&app_name=ImeService&app_version=0.9.0&channel=release
    &device_id=1184641541794139&device_platform=windows&region=CN
[SAMIConnectPoolContext.cpp:28] ConnectPool params protocol_type: 3, url:
    wss://frontier-audio-ime-quic.doubao.com/api/v1/ws;
    wss://frontier-audio-ime-ws.doubao.com/ocean/api/v1/ws
```

**它确实在联网**，观测到已建立的 TLS 连接：

```
ESTAB  10.0.0.214:43118 → 111.6.175.121:443
ESTAB  10.0.0.214:46106 → 111.6.170.21:443
```

落盘目录（自动创建）：`AppData/Roaming/DoubaoIme/{applog,conf,dict,log,parfait,ttnet}/`

### 一条被推翻的猜测
**没有 TSF 硬依赖。** `ImeService.exe` 的导入表里没有 `tsf*` / `msctf*`；
而且 Wine 自带 `msctf.dll` / `msctfp.dll` / `msctfmonitor.dll`。

> ⚠️ **只做实测，不做推断。** 本文所有结论均来自本机实际运行输出。

---

## 3. 因此通往"完全版"的路径

```
现在:   Fcitx 插件 ──Unix socket──> bridge ──RPC──> rpc.dll（键盘引擎，无网络）
                                                        ↑ 断在这里

完全版: Fcitx 插件 ──Unix socket──> bridge ──┬─ RPC ─> ImeService.exe
                                             │            ├─ ime_net_sdk / ttnet → 云端候选 / 词库同步
                                             │            ├─ 设备注册（did）→ 账号
                                             │            └─ sami_asr_client → 语音
                                             └─ 登录 UI / RPC
```

**需要做的（架构级）**：
1. 让 `ImeService.exe` 成为常驻服务（它已经能跑），bridge 改为**通过它取候选**
2. 找到并接上官方登录入口（`did` 已生成，缺的是账号凭证）
3. 语音：官方服务自带 SAMI 通道；但上游桥接走的是**外部社区 ASR 适配器**，两条路可以并存

**风险与边界（必须说清）**：
- 这是**非官方**集成，官方随时可能改协议
- 引擎会自行联网（上报、自动更新已在日志里开启）
- 逐步逼近"把 Windows 输入法完整跑在 Wine 上"，维护成本会显著上升

---

## 4. 各项功能现状对照

| 功能 | 状态 | 说明 |
|---|---|---|
| 键盘输入 | ✅ 可用 | 本仓库一键部署 |
| 候选横向 | ✅ 已修 | 上游 PR #4 |
| 官方设置窗口 | ✅ 可见可用 | 仅键盘类选项会回写到活动引擎配置 |
| 外观（候选框） | ✅ 跟随 Fcitx 主题 | 由 Fcitx 绘制，非官方渲染 |
| **语音输入** | ⚠️ 上游已备好，缺适配器 | 需 `vinput-registry` 的 `doubaoime/streaming`（修订 `38e203e3`）+ `install --voice` |
| **登录 / 多机同步 / 云词库 / AI 联想** | ❌ 未接 | 需按第 3 节改造 |

---

## 5. 复现本文结论

```bash
cd ~/src/doubao-ime-linux
V=work/app/versions/v0.9.0.0

# 键盘引擎没有网络依赖
objdump -p "$V/rpc.dll" | grep 'DLL Name'

# 官方主服务能否在 Wine 下起来（隔离 prefix，25 秒后自动结束）
WINEPREFIX="$PWD/work/settings-prefix" WINEDEBUG=-all \
  timeout 25 wine "$V/ImeService.exe" 2>&1 | grep -E 'ttnet|frontier|did=|enable_cloud'

# 联网证据（另开一个终端看）
ss -tanp | grep ImeService
```
