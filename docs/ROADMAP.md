# 最终版路线图（v1.0 目标）

> **目标**：在 Linux 上用**完整的**豆包输入法 —— 键盘 + 语音 + 云端/账号/词库同步。
> **明确不做**：官方候选窗渲染（外观）。候选框继续由 Fcitx 绘制（横向排列已修，上游 PR #4）。
> **决策依据**：官方 UI 需要在 Wayland 下把 Wine 的 X11 窗口精确定位到原生应用光标处，
> 这是全项目唯一有真正不确定性的环节；去掉它之后，其余全部是确定的客户端实现。

---

## 目标架构

```
Fcitx 5 插件
   │  Unix socket（现有，works）
   ▼
bridge (Python)                      现有组件，扩展
   │  Unix socket
   ▼
doubao-host.exe (Wine, mingw)        新增：官方 RPC 客户端宿主
   │
   ├─ LoadLibrary("rpc.dll")
   │  GetProcAddress("CreateRpcClient")  ← 已实测可取到
   │  CreateRpcClient(param)             ← 签名已反汇编确认
   │
   ├─ 经 \\.\pipe\ObricIme\oime-server 调用（24 个 RpcPipe_* 方法）
   │     RpcPipe_KeyEvent / KeyDown / KeyUp / GetInputState
   │     RpcPipe_GetCompTextUtf8 / GetCandidateListUtf8 / GetCommitTextUtf8
   │     RpcPipe_UpdateHostContextUtf8          ← 上下文消歧
   │     RpcPipe_UploadModifyPair               ← 词库同步（JSON）
   │     RpcPipe_AckVoiceCommit / PeekVoiceCommitUtf8   ← 语音
   │     RpcPipe_FocusIn / FocusOut / DeActivate / EnsureServerRunning
   │
   └─ ImeService.exe（常驻单例）
        ├─ ttnet / sscronet  → 云端（多条 443 TLS 实测）
        ├─ 设备注册 did=1184641541794139
        ├─ SAMI 语音连接池（实测持续维护）
        └─ (可选) ui.dll —— 本项目不使用
```

---

## 阶段计划

| 阶段 | 内容 | 风险 | 验证判据 | 状态 |
|---|---|---|---|---|
| **P0** | 键盘桥接跑通 · 候选横向 · 三线隔离 · rime 备份 · wetype 移除 · 官方接口侦察 | — | 11/11 PASS，按键 1.90 ms | ✅ 完成 |
| **P1** | **ImeService 常驻**：systemd 用户服务，开机自启、崩溃自拉 | 低 | `\\.\pipe\ObricIme\oime-server` 长期存在；`systemctl --user is-active` | ⏳ 进行中 |
| **P2** | **最小 RPC 客户端**：mingw 宿主 `LoadLibrary("rpc.dll")` + `CreateRpcClient` + `EnsureServerRunning` / `GetInputState` | 中 | 拿到非零响应，进程不崩 | ⏳ |
| **P3** | **键盘链路改走 RPC**：`KeyEvent` / `GetCandidateListUtf8` / `GetCommitTextUtf8`，与现有路径 A/B | 中 | 候选与上屏文本逐字节一致 | ⏳ |
| **P4** | **上下文 + 词库同步**：`UpdateHostContextUtf8`（喂已上屏文本）、`UploadModifyPair`（JSON） | 低 | 孤立 `gai` 首选「该」；同步有包 | ⏳ |
| **P5** | **语音**：优先走官方 SAMI（`AckVoiceCommit` / `PeekVoiceCommitUtf8` + Linux 侧 PipeWire 录音）；若不通则退回上游 Linux 协调器 + 外部 ASR 适配器 | 中 | 右 Alt 长按说话 → 出字 | ⏳ |
| **P6** | **账号登录** → 云端候选 / 多机同步生效 | 中 | `enable_cloud` 生效，候选含云端结果 | ⏳ |
| **P7** | **发布 v1.0**：`install.sh` / `verify.sh` 覆盖全功能 | 低 | `./verify.sh` 全绿 | ⏳ |

---

## 已知未知（诚实标注）

| 项 | 说明 | 破解方法 |
|---|---|---|
| `CreateRpcClient(param)` 的 param 形态 | 疑似指向 RPC 服务地址的 `std::string*` | 试调用观察；`oime-config.dll::GetRpcServerAdderss()` 应给出地址 |
| `RpcPipe_*` 的调用方式 | 可能本身就是可 `GetProcAddress` 的入口，也可能映射到 `PipeCall(op, ...)` | 逐个 `GetProcAddress` 试 |
| op 号 ↔ 方法名对应表 | `PipeCall` 日志显示底层按 `op=%u` 分发 | 从调用点反推 + 响应行为对照 |
| 登录入口 | 官方设置界面里未发现登录页；登录可能在 `ImeService` 的某个 RPC 或独立 UI | 继续挖 `ime_net_sdk` / `deviceregister` |

---

## 隔离与回退（贯穿全程）

- **三线隔离**：rime / wetype / 豆包 数据面互不触碰（wetype 已移除，rime 已完整备份）
- **每阶段落盘**：台账 + 幂等回退脚本，遵循「原路径 → 动作 → 备份位置 → 反向操作 → 可逆性」
- **一键回退**：`./rollback.sh --apply`（豆包）/ `outputs/ime_vtype_trial_*/rollback_*.sh`（微信）
- **不做破坏性覆盖**：新宿主与现有 `keyboard-host.exe` 并存，A/B 通过后再切换

---

## 风险提示（用户已知悉并接受）

1. **非官方集成**：官方随时可能改协议或版本，破坏兼容
2. **引擎自动联网**：日志中 `automatic_update=enabled`；引擎会自行上报、更新
3. **语音走云端**：录音会发送到字节的 ASR 服务
4. **账号凭据**：登录后产生的凭据等同于账号，不得外传
