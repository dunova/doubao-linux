# 官方豆包 IME 的 RPC 接口面（逆向侦察记录）

> 本文件的每一条都来自**本机实测与二进制符号表**，没有推断。
> 环境：Arch Linux (Omarchy) · Wine 11.19 · 豆包 Windows `0.9.0.0`
> 侦察日期：2026-10-13
> 用途：这是把「键盘桥接」升级为「100% 完整版」所需的全部接口清单。

---

## 1. 架构全景

```
                     ┌─────────────────────────────────────────────┐
                     │  ImeService.exe  （单例，248 个 pipe 句柄）  │
                     │                                             │
   Fcitx 插件        │  ├─ ttnet / sscronet  → 云端（多条 443 TLS） │
      │              │  ├─ ime_net_sdk (Rust/tokio/reqwest/quinn)  │
      │  Unix socket │  ├─ SAMI 语音连接池（实测持续维护中）        │
      ▼              │  ├─ 设备注册 did=1184641541794139           │
   bridge ───────────┼─>│  ├─ rpc::PipeRpcServer                   │
   （现状：进程内直调  │  └─ ui.dll（tiny-skia 渲染官方候选窗）      │
     rpc.dll，无网络）│                                             │
                     └────────────────┬────────────────────────────┘
                                      │  \\.\pipe\ObricIme\oime-server
                                      │  （实测：外部进程可打开并写入）
                                      ▼
                             官方 RPC 方法（见 §3）
```

**上游 `royess/doubao-ime-linux` 的做法**是「进程内直接调 `rpc.dll` 的键盘引擎」。
`rpc.dll` 的导入表里**没有任何网络组件**（无 `winhttp/wininet/ws2_32`），
所以这条路天然拿不到云端。**要用云端，就必须走 §3 的管道 RPC。**

---

## 2. 通道与协议（实测）

| 项 | 值 |
|---|---|
| RPC 服务端地址 | `\\.\pipe\ObricIme\oime-server` |
| 旁路通道 | `\\.\pipe\ObricIme\oime-server-tsf-log` |
| 实测可连性 | ✅ 外部进程 `CreateFile` 成功，`WriteFile` 成功 |
| 会话隔离 | `PipeServer rejected cross-session client`（有安全检查） |
| 安全描述符 | `PipeServer security descriptor enabled` |
| 分帧 | `PipeCall read header` / `read body` / `write header` / `write body` |
| 调度 | `PipeServer Dispatch no callback op={}`（**op 号分派**） |
| 日志字段 | `PipeCall begin op=%u req_size=%u has_pipe=%d` → `PipeCall ok op=%u resp_size=%u cost_ms=%llu` |

**客户端 API（`rpc.dll` 导出/符号）：**
```
CreateRpcClient / DestroyRpcClient
CreateRpcServer / DestroyRpcServer
RpcClient / RpcClientImpl / RpcServer / PipeRpcServer
PipeCall / PipeServer
CreateNamedPipe / ConnectNamedPipe / DisconnectNamedPipe
GetNamedPipeClientProcessId / PeekNamedPipe
CreateFilePipeBusyFailFast            ← 服务忙时的快速失败路径
::PipeSecurity::PipeSecurity
DoubaoImeRpc
```

---

## 3. RPC 方法全清单（24 个）

> 来源：`rpc.dll` 与 `tsf-oime-core.dll` 符号表，两份完全一致。

