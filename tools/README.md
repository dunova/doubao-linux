# 研究工具

这些是理解与验证官方引擎 RPC 通道时用的工具，**不是安装流程的一部分**。
`./install.sh` 不依赖它们，删掉也不影响使用。

保留在这里是因为它们记录了这套方案是怎么摸出来的，对后续排障和继续逆向有用。

| 工具 | 用途 | 依赖 |
|---|---|---|
| `pipe_probe.c` | 探测命名管道 `\\.\pipe\ObricIme\oime-server` 是否可连 | MinGW-w64 |
| `doubao-rpc-probe.c` | 枚举可 `GetProcAddress` 的 `RpcPipe_*`，试调 `CreateRpcClient` | MinGW-w64 |
| `doubao-rpc-live.c` | 实测 RPC 活性（`EnsureServerRunning`），抓 protobuf 证据 | MinGW-w64 |
| `headless_nox.py` | 无 `DISPLAY` 时起私有 Xvfb 跑测试 | Python 3 |
| `doubao-imeservice` | `ImeService.exe` 常驻启动器的参考实现 | Wine |

## 编译

```bash
x86_64-w64-mingw32-gcc -O2 -o pipe_probe.exe tools/pipe_probe.c
x86_64-w64-mingw32-gcc -O2 -o doubao-rpc-probe.exe tools/doubao-rpc-probe.c
x86_64-w64-mingw32-gcc -O2 -o doubao-rpc-live.exe tools/doubao-rpc-live.c
```

编译产物需要放进私有 Wine prefix 才能调官方 DLL，具体路径见 `docs/ARCHITECTURE.md`。

## 关于 doubao-imeservice

上游的 `install.py` 已经会生成 `doubao-keyboard.service`，正常情况下用不着这个脚本。

它的价值在于单独拉起 `ImeService.exe`（官方主服务：云候选、账号、词库同步、语音 ASR）
而不启动键盘桥接，用于隔离排查——云候选不工作时，先确认是服务没起来还是桥接没连上。

关键设计点（脚本注释里也写了）：

- 用自己的 Xvfb，不占用你的 `DISPLAY`
- 直接用 `WINEPREFIX`，**不加 flock**，否则会挡住设置窗口
- 单例语义交给 `ImeService` 自己（重复启动会打印 `Server Already Exists.` 后退出）

## 实测结论存档

这些工具跑出来的结果记在：

- `docs/OFFICIAL-RPC.md` —— 24 个 RPC 方法全清单与反汇编签名
- `docs/PROTOCOL.md` —— 协议契约、14 个 protobuf 消息
- `docs/PERFORMANCE.md` —— 延迟与内存，以及两条被否掉的优化

## 注意

这些工具会读写私有 Wine prefix 里的官方二进制。它们**不修改**官方文件，
只是调用其导出函数。别用它们去做绕过授权的事。
