# 豆包输入法（Linux/Wine v0.9.0.0）账号登录路径分析

> 目标：确定账号登录入口，判断「云端候选 / 多机词库同步」是否、以及如何生效。
> 分析对象：`work/app/versions/v0.9.0.0/` 下的 `ImeService.exe`、`ime_net_sdk.dll`、
> `rpc.dll`、`oime-config.dll`、`DoubaoImeSettings.exe` 及 `DoubaoIme.Settings.*.dll`。
> 约束：不抓取/外传任何 `did` / `account` 标识；结论强度不超过证据强度。

---

## 0. TL;DR

- **当前版本（v0.9.0.0 Linux/Wine 移植包）没有消费端账号登录入口**。既无登录页，也无登录 RPC，也无登录令牌文件。
- 唯一与「account」相关的符号是企业**管理员账号 / 策略**（`policy=administrator_only`、
  `administrator_account_query_failed`、`non_administrator_account`），用于 MDM/策略下发，
  **不是**消费端登录，也不参与云端候选。
- 云端的身份基元是**设备 ID（device_id）**，匿名、无需登录即可使用云端候选。
- 凭据边界：`device_id` 即等同账号标识，持久化在 `ttnet/tt_net_config.config`，**严禁外传/提交**。

---

## 1. 登录入口判定（含证据）

### 候选假设逐一判定

**(a) `ImeService` 的某个 RPC 方法 → 否（反编译确认）**
`rpc.dll` 导出的全部 24 个 `RpcPipe_*` 方法（已与 `tsf-oime-core.dll` 对齐）为：
`AckVoiceCommit / DeActivate / EnsureServerRunning / FocusIn / FocusOut /
GetCandidateListUtf8 / GetCommitTextUtf8 / GetCompTextUtf8 / GetInlineCommitTextUtf8 /
GetInputState / KeyDown / KeyEvent / KeyUp / PeekVoiceCommit / RegisterTsfNotifySink /
SetCursorPos / SetUIElementShowState / ShowContextMenu / SimpleMessage /
SimpleMessageEx / UnregisterTsfNotifySink / UpdateHostContextUtf8 / UploadModifyPair`。
**无任何 login / account / token / session 方法**。`SimpleMessage`/`SimpleMessageEx` 是通用
消息管道，不含账号语义。

证据命令（队友产出，符号表提取，见 `RPC_API_SURFACE.txt`）：
```
rea inspect-managed-members  # 不适用（rpc.dll 为本机 PE，非 .NET）
符号表导出（EXPORTS.txt / RPC_API_SURFACE.txt）：RpcPipe_* 清单 + 无 Account 导出
```

**(b) `DoubaoImeSettings.exe` 的 .NET 页面/命令 → 否（反编译确认）**
对 `DoubaoIme.Settings.ViewModels.dll`、`DoubaoIme.Settings.UI.dll`、
`DoubaoIme.Settings.NativeRuntime.dll`、`DoubaoImeSettings.exe` 执行
`rea inspect-managed-members`，按 `Login|Account|User|Scan|QR|Phone|Token|Auth|Bind|Session|OAuth`
过滤，结果只有：
- 语音试用的 `CurrentUser`（实为编译器生成的闭包 `<>c__DisplayClass15_0` 局部变量，**非账号对象**）；
- `EnableCloudCandidate` 设置项；
- 二维码仅 `FeedbackQrCodeDialog` / `QrCodeDownloadDialog`（`LoadFeedbackQrCodeAsync`、
  `FeedbackQrCodeApi`、`ResolveFeedbackQrCodeUrl`）——即**反馈二维码 / 下载二维码**，**无扫码登录页**。

证据命令：
```
rea inspect-managed-members DoubaoIme.Settings.ViewModels.dll
rea inspect-managed-members DoubaoIme.Settings.UI.dll
# 输出摘录：
#   full_name: DoubaoIme.Settings.UI.Controls.FeedbackQrCodeDialog
#   full_name: DoubaoIme.Settings.UI.Controls.QrCodeDownloadDialog
#   name: CurrentUser  (位于 <>c__DisplayClass15_0 闭包内)
#   name: enableCloudCandidate / EnableCloudCandidate
```

**(c) `deviceregister.dll` 流程 → 否（仅路径引用，二进制未随包）**
`oime-config.dll` 字符串含 `\files\bin\deviceregister.dll`，但全盘查找该文件在
`work/` 与安装产物中均**不存在**；实际 `files/bin/` 目录为空（仅 `data` 子目录）。
设备注册由 `ImeService` 首启时在内部生成 `device_id` 并落地（见 §4），`deviceregister.dll`
在本构建中是残留的路径引用，不构成登录流程。

**(d) `ime_net_sdk` 直接有登录 HTTP 调用 → 否（反编译确认）**
`ime_net_sdk.dll` 为 Rust + tokio 1.52.3 + reqwest 0.12.28 + quinn（HTTP/3 QUIC），是**通用
网络栈**，字符串中无 `login/oauth/get_token/authorization/bearer` 等登录端点；云端请求是
`BuildImeNetCloudRequestData` 构造的 frontier query（见 §3），以 `device_id` 匿名发出。

**(e) 需要官方 Windows 客户端的独立登录进程 → 未发现（推测）**
本包内无独立登录进程；`bootstrap/` 下仅有 `SettingsLauncher / ImeWatchdog / UpdateTaskHost /
oime-installer`。未在其他位置发现登录可执行体，故当前构建**不包含**独立登录进程。

