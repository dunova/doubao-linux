# 官方豆包 IME · RPC 协议契约（实测确认）

> 全部来自**本机实测**（Wine 下真实调用）与二进制符号表挖掘，无推断。
> 环境：Arch (Omarchy) · Wine 11.19 · 豆包 Windows `0.9.0.0` · 2026-10-13

---

## 1. 客户端调用形态（已跑通）

```c
HMODULE h = LoadLibraryA("rpc.dll");

// 入口：NULL 即有效参数，返回 client 对象（48 字节，失败返回 NULL）
void *(*CreateRpcClient)(void*) = GetProcAddress(h, "CreateRpcClient");
void  (*DestroyRpcClient)(void*) = GetProcAddress(h, "DestroyRpcClient");

void *client = CreateRpcClient(NULL);   // ✔ 实测返回 0x00007FFFF02A1F50

// 23 个方法全部可直接 GetProcAddress，第一个参数一律是 client
int (*RpcPipe_XXX)(void *client, ...) = GetProcAddress(h, "RpcPipe_XXX");
```

### 实测结果（决定性）

```
== RpcPipe_* 可 GetProcAddress ==
  → 23 / 23 个全部可取到

== CreateRpcClient(NULL) ==
  返回 00007FFFF02A1F50                       ← 成功

== RpcPipe_EnsureServerRunning(client) ==
  → 1                                         ← RPC 通道活着，服务在线

== RpcPipe_FocusIn(client) ==
  → 1                                         ← 焦点注册成功

== RpcPipe_GetCompTextUtf8 / GetCommitTextUtf8 / GetInlineCommitTextUtf8 ==
  → -1                                        ← 无活动会话时的合理返回

== RpcPipe_GetInputState(client) ==
  → 0
```

---

## 2. 协议是 protobuf（实测抓到证据）

给 `RpcPipe_KeyEvent` 传 `int` 时，引擎自己吐出了错误：

```
[libprotobuf ERROR .../wire_format_lite.cc:618]
String field 'oime.KeyCode.process_name' contains invalid UTF-8 data
when serializing a protocol buffer. Use the 'bytes' type if you intend to send raw bytes.
```

→ **参数是 protobuf 序列化**；`oime.KeyCode` 是消息类型名，`process_name` 是字段名。
（样例位置：`rpc.dll` 的字符串表。）

---

## 3. 全部 protobuf 消息与已知字段

> 来源：`rpc.dll` 字符串表（`oime.*` 前缀）

| 消息 | 已知字段 | 用途推断 |
|---|---|---|
| `oime.Empty` | — | 空参数/占位 |
| `oime.BoolType` | — | 布尔包装 |
| `oime.Int32Type` | — | 整数包装 |
| `oime.StringType` | `value` | 字符串包装 |
| **`oime.KeyCode`** | `process_name` | **按键事件（前台进程名用于上下文）** |
| `oime.KeyProcessResult` | — | 按键处理结果 |
| `oime.InputState` | — | 输入状态 |
| `oime.CursorPos` | — | 光标位置（官方 UI 定位；本项目不使用） |
| `oime.CompTextType` | `inline_text` | 组合中文本（preedit） |
| **`oime.CandidateListType`** | `candidates` | **候选列表** |
| `oime.ConfigType` | `config` | 配置 |
| `oime.ImeChangedType` | `from`, `ime_current`, `ime_last` | 输入法切换通知 |
| `oime.ReportEventType` | `event_name`, `josn_value` | 上报事件（注意原字段名拼写就是 `josn_value`） |
| `oime.SimpleMsgType` | `process_name` | 通用消息 |

---

## 4. 方法 ↔ 参数/返回 映射（据消息名与实测返回推断）

| RpcPipe_ 方法 | 参数（推测） | 返回（推测） |
|---|---|---|
| `EnsureServerRunning` | `Empty` | `BoolType`（实测 1） |
| `FocusIn` / `FocusOut` | `KeyCode`（进程名等） | `BoolType`（实测 1） |
| `DeActivate` | `Empty` | `BoolType` |
| `KeyEvent` | `KeyCode` | `KeyProcessResult` |
| `KeyDown` / `KeyUp` | `KeyCode` | `KeyProcessResult` |
| `GetInputState` | `Empty` | `InputState` / `Int32Type` |
| `GetCompTextUtf8` | `Empty` | `CompTextType`（实测 -1 = 无会话） |
| `GetCandidateListUtf8` | `Empty` | `CandidateListType` |
| `GetCommitTextUtf8` | `Empty` | `StringType` |
| `GetInlineCommitTextUtf8` | `Empty` | `CompTextType` |
| `SetCursorPos` | `CursorPos` | `Empty` |
| `SetUIElementShowState` | `BoolType` | `Empty` |
| `ShowContextMenu` | `Empty` | `Empty` |
| `UpdateHostContextUtf8` | `StringType` | `Empty` |
| `AckVoiceCommit` | `StringType`/`Int32Type` | `BoolType` |
| `PeekVoiceCommitUtf8` | `Empty` | `StringType` |
| `UploadModifyPair` | `StringType`（JSON，实测日志 `json_size={}`） | `BoolType` |
| `RegisterTsfNotifySink` / `Unregister` | 回调指针 | `BoolType` |
| `SimpleMessage` / `SimpleMessageEx` | `SimpleMsgType` | `StringType` |

> ⚠️ 上表"推测"列基于消息名与实测返回值的合理推断，**尚未逐条验证**。
> 下一步用「挖 `oime.*` 的字段号 + 逐个试调观察」把它固化成确定结论。

---

## 5. 完整链路（当前已可达）

```
Linux 侧 bridge (Python)
   │  Unix socket
   ▼
doubao-rpc-host.exe (Wine, mingw)                 ← 待实现（P3）
   │  LoadLibrary("rpc.dll") → CreateRpcClient(NULL)
   │  RpcPipe_KeyEvent(client, KeyCode{process_name,...})
   │  RpcPipe_GetCandidateListUtf8(client, Empty)
   ▼
ImeService.exe（systemd 用户服务，已常驻）
   ├─ ttnet / sscronet → 云端候选、词库同步、账号
   ├─ SAMI 连接池 → 语音 ASR
   └─ 设备身份 did=1184641541794139（已生成）
```

---

## 6. 复现命令

```bash
# 1) 确保服务在位
systemctl --user status doubao-imeservice.service
cd ~/src/doubao-ime-linux
D=/mnt/nas/quantgo/outputs/doubao_ime_linux_20261013
V=work/app/versions/v0.9.0.0

# 2) 枚举可调用导出（23/23）
WINEPREFIX=$PWD/work/settings-prefix WINEDEBUG=-all \
  wine "$D/doubao-rpc-probe.exe" "Z:$PWD/${V//\//\\}\\rpc.dll" 0

# 3) 实测 RPC 活性（EnsureServerRunning 应返回 1）
WINEPREFIX=$PWD/work/settings-prefix WINEDEBUG=-all \
  wine "$D/doubao-rpc-live.exe" "Z:$PWD/${V//\//\\}\\rpc.dll" 1

# 4) 看 protobuf 证据（会在 stderr 打出 oime.KeyCode.process_name）
WINEPREFIX=$PWD/work/settings-prefix WINEDEBUG=-all \
  wine "$D/doubao-rpc-live.exe" "Z:$PWD/${V//\//\\}\\rpc.dll" 2
```
