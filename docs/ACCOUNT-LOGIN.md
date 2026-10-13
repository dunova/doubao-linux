# 豆包输入法账号登录入口定位（ImeService 内部，v0.9.0.0）

> 目标：在 `ImeService.exe`（`ime_net_sdk.dll` / `sscronet.dll`）内部定位「豆包账号登录」与
> 「多端词库同步」的真正入口；判定登录后 token 落盘位置、同步接口、是否扫码形态。
> 分析对象：`work/app/versions/v0.9.0.0/` 下全部 PE（重点 `ImeService.exe`、`ime_net_sdk.dll`、
> `sscronet.dll`、`audioeffect-mt.dll`、`DoubaoImeSettings.exe` 及 `DoubaoIme.Settings.*.dll`）。
> 约束：不抓取/外传任何 `did` / `device_id` / `token` 真实值；结论强度不超过证据强度。
> 配套文档：见 `ACCOUNT.md`（旧前提版，顶部已加「前提已变」横幅）。

---

## 0. 结论摘要（先说结论）

- **v0.9.0.0 的整包（含 ImeService）中，没有豆包消费端账号登录入口。** 全二进制跨文件检索
  `passport` / `login` / `oauth` / `signin` / `user_info` / `account_login` / `login_qr` /
  `qr_login` / `scan_login` / `access_token`（应用级）/ `account_id=`（应用级）/ `app_token=`（应用级）
  —— **全部命中为空**（仅 `sscronet.dll` 内有 Chromium 网络栈的通用库符号，见 §4）。
- ImeService 是**唯一有网络能力的云组件**（直接链接 Cronet `Cronet_Engine_*` 并自带 Rust
  `ime_net_sdk`），但其云端身份是**设备 + 应用级（`did` + `aid`）**，**不是账号级**。实测日志与
  `audioeffect-mt.dll` 的 `CronetFrontierClient` 日志格式完全吻合：
  `frontier config url: %s, did: %s, aid: %d` 与 `frontier query: aid=...&device_id=<did>&...`。
- 因此：**当前构建无法让 Daniel 用其豆包账号登录；其「账号级多机词库同步」在 0.9.0.0 不存在。**
  公开发布的「登录 → 个人词库/短语/偏好自动同步」对应的是 **0.9.1** 才补齐的能力（见 §8 关键提示）。

---

## 1. 方法与工具

```
# 跨二进制字符串检索（Ghidra 后端 rea search 在 24MB/9MB 二进制上超时，改用 binutils strings 等价静态证据）
strings -n 5 <pe> | grep -iE "<keyword>"
# 域名/URL 提取
strings -n 8 <pe> | grep -oE "https?://[a-zA-Z0-9./_%?=&~-]+" | sort -u
# .NET 设置程序成员清单（确认无登录页）
rea inspect-managed-members DoubaoIme.Settings.UI.dll
rea inspect-managed-members DoubaoImeSettings.exe
```
证据强度说明：以下「实测」= 静态字符串/符号/目录枚举直接确认；「推测」= 基于架构的合理推断，未运行时验证。

---

## 2. 网络能力分布（前提校准）

- `rpc.dll` 导入表仅 `ADVAPI32/KERNEL32/SHELL32/USER32/WTSAPI32/dbghelp`，**无 winhttp/wininet/
  ws2_32/crypt32** → 物理上无网络能力（团队实测确认）。当前桥接「直接加载 rpc.dll 取候选」因此
  碰不到云端，与「ImeService 是否含登录」是两回事（见 §8）。
- `ImeService.exe` 链接 `Cronet_Engine_*`（`Cronet_EngineParams_ttnet_params_set` /
  `enable_quic_set` / `storage_path_set` / `user_agent_set` / `opaque_data_store_add` 等）+
  自带 Rust `ime_net_sdk`（tokio 1.52.3 + reqwest 0.12.28 + quinn HTTP/3）→ **ImeService 才是云组件**。
- `audioeffect-mt.dll`（字节 SAMI 语音 SDK）内含 `CronetFrontierClient`（
  `sami_core/common_util/net/frontier/CronetFrontierClient.cpp`），是 frontier 云客户端封装。

---

## 3. 登录入口实体：未找到消费端登录（实测）

对全部 30+ 个 PE 做登录关键字跨文件检索，结果：

