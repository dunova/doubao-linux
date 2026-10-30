# 技术交底：豆包输入法重启后「引擎未就绪」故障根因定位与 0.9.2.7 全面升级闭环

- **日期**：2026-10-30
- **模块**：`doubao-ime-linux` / `doubao-linux` (Fcitx 5 桥接与 Wine 运行环境)
- **责任主体**：Antigravity Agent

---

## 一、背景与目标

用户在系统重启后发现桌面中文输入法完全失效，仅豆包语音输入可用；切换到豆包键盘模块时，Fcitx 5 候选框弹出提示：**「豆包引擎未就绪」**。
目标：查明重启失效的确凿物理根因，全面完成官方引擎 `0.9.2.7` 与 Fcitx 5 桥接插件的升级闭环，彻底恢复桌面键盘中文输入能力。

---

## 二、根因剖析与确凿证据

### 1. 故障发生机理（时间线与链路还原）
1. 在上一轮会话中，本地仓库 `doubao-ime-linux` 快进同步合并了最新上游分支 `origin/main`（`cfb2af9`，对应 `v0.1.0-rc.2`），该版本的代码逻辑已全面推进至官方 Windows 引擎 **`0.9.2.7`**；
2. 系统重启时，`systemd --user` 自动启动 `doubao-keyboard.service`，调起 `bridge/keyboard_broker.py`；
3. `keyboard_broker.py` 开机初始化时无条件向 Wine 注册表写入最新版本路径：
   ```text
   reg add HKCU\SOFTWARE\DoubaoIme /v VersionDir /t REG_SZ /d C:\DoubaoIme\versions\v0.9.2.7 /f
   ```
4. 然而当时系统磁盘的 Wine Prefix（`work/wineprefix`）中**尚未解包放置 0.9.2.7 官方安装包，仅有旧版 `v0.9.0.0`**；
5. `keyboard-host.exe` 启动并调用 `rpc.dll` 的 `RpcPipe_EnsureServerRunning()` 时，`rpc.dll` 循注册表 `VersionDir` 查找 `C:\DoubaoIme\versions\v0.9.2.7\ImeService.exe`，发现路径不存在，后台引擎拉起失败；
6. 后续用户每一次击键，`RpcPipe_KeyDown` 均返回 `-1`；
7. `fcitx5/keyboard.cpp` 在接收到 `r.result < 0` 时抛出异常：
   ```cpp
   // fcitx5/keyboard.cpp:74
   if(r.result<0) throw std::runtime_error("Engine rejected request");
   // fcitx5/keyboard.cpp:217
   ic->inputPanel().setAuxUp(fcitx::Text("豆包引擎未就绪"));
   ```
   从而在输入框处直接报出“豆包引擎未就绪”并拒绝落字。

### 2. 伴随缺陷：常驻启动器 glob 展开失效
常驻后台服务 `doubao-imeservice`（`/home/dunova/.local/bin/doubao-imeservice`）中配置：
```bash
LATEST_VER_DIR="$(ls -d "$STATE/app/versions/v*" 2>/dev/null | sort -V | tail -1)"
```
由于双引号包裹了通配符 `*`，bash 将其当作字面量处理导致匹配失败，`LATEST_VER_DIR` 为空，输出日志 `[imeservice] 找不到 /ImeService.exe` 并频繁异常重启。

---

## 三、变更清单（Diff 对比）

### 1. 官方安装包下载与校验
- 从官方 CDN 获取 `DoubaoIME_Installer_0.9.2.7_release.exe`，校验 SHA-256：
  `d777027cc822a67dac04ba502616f6e6216a54c06681e21f8f45ef0a89cec5db`（确凿吻合）；
- 获取 Wine Mono 11.3.0 MSI，校验 SHA-256：
  `df2dfc1665c2511882e7cabd56eafd0c0a3d94e5a7e86f969277f6c189d418d3`（确凿吻合）。

### 2. 依赖解包与二进制更新
- 解包产物同步至：
  - `/home/dunova/src/doubao-ime-linux/work/app/versions/v0.9.2.7/`
  - `/home/dunova/src/doubao-ime-linux/work/wineprefix/drive_c/DoubaoIme/versions/v0.9.2.7/`
  - `/home/dunova/src/doubao-ime-linux/work/settings-prefix/drive_c/DoubaoIme/versions/v0.9.2.7/`
- 校验核心 RPC DLL：
  `work/app/versions/v0.9.2.7/rpc.dll` SHA-256 为 `e3ee88527bf6bd38156e86b93413ca004a829809ad51f064a42db44814e9a5d5`。

### 3. 代码重新编译与插件安装
- 编译 Windows RPC 宿主：`python3 scripts/build_windows.py`，生成最新 `build/keyboard-host.exe`；
- 编译 Fcitx 5 原生插件：`cmake -S . -B build/fcitx -DCMAKE_BUILD_TYPE=Release && cmake --build build/fcitx -j$(nproc)`；
- 部署动态库：安装至 `~/.local/lib/fcitx5/doubaoime.so`。

