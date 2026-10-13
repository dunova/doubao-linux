# 0.9.1 / 0.9.2.7 追版报告（豆包输入法 Linux 桥接）

> 日期：2026-10-13 ｜ 执行人：general-purpose-2（前身 `account-engineer`，此前被 429 掐断未开始）
> 目标：判定「官方 release 通道的更新版本」是否新增**账号登录 / 多端词库同步**能力
> 背景：HANDOFF §1.2 判决「0.9.1 追版很可能是唯一解」。但实测官方通道当前只服务 **0.9.2.7**，`0.9.1` 已无法获取。本报告以 **0.9.2.7**（version_code 90207，严格更新于 0.9.1）作为分析对象，结论对「0.9.1+ 谱系」有效。

---

## 1. 安装包来源（实测）

| 项 | 值 |
|---|---|
| 版本清单端点 | `https://ime.doubao.com/api/v1/version/list` |
| 必填参数（逐一试错还原） | `channel=release` & `version_code=<非零int>` & `platform=Windows` |
| 最新版本 | **0.9.2.7**（version_code `90207`） |
| 安装包 URL | `https://lf-wave.doubaocdn.com/obj/doubao-ime/autoupdate/Windows/DoubaoIME_Update_0.9.2.7_release.imepkg` |
| 文件大小 | 264,221,038 字节 |
| sha256（**自算实测值，非官方提供**；响应 JSON 无 sha256/md5/signature 字段） | `81415eec5b3df586a3091a7962549809fd8893d490769dd5fff523687baac31c` |
| 0.9.1 可取性 | **不可得**：`DoubaoIME_Update_0.9.1.{0..5}_release.imepkg` 全部 HTTP 404；`history_version=true` 与 `false` 返回完全相同（仅 0.9.2.7 一条）。官方仅保留最新版。 |
| 备用官方主机 `ime-igw.doubao.com` | 未另行使用——`ime.doubao.com` 清单 + CDN 已成功取包，无需回退。 |
| changelog（弱阴性） | 仅提「深色模式」「语音设置页改版」，**未提**账号/登录/云同步。不能单独定论，须靠二进制比对。 |

`.imepkg` 是 **zip 归档**（非完整安装器），内含 `payload/`（完整 PE 集：ImeService.exe、rpc.dll、各 dll）+ `signed_manifest_holder.exe`。直接 `unzip` 即得完整二进制，无需运行安装器，**未触碰生产 prefix**。

---

## 2. 解包与方法对齐

- 解包位置：`/mnt/nas/quantgo/outputs/doubao_ime_linux_20261013/v091/unpacked/payload/`（**独立**，绝不触碰 `/home/dunova/src/doubao-ime-linux/work/wineprefix`）。
- 方法完全对齐基线（HANDOFF §1.3）：全 PE `strings` 检索 + `rea inspect-managed-members`，关键词 `passport / login / qr_login / user_info / oauth / signin / access_token / account_id / app_token / sync / user_words`。
- ⚠️ 方法修正：检索须用 **plain `strings`**（UTF-16 `-el` 对这批二进制会漏检，已踩坑修正）。

---

## 3. 关键词对比（0.9.0.0 基线 vs 0.9.2.7）

### 3.1 仍为零命中（两版相同，且是「设备/应用级」而非「账号级」）
- `passport` / `oauth` / `qr_login` / `signin`（页面级）/ `user_info`（账号）/ `account_login` / `passport_login` / `登录` / `扫码`：**两版均为 0 命中**。
- `&account_id=` / `&app_token=` / `Cronet_FrontierConfig_access_token_*`：**两版都在 `sscronet.dll` 中，逐字相同** → 属 TTNet/Cronet SDK 的**应用级**身份参数（等同 HANDOFF §1.3 的 device_id+aid），**不是用户账号登录**。这是基线「命中为零」未单列、但本次显式核对的「看似像账号、实为应用级」信号，已排除。