| 关键字 | 命中位置 | 性质 |
|---|---|---|
| `passport` / `oauth` / `signin` / `authorize` | 无 | — |
| `/login` / `login_qr` / `qr_login` / `scan_login` / `get_qrcode` / `account_login` | 无 | — |
| `user_info` / `/user/info` / `avatar` / `nickname` | 无 | — |
| `access_token:` / `&account_id=` / `&app_token=` / `AccountFetcherService` | 仅 `sscronet.dll` | Chromium/Cronet 网络栈**库级**通用符号（裸嵌入时通常不被业务调用） |
| `Cronet_FrontierConfig_access_token_set` | `audioeffect-mt.dll` + `sscronet.dll` | frontier 连接级令牌 setter（见 §4） |
| `administrator_account_query_failed` / `non_administrator_account` / `policy=administrator_only` | `ImeService.exe` | 企业**管理员策略**，非消费登录（见 `ACCOUNT.md` §1） |
| `QRCoder` 二维码 | 仅 `FeedbackQrCodeDialog` / `QrCodeDownloadDialog`（设置程序） | 反馈/下载二维码，**非登录扫码** |

**设置程序（.NET）无登录页**：`DoubaoIme.Settings.UI.dll` / `ViewModels.dll` / `DoubaoImeSettings.exe`
成员清单中，与账号相关的只有语音试用的闭包局部 `CurrentUser`（`<>c__DisplayClass15_0`）与
`EnableCloudCandidate` 开关；无 login/account/signin 类型或命令。

→ 结论（实测）：**v0.9.0.0 整包无豆包账号登录 UI / URL / 二维码 / RPC。**

---

## 4. `access_token` / `account_id` / `app_token` 的实质（实测 + 推测）

`sscronet.dll`（字节 Cronet，基于 Chromium net 栈）含：
```
 access_token:
 access_token is empty.
 &account_id=
 &app_token=
 AccountFetcherService
 Cronet_FrontierConfig_access_token_get / _set
 meta.StreamMeta.access_token
```
`audioeffect-mt.dll` 含 `Cronet_FrontierConfig_access_token_set` 与 SAMI 的 `CronetFrontierClient`，
其日志（与 fact #3 实测日志逐字一致）暴露了 frontier 的真实身份模型：
```
 [SAMICORE] frontier config url: %s, did: %s, aid: %d
 [SAMICORE] frontier query: %s        ← 即实测的 aid=685343&app_name=ImeService&device_id=<did>&device_platform=windows&region=CN
```
判读（实测 + 合理推测）：
- frontier 云身份 = **`device_id` + `aid`（应用 id）**，**设备 + 应用级**，**不含账号字段**。
- `Cronet_FrontierConfig_access_token_set` 注入的是 frontier 连接的**服务端下发令牌**（设备/应用级），
  不是豆包用户登录凭据；URL 查询串里也没有该 token。
- `AccountFetcherService` / `access_token` / `account_id` / `app_token` 是 Cronet 自带的 OAuth/账号
  基础设施符号，**裸嵌入时默认不挂载 AccountManager**，故不被 IME 业务调用（推测，未见调用证据）。
- ImeService 自身的 `Cronet_EngineParams_*` 只配置 TTNet / QUIC / storage / UA，**无登录鉴权调用**。

→ 结论（实测为主）：**这些 token 是设备/应用级 frontier 令牌与网络栈库符号，不是账号登录凭据。**

---

## 5. 凭证落地位置（实测）

- **唯一持久化身份 = `device_id`**，位于 `AppData/Roaming/DoubaoIme/ttnet/tt_net_config.config`
  （键值 `device_id=<16位did>`，另有 `tnc_cmd` / `tnc_etag`）。`device_id` 等同账号指纹，**严禁外传/提交**。
- 对 `AppData/Roaming/DoubaoIme/` 全目录枚举：除 `applog/session.db2`（**日志会话库，非鉴权**）外，
  **无任何 `token` / `session` / `account` / `login` / `credential` / `auth` 命名的账号令牌文件**。
- frontier `access_token` 为连接级 / 服务端下发，未发现落盘账号令牌文件。
- **无登录 → 无登录 token 文件**（逻辑必然，且目录枚举佐证）。

---

## 6. 同步走哪个接口（实测符号 + URL；请求体身份为推测）

