# 实测数据

主机：Arch Linux (omarchy) · Hyprland / **Wayland** · Fcitx5 5.1.23 · x86_64 (i5-1135G7, 8 线程, 15 GB)
日期：2026-10-13 · 上游提交 `62117ce` · 豆包 Windows 引擎 `0.9.0.0` · Wine 11.19

---

## 1. 引擎可用性

| 检查 | 结果 |
|---|---|
| 组件级端到端测试（真实 broker + 真实官方引擎，非 mock） | **11/11 PASS** |
| `official preedit` | PASS（`ni'hao`） |
| **`official candidates include 你好`** | **PASS** ← 官方引擎确实返回候选 |
| `select first candidate` / `select candidate 1` | PASS |
| `partial candidate keeps remaining pinyin` / `complete partial conversion` | PASS |
| `Backspace updates composition` / `Escape clears composition` | PASS |
| `new focus drops previous composition` | PASS |
| `broker survives malformed client` | PASS |
| Fcitx5 侧 | `Loaded addon doubaoime`，`fcitx5-remote -s doubao` 成功 |

---

## 2. 按键延迟

测法：直连 broker 的 Unix socket，**每次命令新建连接**（与插件实际行为一致）。
语料：`nihao / woaini / jintiantianqi / wobuzhidao / zhongguo / beijingdaxue / renshengruomeng`

| 指标 | 值 |
|---|---|
| **单次按键事件** | **1.90 ms**（中位） |
| 一键往返（按下+松开 = 2 次连接） | 3.8 ms（min 2.5 / p90 7.0 / max 11.8，n=69） |

### 关键观察：成本由连接建立主导，不是引擎计算

轻命令 `F`（仅切换焦点）的中位耗时是 **3.9 ms** —— 与一次完整按键往返**基本相等**。
说明每次请求的固定成本（socket connect + Python broker 调度）几乎吃掉了全部耗时，
**官方引擎的候选计算本身可以忽略不计**。

**因此"持久连接替代每命令连接"是理论上唯一还有量级的优化点**，但：

> **本仓库不采用它。** 1.90 ms 已比另一条路线快 20–30 倍、且远低于人可感知阈值（约 50 ms）。
> 改造需要同时修改上游的 `bridge/keyboard_broker.py`（单连接多命令）与 `fcitx5/keyboard.cpp`（保持 fd），
> 风险大于收益。此处仅作为结论记录，供上游决定是否采纳。

---

## 3. 内存

| 口径 | 值 |
|---|---|
| cgroup `MemoryCurrent` | 392 MB（含页缓存，会误导） |
| **`memory.stat` anon（真实匿名内存）** | **334 MB** |
| `memory.stat` file（页缓存，可回收） | 43 MB |

进程级 RSS 分解：

| 组件 | RSS |
|---|---|
| `headless.py`（监督进程） | 16.8 MB |
| **`Xvfb`** | **35.3 MB** |
| `keyboard_broker.py` | 14.9 MB |
| `wineserver` | 15.9 MB |
| `services.exe` | 11.2 MB |
| `winedevice.exe` ×2 | 38.7 MB |

> **看内存不要看 `MemoryCurrent`**：它把 Wine prefix 的页缓存也算进去，
> 冷启动瞬间曾读到 555 MB，实际 anon 只有 334 MB。

---

## 4. 启动

服务启动到 `active`：**约 6 秒**（首次需初始化；后续每次登录都会经历一次）。

---

## 5. 被实测否掉的优化（写在这里，避免后人重做）

### 5.1 省掉 Xvfb —— **不可行**

`Xvfb` 占 35.3 MB，而 `bridge/keyboard_broker.py` **完全不引用 `DISPLAY`**，看起来可以省掉。

**实测结论：不行。** 无 `DISPLAY` 时 Wine host 无法启动，broker socket 根本不建立：

```
DOUBAO_NO_XVFB=1 python3 scripts/headless_nox.py --prefix keyboard -- python3 tests/integration_keyboard.py
  ConnectionRefusedError: [Errno 111] Connection refused
  （work/keyboard-host.log 只有 MESA-EGL 警告，未见候选回调）
```

`keyboard_broker.py` 自己不碰 X，但**它拉起的 Wine host 需要 X**（winex11 驱动 / 消息循环）。
→ **Xvfb 是硬依赖**，不要尝试移除。

### 5.2 `headless.py` 的监督进程（16.8 MB）

`headless.py` 自己是一个 Python 进程，为子进程管 Xvfb 生命周期。理论上可改为 `exec` 省掉这层，
但它承担 `flock` 前缀独占锁、信号转发、`wineserver -k -w` 清理 —— 省 16 MB 换掉这些保障不划算。

---

## 6. 复现方式

```bash
# 一键跑完上面 1–4 节
./verify.sh
```

原始证据（含完整输出）随本机留档，不随仓库分发。
