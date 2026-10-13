# RPC 帧 / 候选可用性 结论报告（2026-10-13）

> 验收闸门：**从 `\\.\pipe\ObricIme\oime-server` 取回非空候选** —— 已通过（实测）。
> 结论分级：实测 / 二进制证据 / 推测。

## ① gle=123（ERROR_INVALID_NAME）是否无害？—— 实测：无害
- `t_seh.err` 的 `gle=123` 来自**孤儿后台连接线程**，不是 RPC 真实失败。
- 根因：原 host 调用 `CreateRpcClient(NULL)` 得到一个 client 指针，却把该指针传给
  `RpcPipe_*` 第一参数。第一参数被当成**地址 C 字符串**去 `strlen`（见②），
  后台线程读坏内存 → `CreateFile` 拿到野指针管道名 → `gle=123` → exit 5 / AV@0x140001d00。
- 删除 `CreateRpcClient`（对齐已知可用的 `bridge/keyboard_host.c`）后，stderr 不再出现
  任何 gle 警告，host 干净启动。证据：`fixed3.err` 为空，`fixed3.out` 完整 8 行。

## ② KeyDown / ABI 真实签名 —— 二进制证据
- 对 `rpc.dll` 0.9.0.0 反汇编：内部 helper `0x180014390` 对 `rcx` 做 `strlen` +
  `std::string::assign`，`rcx==NULL` 走空默认串。**结论：第一参数（rcx）是管道/地址
  C 字符串，文件头第一条注释“被忽略”是错的，第二条“是地址串”正确。**
- `RpcPipe_GetCandidateListUtf8 @0x1800198c0`：`rcx=endpoint, rdx=buf, r8=size,
  r9=*selected, rsi=*has_prev, rbx=*has_next` —— 与 host 的 `cands_t` typedef **逐位吻合**。
- `KeyDown @0x18001a010`：`rcx=endpoint, rdx=vk, r8=ts, r9=app`，host 签名一致。

## ③ 是否拿到非空候选（贴原文）—— 实测：拿到
驱动**我们修复后的 `doubao-rpc-host-fixed.exe`**（settings-prefix，`F/K78/K73/K72/K65/K79/C/Q`）：

`ni'hao` 取词（`fixed3.out` 末行，已精简长度）：
```json
{"candidates":["你好","👋","ヾ(=^▽^=)ノ","你号","拟好","泥嚎","你还","倪好","泥蒿","你","尼","呢","你哈",…],"selected":0,"has_prev":0,"has_next":1}
```
顶候选 `你好`。逐键 `preedit` 演进：`n → ni → ni'h → ni'ha → ni'hao`，每次 `result:1`、`candidates` 非空。
**HANDOFF §3.1 “需要 protobuf 序列化” 的猜测已实测推翻**——host ABI 与 rpc.dll 一致，无需自组帧。

## ④ 之前卡在哪一层 —— 已定位并解除
- 崩溃层：`CreateRpcClient` 孤儿 client 导致后台 RPC 线程 AV（EXIT=5）。已移除。
- 静默喂死层：原 `obuf/ojstr` JSON 构造器对**非 null 结尾**的候选/组合串调用
  `lstrlenA` → 越界写坏静态区 → 无限循环刷 `result:1`（EXIT=124）或随机崩（EXIT=1）。
  已改为有界直接 `WriteFile` 的 `jwrite/jquoted/jcands`（对齐 keyboard_host.c）。
- 编译层：`mingw` 必须**源文件在前、`-lkernel32 -luser32` 在后**，否则全符号未定义。
  正确旗标见 `build_windows.py:14-16`。

## ⑤ 证据路径
- 修复后宿主源码：`/home/dunova/src/doubao-linux/tools/doubao-rpc-host.c`
- 修复后二进制：`/mnt/nas/quantgo/outputs/doubao_ime_linux_20261013/doubao-rpc-host-fixed.exe`
- 完整候选证据：`.../fixed3.out`（8 行 JSON）、`fixed2.out`（含逐键演进）
- 崩溃/噪声证据：`t_seh.err`(gle=123)、`host.out`(EXIT=5/AV)、`diag1.out`(EXIT=124 刷屏)
- 二进制 ABI 证据：rpc.dll 反汇编 helper `0x180014390`、导出 `0x1800198c0`/`0x18001a010`
- 参考可用实现：`/home/dunova/src/doubao-ime-linux/bridge/keyboard_host.c`

## 结论（≤400 字版）
验收闸门通过：修复后的 `doubao-rpc-host-fixed.exe` 在 settings-prefix 下向官方
`\\.\pipe\ObricIme\oime-server` 发 `n-i-h-a-o` 五键，取回非空候选，顶候选 `你好`，
`preedit` 逐键从 `n` 演进到 `ni'hao`，stderr 无 gle=123 噪声，干净退出（EXIT=0）。
①gle=123 实测无害：源自被当字符串 strlen 的孤儿 client 指针导致后台连接线程崩溃，删除
`CreateRpcClient` 后消失。②ABI 二进制证据确证：`RpcPipe_*` 第一参数是管道地址 C 串
（helper 0x180014390 做 strlen+assign），`GetCandidateListUtf8` 签名与 host 完全一致。
③非空候选已实测拿到（原文见上）。④卡点已解除：崩溃=孤儿 client AV；静默喂死=原 JSON
构造器对未结尾候选串 lstrlenA 越界；编译=库须置于源之后。§3.1“需 protobuf 序列化”猜测
已推翻。证据路径见 §⑤。