云个性化 / 词库接口（URL 实测自 `ImeService.exe`）：
```
 https://speech.bytedance.com/api/v3/context/ime/user_words          ← 用户词（上传：UserWordsUploadResponse@server）
 https://speech.bytedance.com/api/v3/context/ime/modify_pair/v2       ← 修改对（UploadModifyPair RPC 目标：ModifyPairRpcResponse@server）
 https://speech.bytedance.com/api/v3/context/ime/ner                  ← 命名实体
 https://ime.doubao.com/api/v1/sdk/dns_analysis?domain=
 https://ime.doubao.com/api/v1/version/list
 frontier 网关：frontier-audio-ime-quic.doubao.com / frontier-audio-ime-ws.doubao.com
               ime-gw3.oceancloudapi.com / ime-igw.doubao.com
```
- `user_words` / `modify_pair` 即"个人词库/输入习惯上云"的接口；类型 `UserWordsUploadResponse`、
  `ModifyPairRpcResponse` 在 ImeService 符号表中**实测**存在，与 `rpc.dll` 的 `UploadModifyPair` 对应。
- 但请求身份由 frontier 决定 = **`did` + `aid`（设备级）**（推测：请求体/Header 携带 device_id，
  未见 account_id 绑定；未运行时抓包实测）。
- → **结论（实测+推测）**：0.9.0.0 的"云词库"是**单设备级**上云，**同一账号跨机同步所需的账号绑定参数在本版本不存在**。

---

## 7. 是否扫码形态（实测）

- 全包无 login QR / scan-to-login 字符串；`QRCoder.dll` 仅用于设置程序的**反馈二维码 / 下载二维码**。
- → 当前构建**没有"必须由人扫码"的登录环节**（因为根本无登录）。

---

## 8. 对 Daniel 需求的影响 + 关键架构提示（重要）

1. **事实**：0.9.0.0 无账号登录入口；云以设备+应用身份匿名可用；多机**账号级**同步所需登录在 0.9.0.0 不存在。
2. **架构澄清（建议上报 team-lead）**：team-lead 此前放弃 0.9.1 的理由是「桥接用 `rpc.dll`（无网卡），
   升 0.9.1 也只是换个无网卡」——但**账号登录发生在 `ImeService` 进程内部**，与「我们的候选桥接用 rpc.dll」
   是**两件事**：ImeService 本身在 Wine 下已常驻且联网。若 0.9.1 在 ImeService 内补齐了账号登录与同步，
   则**运行 0.9.1 的 ImeService 即可自行登录+同步**，不受候选桥接走 rpc.dll 的影响。因此 0.9.1 对
   "Daniel 账号级多机同步"**仍可能关键**，建议重新评估（前提是他接受对该版本重做 ABI 校对）。
3. 退路：若坚持 0.9.0.0，则只能拿到**设备级**云候选/云词（匿名、不跨账号），无法实现 Daniel 的
   账号级多机同步。

---

## 9. 未解明项与下一步

1. 上述接口请求体/Header 的真实身份字段（是否 account_id 绑定）——建议对运行中的 ImeService 做一次
   TLS 解密抓包，确认 `user_words`/`modify_pair` 是否携带账号标识（仅观测协议，不保存 `did`/token）。
2. 0.9.1 是否在 ImeService 内新增 passport/login 入口——需拿到 0.9.1 二进制后，用本报告的同一套
   `strings` + `rea inspect-managed-members` 流程复测（重点看是否新增 login/auth/user_info 符号与 URL）。
3. `Cronet_FrontierConfig_access_token` 的获取与刷新路径（服务端下发 vs 本地缓存）——当前仅确认其被
   `set`，未确认来源与落盘。
4. 管理员账号（`administrator_account`）的触发条件与凭据去向——见 `ACCOUNT.md` §5，本版本未实现客户端登录。

---

## 附：核心证据摘录

```
# ImeService 云端 URL（实测）
https://ime.doubao.com/api/v1/version/list
https://ime.doubao.com/api/v1/sdk/dns_analysis?domain=
https://speech.bytedance.com/api/v3/context/ime/user_words
https://speech.bytedance.com/api/v3/context/ime/modify_pair/v2
https://speech.bytedance.com/api/v3/context/ime/ner
frontier-audio-ime-quic.doubao.com/api/v1/ws ; ime-gw3.oceancloudapi.com ; ime-igw.doubao.com

# audioeffect-mt.dll（SAMI CronetFrontierClient）日志格式 = fact#3 实测日志
[SAMICORE] frontier config url: %s, did: %s, aid: %d
[SAMICORE] frontier query: %s

# sscronet.dll（库级，非业务调用）
 access_token: / access_token is empty. / &account_id= / &app_token= / AccountFetcherService
 Cronet_FrontierConfig_access_token_get / _set

# 跨二进制登录关键字检索结果：passport/login/oauth/signin/user_info/login_qr/qr_login/scan_login = 无（应用级）
```