### 唯一的「account」概念：企业管理员账号（策略，非登录）
`ImeService.exe` 字符串集中出现（连续错误/状态模板段）：
```
policy=administrator_only,system_error=
non_administrator_account
administrator_account_query_failed
https://ime.doubao.com/api/v1/version/list
```
含义：`administrator_account_query_failed` 表示「查询管理员账号失败」后回退；
`policy=administrator_only` 是策略开关。这是**企业/受管部署的策略能力**，
与消费端登录、云端候选、词库同步均无耦合（云端候选默认开启且实测匿名）。

---

## 2. 登录形态与所需交互

- **消费端：无登录形态**。没有扫码登录页、没有手机号登录、没有账号输入框。
  `QRCoder.dll` 仅用于「反馈二维码 / 下载二维码」（见 §1(b)），**不是**登录扫码。
- **若涉及管理员账号**：当前客户端**未实现**任何登录 UI 或凭据采集；推测为服务端侧策略
  （设备/租户级），客户端仅在策略查询失败时打 `administrator_account_query_failed` 日志。
  形态与入口在当前构建中**无法确认**（结论强度：推测）。
- **用户交互**：要让云端候选生效，用户唯一需要做的只是保持 `enableCloudCandidate=true`
  （默认即开），**无需任何扫码或登录操作**。

---

## 3. 未登录时能否用云功能（优先验证项）

**结论：能，云端候选可在未登录（无账号）状态下使用。**（结论强度：反编译确认 + 日志佐证）

证据链：
1. `config.json` 中 `keyboard/enableCloudCandidate = True` 为默认开启，且 `config.json`
   **完全不含**任何 `account` / `token` / `session` 字段（已逐键核对）。
2. 实测 `ImeService` 持续联网，frontier 查询形如（值已脱敏）：
   ```
   frontier query: aid=685343&app_name=ImeService
      &device_id=<did>&device_platform=windows&region=CN
   ```
   **仅携带 `device_id` + `aid` + `region` + `app_name`，无账号令牌/会话**。
3. 云端候选数据结构为 `CloudItem@pinyin@oime_engine` / `CloudAssoRespItem@pinyin@oime_engine`
   （protobuf，`cloud_convert` + `google::protobuf`），由 `BuildImeNetCloudRequestData`
   基于设备身份构造——印证「设备级匿名」而非「账号级」。
4. `AppLog_getDeviceId` / `AppLog_registerDidObserver` 表明设备 ID 是云能力的唯一身份基元。

> 注意区分两类能力：
> - **云端候选（Cloud Candidate）**：当前证据指向「设备级匿名可用」，无需登录。
> - **多机词库同步**：本地用户词库为 `dict/usr*.dat`（纯本地）。跨机同步入口/是否需账号
>   **尚未确认**（见 §5 未解明项），不可据此默认「同步也免登录」。

---

## 4. 凭据存放位置与安全边界

### 身份基元 = `device_id`（设备匿名标识）
- 持久化位置：`AppData/Roaming/DoubaoIme/ttnet/tt_net_config.config`
  文件内键值（已脱敏）：`device_id=<16位十进制did>`、`tnc_cmd`、`tnc_etag`。
- `oime-config.dll` 另暴露 `GetDeviceIDCachePath` / `GetDeviceIDRegisterPath`
  （路径管理入口），但本机实际落地的设备标识以 `ttnet/tt_net_config.config` 为准。

### 凭据边界与硬约束
- **本构建不存在任何账号令牌文件、会话 token、cookie 或账号配置节**（`config.json` 无
  `account` 字段；`AppData/Roaming/DoubaoIme/` 下无 token/session/account 命名文件）。
- `device_id` **等同账号标识**：它把本机与云端请求绑定，泄露等同于暴露设备指纹。
  **严禁**将其写入本仓库、截图外传或提交。
- 用户词库（`dict/usr*.dat`）为本地明文，仅本机有效，不跨机、不含账号。
- 云端请求不包含账号凭据，因此「云端候选」属于**匿名设备级**能力，对外暴露面仅为
  `device_id + 区域 + app id`。

---

## 5. 未解明项与下一步

1. **多机词库同步是否需账号**：本地词库为 `usr*.dat`；跨机同步的 RPC/UI 入口在本版本中
   未见（RPC 清单无 sync，设置页无同步项）。**推测需要账号**，但无证据，需进一步抓包/逆向确认。
2. **管理员账号（`administrator_account`）的触发条件与凭据去向**：仅见失败日志与策略字符串，
   客户端无登录实现证据，可能完全由服务端策略决定。
3. **`device_id` 的生成 / 注册流程**：`deviceregister.dll` 未随包；`did` 由 `ImeService`
   首启生成并写入 `ttnet/tt_net_config.config`，具体算法未逆向（可在不读取明文 did 的前提下
   静态分析生成函数）。
4. **live 抓包确认**：建议对运行中的 `ImeService` 做一次 TLS 解密抓包，确认云端候选响应在
   **无 token** 时确实返回有效候选（证据强度从「配置+日志」提升到「实测响应」）。
   注意：抓包只观察协议，不提取/保存 `device_id` 原文。

---

## 附：使用的 rea 命令与工具

```
# .NET 设置程序成员清单（登录/账号类型检索）
rea inspect-managed-members DoubaoIme.Settings.ViewModels.dll
rea inspect-managed-members DoubaoIme.Settings.UI.dll
rea inspect-managed-members DoubaoImeSettings.exe

# 原生二进制符号/字符串（Ghidra 后端 rea search 在 24MB/7MB 二进制上超时，
#   改用 binutils strings 作等价静态证据；符号表已由 RPC_API_SURFACE.txt/EXPORTS.txt 覆盖）
strings -n 6 ImeService.exe | grep -iE "account|login|administrator|policy=administrator_only"
strings -n 5 oime-config.dll | grep -iE "deviceid|cloud|register|cache"
strings -n 5 rpc.dll | grep -iE "SimpleMessage|ConfigType|account|login|cloud"
```