### 3.2 0.9.2.7 **新增**（0.9.0.0 全为 0 命中）——【二进制证据，强】
- `sync_user_dict` 命名空间（38 处）：`SyncUserDict / SyncUserDictEntry / SyncUserDictInfo / SyncUserDictPackage / SyncUserSideDictInfo / SyncPinyinUserWord / SyncPinyinUserBigram / SyncLocalDownloadInfo / SyncLocalUploadInfo / SyncUploadTaskControl …`
- **新增同步传输端点**：`/api/v2/sync/pull`、`/api/v2/sync/push`、`/api/v2/sync/version`、`/api/v2/stream/sync/upload`（0.9.0.0 这些**全为 0**，基线仅有的 `speech.bytedance.com/api/v3/context/ime/user_words` 在 0.9.2.7 仍保留）。
- **账号身份绑定（正是 HANDOFF §1.4 指出的「缺账号身份绑定」缺口）**：
  - `oime_engine::UserAccountInfoState::Set` / `SetUserDictPath`，携带 `user_id={} path={} is_sync_enabled={}`
  - `oime_engine::sync::SyncTaskManager::OnUserAccountChanged`、`SyncTaskManager account changed schedules sync`、`account disabled, cancel sync`
  - `oime_engine::pinyin::Engine::ClearUsrDictWhenSwitchAccount(bool)`（切换账号清用户词库 → 多账号感知）
- 源码路径线索：`oime_engine/src/other/sync/sync_usr_dict.cpp`、`oime_engine/src/common/usr_dict_base.cpp`、`oime_engine/src/pinyin/dict/usr_dict.cpp`

### 3.3 `rea inspect-managed-members`（DoubaoIme.Settings.ViewModels.dll）
未发现 `AccountViewModel` / `LoginViewModel` / `UserCenter` 等登录页 ViewModel；命中的 `syncContext` / `CurrentUser` 等为 WPF 框架通用符号（误报）。**设置 App 内亦无独立登录入口**。

---

## 4. rpc.dll 导出表 diff（基线 `EXPORTS.txt`）

| 维度 | 0.9.0.0 | 0.9.2.7 | 变化 |
|---|---|---|---|
| 具名导出 | 34（含 23 个 `RpcPipe_*`） | 49（含 34 个 `RpcPipe_*`） | +15 |
| C++ 修饰导出 | 7 | 11 | +4 |

**新增具名导出（全部 = 焦点/语音/撤销，与账号无关）**：
`RpcPipe_AckVoiceCommitAnnounce / CompleteSmartUndo / CompleteVoiceCommitEx / DeActivateEx / FocusInEx / FocusInExChecked / FocusOutEx / PeekSmartUndoCommand / PeekVoiceCommitExUtf8 / RegisterSmartUndo / RegisterTsfNotifySinkChecked` + `rpc::ClearFocusOwnerIfMatches / ClearStrictFinalOwner / FocusOwnerSupportsCapability / GetFocusOwnerSnapshot`。

- **带 `login/account/user/sync` 字样的 `RpcPipe_*`：新增为 0**（0927 全表 grep 这些词 = NONE）。
- 附带：`doubaoime-rpc-new.dll` 与 `rpc.dll` **二进制完全一致**（sha256 同为 `e3ee88527bf6bd38156e86b93413ca004a829809ad51f064a42db44814e9a5d5`），仅为冗余副本。

---

## 5. 交接文档 §1.5 开放问题（hybrid 分版本混跑）

**Q：0.9.2.7 同步下的用户词库落在哪个路径？**
- 落点由 `UserAccountInfoState::SetUserDictPath(user_id, path)` 在运行时按**账号作用域**设定，位于 `oime-config.dll` 的 `PathManager::GetCloudDir()` 之下（即 `AppData/Roaming/DoubaoIme` 的云端/用户数据目录）。
- 磁盘格式 = 引擎 `usr_dict` 的 **`.dat`** 用户词库文件（与出厂 `correct.dat / contact.dat / asr_user_correct_dict.dat / asr_user_ner_dict.dat / common_phrase_dict.dat` 等同族），由 `usr_dict.cpp` / `usr_dict_base.cpp` 读写。