| 方法 | 用途 | 对应现有桥接能力 |
|---|---|---|
| `RpcPipe_EnsureServerRunning` | 确保服务在跑（可自启） | 新增 |
| `RpcPipe_FocusIn` / `FocusOut` | 焦点进出 | 对应 `F` 命令 |
| `RpcPipe_DeActivate` | 失活 | 新增 |
| `RpcPipe_KeyEvent` | 按键（含修饰键） | 对应 `K` |
| `RpcPipe_KeyDown` / `KeyUp` | 按下 / 松开（分开） | 对应 `K ... 0/1` |
| `RpcPipe_GetInputState` | 取输入状态 | 新增 |
| `RpcPipe_GetCompTextUtf8` | 取组合中文本 | 对应 `preedit` |
| **`RpcPipe_GetCandidateListUtf8`** | **取候选列表** | 对应 `candidates` |
| `RpcPipe_GetCommitTextUtf8` | 取上屏文本 | 对应 `commit` |
| `RpcPipe_GetInlineCommitTextUtf8` | 取内联提交文本 | 新增 |
| `RpcPipe_SetCursorPos` | 设置光标位置 | **官方 UI 定位用** |
| `RpcPipe_SetUIElementShowState` | 控制官方 UI 显示 | **外观关键** |
| `RpcPipe_ShowContextMenu` | 官方右键菜单 | 新增 |
| **`RpcPipe_UpdateHostContextUtf8`** | **上报宿主上下文** | 上下文消歧（如"我不知道_该怎么说"） |
| `RpcPipe_AckVoiceCommit` | 语音提交确认 | 语音 |
| `RpcPipe_PeekVoiceCommitUtf8` | 取语音识别结果 | 语音 |
| **`RpcPipe_UploadModifyPair`** | **词库修改对上送（JSON）** | **词库同步** |
| `RpcPipe_RegisterTsfNotifySink` / `UnregisterTsfNotifySink` | TSF 通知注册 | 新增 |
| `RpcPipe_SimpleMessage` / `SimpleMessageEx` | 通用消息 | 新增 |

> `PipeServer UploadModifyPair received json_size={}` —— **这一条走 JSON，明文可读**，
> 是全部方法里最容易先打通的一条。

---

## 4. 云端与账号

**符号证据（`ImeService.exe`）：**
```
BuildImeNetCloudRequestData                 ← 云端请求构造
CloudItem@pinyin@oime_engine                ← 云端候选条目
CloudAssoRespItem@pinyin@oime_engine        ← 云端联想响应条目
cloud_convert + google::protobuf::MapEntryLite   ← 云端协议用 protobuf
administrator_account_query_failed
enable_cloud                                ← 配置开关
\files\bin\deviceregister.dll               ← 设备注册组件
AppLog_getDeviceId / AppLog_registerDidObserver
```

**网络栈实现（`ime_net_sdk.dll`）：**
Rust —— `tokio 1.52.3` + `reqwest 0.12.28` + `quinn-proto 0.11.16`（**HTTP/3 QUIC**）+ `tiny-skia 0.12.0`（UI）。

**实测行为：**
```
[controller.cpp] voice connection pool warmup trigger env_enable_cloud=1 client_ready=1
[CronetFrontierClient] frontier query: aid=685343&app_name=ImeService
    &device_id=1184641541794139&device_platform=windows&region=CN
已建立 TLS：120.220.18.106:443 / 183.204.40.101:443 / 111.6.169.60:443 / 111.6.169.58:443
```

**路径入口（`oime-config.dll` 的 `PathManager`）：**
```
GetRpcServerAdderss / GetTsfLogRpcServerAddress
GetCloudDir / GetCloudConfPath / GetSysConfPath
GetDeviceIDCachePath / GetDeviceIDRegisterPath
GetSysDictPath / GetUsrDictPath          ← 系统词库 / 用户词库
GetSysSkinPath                            ← 皮肤（外观）
GetFcitxLogFullPath                       ← 官方连 fcitx 日志路径都准备了
GetServerBinPath / GetWatchdogBinPath / GetToolsBinPath
GetInstallRootPath / GetConfigRootPath / GetParfaitWorkPath
GetDisplayNumber / GetLogDir / GetLogDumpFullPath
```

---

## 5. 外观（候选窗皮肤）

**两个可走的方向：**

**A. Fcitx 绘制（现状）** —— 候选窗由 Fcitx 的 classicui 画。
本仓库的 `install.sh` 已经把上游硬编码的纵向排列改成跟随全局设置（上游 PR #4）。