### 4. 修复 `/home/dunova/.local/bin/doubao-imeservice`
```diff
--- a/home/dunova/.local/bin/doubao-imeservice
+++ b/home/dunova/.local/bin/doubao-imeservice
@@ -21,3 +21,3 @@
 PREFIX="$STATE/settings-prefix"
-IME_EXE="${DOUBAO_IME_SERVICE:-$STATE/app/versions/v0.9.0.0/ImeService.exe}"
+LATEST_VER_DIR="$(ls -d "${STATE}/app/versions"/v* 2>/dev/null | sort -V | tail -1)"
+IME_EXE="${DOUBAO_IME_SERVICE:-${LATEST_VER_DIR}/ImeService.exe}"
```

---

## 四、实测验证记录

1. **环境巡检（`doctor.py`）**：
   ```json
   {
     "core_ready": true,
     "core": {
       "wine": true, "wineserver": true, "xvfb": true,
       "mingw_cc": true, "innoextract": true, "fcitx_addon": true,
       "windows_host": true, "keyboard_engine": true
     }
   }
   ```
2. **端到端集成测试（`integration_keyboard.py`）**：
   - 全部 11 项用例 100% 通过（`PASS official candidates include 你好`、`PASS select first candidate` 等）。
3. **单元回归测试**：
   - `Ran 65 tests in 0.741s -> OK`。
4. **底层 Unix Socket 直连击键测验**：
   - 输入 `nihao` -> 第一候选输出 **「你好」**
   - 输入 `ceshi` -> 第一候选输出 **「测试」**
   - 输入 `zhongwen` -> 第一候选输出 **「中文」**
   - 输入 `doubao` -> 第一候选输出 **「豆包」**
5. **服务健康与进程状态**：
   - `doubao-keyboard.service`：**active (running)**，`ImeService.exe (0.9.2.7)` 与 `keyboard-host.exe` 存活且正常交互；
   - `doubao-imeservice.service`：**active (running)**；
   - `doubao-say.service`：**active (running)**；
   - Fcitx 5：平滑热重启加载 `doubaoime` 插件，当前活动输入引擎锁定 `doubao`。

---

## 五、回退方案（Rollback）

若后续需要紧急回退至 0.9.0.0 旧态，可直接单行复制执行以下命令：

```bash
systemctl --user stop doubao-keyboard.service && WINEPREFIX=/home/dunova/src/doubao-ime-linux/work/wineprefix wine reg add 'HKCU\SOFTWARE\DoubaoIme' /v VersionDir /t REG_SZ /d 'C:\DoubaoIme\versions\v0.9.0.0' /f && systemctl --user start doubao-keyboard.service && fcitx5 -r -d
```

---

## 六、脱亚入欧高精短语纠偏与用户词库接入（2026-10-30 追加）

### 1. 现象与根因剖析
- **现象**：用户在豆包键盘输入法中键入全拼 `tuoyaruou` 时，系统第一候选项固定为生僻组合字「拖亚茹偶」，未能命中「脱亚入欧」。
- **根因确认（L1 确凿证据）**：
  1. 官方 `v0.9.2.7` 提取的 137MB 离线词库（`c48352298dbd` 等）内，通过二进制全盘扫描 UTF-8 / UTF-16LE 确认**压根未收录「脱亚入欧」该 4 字词**；
  2. 离线引擎根据贪心拼音统计算法，将 `tuo-ya-ru-ou` 拆解为 `拖`、`亚`、`茹`、`偶` 四个单字高频组合；
  3. Fcitx5 与 Broker 原仅做直通透传，缺乏成语纠偏与用户词库热加载能力。

### 2. 变更清单（Diff）
- **修改文件**：`src/doubao-ime-linux/bridge/keyboard_broker.py`
  - 新增 `CUSTOM_PHRASE_PATH = ~/.config/doubao-ime/custom_phrase.txt` 动态热加载；
  - 内置 `tuoyaruou`、`tyro` 映射为「脱亚入欧」，`tuyarugou` 映射为「涂鸦入钩」；
  - 拦截候选词列表注入，命中时将高精纠偏词置顶至第 0 位；
  - 拦截选择请求 `S 0`，当选中注入短语时直接返回 `commit: phrase` 并发 `R` 重置底层拼音，实现瞬时上屏。
- **配置文件落盘**：`~/.config/doubao-ime/custom_phrase.txt` 允许用户自由追加自定义词条。

### 3. 实测验证记录
- **全拼测试**：
  - 输入：`tuoyaruou`
  - 第一候选项：`脱亚入欧`
  - 按空格/数字1（`S 0`）：直接上屏 **「脱亚入欧」**
- **缩写测试**：
  - 输入：`tyro`
  - 第一候选项：`脱亚入欧`
  - 按空格/数字1（`S 0`）：直接上屏 **「脱亚入欧」**
- **涂鸦入钩测试**：
  - 输入：`tuyarugou`
  - 第一候选项：`涂鸦入钩`
- **全套 16 项门禁复测**：`bash verify.sh` 输出 `全部通过：16 项`，Exit Code: 0。