**Q：0.9.0.0 引擎读得到吗？**
- **推测 / 中等证据**：`usr_dict` 引擎核心（`oime_engine`）两版同源，`.dat` 格式由引擎定义、跨小版本稳定；若 0.9.2.7 的同步把用户词写入 0.9.0.0 引擎读取的同一 user-dict 目录与格式，则**可读 → hybrid 可行**。
- **但**：`SetUserDictPath` 是账号作用域、运行时决定，可能指向 sync 专用子目录；能否与 0.9.0.0 引擎读取路径完全对齐，**静态分析无法 100% 确认**（证据不足到「确定可行」）。需实机运行 0.9.2.7 的 ImeService 观察落盘路径后再拍板。

---

## 6. 结论（严格分级）

**是否新增账号登录能力？**

- **账号身份绑定 + 多端词库同步子系统：是【二进制证据，强】**。0.9.2.7 新增 `sync_user_dict`（38 处）、`/api/v2/sync/{pull,push,version}` 传输端点、`UserAccountInfoState`（user_id + UserDictPath + is_sync_enabled）、`SyncTaskManager::OnUserAccountChanged`——这恰好补上了 HANDOFF §1.4 判定的「缺账号身份绑定」缺口。→ **「0.9.1+ 追版带来账号身份绑定从而解锁云端词库同步」这一假设，得到强二进制证据支持。**
- **独立可交互登录入口（passport/oauth/扫码/登录页）：证据不足【静态分析局限】**。两版静态字符串均无独立登录 UI；账号身份如何被填充（独立登录流程 vs 复用字节系已有登录态）无法从二进制静态分析确认。
- **候选桥接的 rpc.dll：否【二进制证据，强】**。rpc.dll 导出表变化全是焦点/语音/撤销，无任何 login/account/sync 方法——与 HANDOFF §1.2「登录发生在 ImeService.exe 内部，与候选加载哪个 rpc.dll 独立」一致。

**综合判定**：追 0.9.2.7（= 0.9.1 谱系最新）**确有账号/同步子系统新增（是，强证据）**；但**完整独立登录 UI 证据不足**。**hybrid 方案的前提（账号绑定+同步）在 0.9.2.7 已成立**，仅剩「0.9.0.0 引擎能否读 0.9.2.7 落盘词库」待实机确认（推测可行/中等）。

---

## 7. 铁律合规 & 回退

- 全程**只读取证**，无任何系统级/破坏性变更；三个服务（`doubao-keyboard` / `doubao-imeservice` / `omarchy-fcitx5`）未重启；未安装任何系统包；未污染生产 prefix。
- 临时产物**全部**在 `outputs/doubao_ime_linux_20261013/v091/`，未放 `/tmp`。
- 真实 device_id / token：**一律未出现在任何产出与 git**（本报告不涉及）。
- 回退：本任务无系统变更，唯一产物为 v091 证据目录与本次 git 提交。幂等清理脚本 `rollback_v091_20261013.sh`（用 `mv` 移到 trash，**非 `rm -rf`**，支持 `--dry-run`）。

---

## 8. 证据绝对路径

- 安装包：`/mnt/nas/quantgo/outputs/doubao_ime_linux_20261013/v091/DoubaoIME_Update_0.9.2.7_release.imepkg`
- 版本清单响应：`.../v091/version_list.json`、`.../v091/version_list_90207.json`
- 解包 PE：`.../v091/unpacked/payload/`（ImeService.exe、rpc.dll、oime-config.dll …）
- 导出 diff：`.../v091/rpc0900_named.txt`、`.../v091/rpc0927_named.txt`、`.../v091/rpc0900_cpp.txt`、`.../v091/rpc0927_cpp.txt`、`.../v091/rpc_exports.diff`
- 关键词命中：`.../v091/ime0900_login.txt`、`.../v091/ime0927_login.txt`（comm 差异）
- 基线导出表：`/mnt/nas/quantgo/outputs/doubao_ime_linux_20261013/EXPORTS.txt`
- 基线 0.9.0.0 PE：`/home/dunova/src/doubao-ime-linux/work/app/versions/v0.9.0.0/`