**B. 官方 UI 绘制（100% 复刻外观）** —— 官方组件本身就是一套独立渲染器：
```
ui.dll  依赖：DWrite / D2D1 / GDI32 / GDI+ / MSIMG32 / USER32   ← 无 TSF 依赖
        内部渲染：tiny-skia 0.12.0（Rust 软件光栅化）
        布局系统：ui::Window / WindowWin / ChildLayout / ListLayout /
                  HorizontalLayout / VerticalLayout / TileLayout /
                  TileExLayout / TabLayout
        实测：Wine 下 LoadLibrary 成功

tsf-oime-core.dll：
        OimeCandidateListUIElement::GetCount / GetSelection
        AUITfCandidateListUIElement   ← 实现了 Windows ITfCandidateListUIElement
        CheckForegroundWindowStyleAndRect / MonitorFromWindow / GetDpiForWindow
        nEnsureNotifyWindow
```

**接法**：让 bridge 调 `RpcPipe_SetCursorPos`（把光标屏幕坐标给服务）
+ `RpcPipe_SetUIElementShowState`（让官方 UI 显示），
官方 `ui.dll` 就会自己开一个 Win32 顶层窗口渲染候选。
这个窗口是 Wine 的 X11 窗口，在 XWayland 下可以叠在 Linux 应用之上。

> ⚠️ **这是唯一一条能让外观 100% 与 Windows 版一致的路径**，也是工程量最大的一环：
> 需要处理坐标换算（Wayland 应用的光标 → 屏幕坐标 → Wine 窗口位置）、层级、
> 以及在 Wayland 下 XWayland 窗口相对原生 Wayland 应用窗口的定位限制。

---

## 6. 语音

上游已有 Linux 录音协调器 + Fcitx 提交插件，但那条路要**外部社区 ASR 适配器**。

而**官方服务自带 SAMI 语音通道**，实测一直在维护连接池：
```
[SAMICORE: needMaintain] connect pool transport resources size: 2, client count: 2
[SAMICORE: RunOnce] all ready, sleep
ConnectPool params protocol_type: 3, timeout: 5000, url:
  wss://frontier-audio-ime-quic.doubao.com/api/v1/ws;
  wss://frontier-audio-ime-ws.doubao.com/ocean/api/v1/ws, appKey: OrnqKvSSrs
```
配合 `RpcPipe_AckVoiceCommit` / `RpcPipe_PeekVoiceCommitUtf8`，
理论上可以走官方语音而不是第三方适配器。

---

## 7. 施工路线（建议顺序）

| 阶段 | 内容 | 风险 |
|---|---|---|
| **1** | 让 `ImeService.exe` 常驻（新增 systemd 用户服务），与本仓库的键盘服务并存 | 低 |
| **2** | 实现 `RpcClient` 最小客户端，先打通 `EnsureServerRunning` + `GetInputState` | 中（要反推帧格式与 op 号） |
| **3** | 键盘链路改走 RPC：`KeyEvent` / `GetCandidateListUtf8` / `GetCommitTextUtf8` | 中 |
| **4** | 接 `UpdateHostContextUtf8`（上下文消歧） | 低 |
| **5** | 接 `UploadModifyPair`（JSON，词库同步）+ 账号登录 | 中 |
| **6** | 接官方 UI：`SetCursorPos` + `SetUIElementShowState` | **高** |

**总风险提示**：RPC 协议私有、无公开文档，需反推；官方版本升级会破坏兼容；
引擎会自行联网并自动更新（日志中 `automatic_update=enabled`）。

---

## 8. 复现本文全部结论

```bash
cd ~/src/doubao-ime-linux
V=work/app/versions/v0.9.0.0

# 键盘引擎没有网络依赖（这是理解一切的起点）
objdump -p "$V/rpc.dll" | grep 'DLL Name'

# RPC 通道名
strings -n 8 "$V/oime-config.dll" | grep -E 'pipe|RpcServer'

# 24 个 RPC 方法
strings -n 8 "$V/rpc.dll" | grep -oE 'RpcPipe_[A-Za-z0-9_]+' | sort -u

# 启动官方服务并观察联网
WINEPREFIX="$PWD/work/settings-prefix" WINEDEBUG=-all \
  setsid timeout 90 wine "$V/ImeService.exe" >/tmp/is.log 2>&1 < /dev/null &
sleep 20
ss -tanp | grep ImeService          # 应看到多条 443
grep -E 'ttnet|frontier|enable_cloud' /tmp/is.log

# 官方 RPC 管道可连性（本仓库带探测程序源码）
#   outputs/doubao_ime_linux_20261013/pipe_probe.c
```

---

## 9. 2026-10-13 追加：官方 RPC 客户端 API 的导出与签名（反汇编实测）

### 9.1 `rpc.dll` 的纯 C 具名导出（可直接 `GetProcAddress`）

```
CreateRpcClient                     ✔ 实测 GetProcAddress 成功
DestroyRpcClient                    ✔ 实测 GetProcAddress 成功
RpcPipe_KeyEvent
RpcPipe_KeyDown / RpcPipe_KeyUp
RpcPipe_GetInputState
RpcPipe_GetCompTextUtf8
RpcPipe_GetInlineCommitTextUtf8
RpcPipe_SetCursorPos
RpcPipe_SetUIElementShowState
RpcPipe_RegisterTsfNotifySink
RpcPipe_AckVoiceCommit
RpcPipe_PeekVoiceCommitUtf8
```

另有 C++ 修饰名导出（需用修饰名取）：
```
?CreateRpcServer@rpc@@YAPEAVRpcServer@1@XZ
?DestroyRpcServer@rpc@@YAXPEAVRpcServer@1@@Z
?GetFocusOwnerCaps@rpc@@YAIXZ
?GetFocusOwnerPid@rpc@@YAKXZ
?IsPidImeActive@rpc@@YA_NK@Z
```

### 9.2 `CreateRpcClient` 的签名（RVA 0x12e60 反汇编）

```asm
180012e60  push %rbx
180012e62  sub  $0x30,%rsp
180012e6f  mov  %rcx,%rbx              ; 唯一参数（Win64 第一参数）
180012e72  mov  $0x30,%ecx
180012e77  call 0x18016311c            ; operator new(0x30) → 48 字节对象
180012e81  test %rax,%rax
180012e84  je   0x180012e98            ; 失败 → 返回 0
180012e86  mov  %rbx,%rdx              ; 原参数 → 构造第 2 参
180012e89  mov  %rax,%rcx              ; 新对象 → 构造第 1 参(this)
180012e8c  call 0x180010260            ; 构造
180012e92  ret
```

**推导签名：**
```c
typedef void* (*CreateRpcClient_t)(void *param);   // 失败返回 NULL
```

### 9.3 `DestroyRpcClient` 的签名（RVA 0x13040）

```asm
180013040  test %rcx,%rcx
180013043  je   0x180013050      ; 空指针直接返回
180013045  mov  (%rcx),%rax      ; 取 vtable
180013048  mov  $0x1,%edx        ; 参数 1
18001304d  jmp  *(%rax)          ; 虚调用 vtable[0]（deleting destructor）
180013050  ret
```

**推导签名：**
```c
typedef void (*DestroyRpcClient_t)(void *client);
```

### 9.4 这意味着什么

桥接的 Windows 宿主可以**直接使用官方 RPC 客户端**，不必从头反推私有线协议：

```c
HMODULE lib = LoadLibraryA("rpc.dll");
void *(*mk)(void*)  = (void*)GetProcAddress(lib, "CreateRpcClient");
void  (*del)(void*) = (void*)GetProcAddress(lib, "DestroyRpcClient");
void *client = mk(param);      // 连接 \\.\pipe\ObricIme\oime-server
/* ... 用 RpcPipe_* 方法 ... */
del(client);
```

**仍待确定（下一步）**：
1. `param` 的具体形态（疑似指向 RPC 服务地址的 `std::string*`，
   可由 `oime-config.dll` 的 `GetRpcServerAdderss()` 取得）—— 需试调观察
2. `RpcPipe_*` 作为**导出函数**的调用方式：它们可能本身就是可 `GetProcAddress` 的入口，
   也可能是宏映射到 `PipeCall(op, ...)`；`PipeCall begin op=%u` 表明底层按 **op 号** 分发
3. op 号 ↔ 方法名的对应表（需从调用点或响应行为反推）
