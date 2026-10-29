# 故障排查

按"现象"找，不按"组件"找。每条给出判断依据和下一步。

---

## 打字

### 切不到「豆包」，输入法列表里没有

```bash
grep -i doubao ~/.config/fcitx5/profile      # 引擎槽在不在
ls ~/.local/lib/fcitx5/doubaoime.so          # 插件在不在
fcitx5-diagnose 2>&1 | grep -i doubao        # Fcitx 认不认这个插件
```

- 插件在、profile 里没有 → 跑 `./install.sh --only-appearance` 不行，得跑 `./install.sh` 让它补注册；或手动在 `fcitx5-configtool` 里添加
- 插件不在 → 编译阶段失败了，看 `install.sh` 输出的最后几行
- 插件在但 Fcitx 不加载 → 检查 addon 描述里的 `Library=` 路径是否指向真实文件

### 能切过去，但打不出候选

九成是引擎侧没起来。

```bash
systemctl --user status doubao-keyboard.service
journalctl --user -u doubao-keyboard.service -n 50 --no-pager
```

看到 `ConnectionRefused` 通常是两种：

1. **Wine 宿主没起来**。检查 `Xvfb` 是否在跑：
   ```bash
   pgrep -a Xvfb
   ```
   没有就是 Xvfb 启动失败。看服务日志里 Xvfb 那几行。

2. **陈旧 socket**。上游测试脚本只检查 socket 文件是否存在，残留文件会让它连到已关闭的监听端：
   ```bash
   rm -f ~/src/doubao-ime-linux/work/keyboard-test.sock
   systemctl --user restart doubao-keyboard.service
   ```

### 打出来的字乱序或重复

按键往返变成异步了。先看延迟：

```bash
./verify.sh      # 会打印按键往返中位延迟
```

正常应在 2 ms 量级。如果是几十毫秒，说明 Wine 在忙别的事——常见于 `ImeService.exe` 正在做网络请求或崩溃重启。

```bash
systemctl --user status doubao-imeservice.service
```

### 服务反复重启

```bash
journalctl --user -u doubao-keyboard.service -n 100 --no-pager | grep -iE 'error|fail'
```

`Restart=on-failure` 会掩盖真实错误，日志里才有原因。

---

## 语音

### 按快捷键没反应

```bash
systemctl --user status doubao-say.service
pgrep -af doubao_input
```

- 服务没跑 → `systemctl --user restart doubao-say.service`
- 在跑但按键无响应 → 快捷键绑定没生效。打开 Doubao Say 的设置窗口，重新录一次快捷键
- 快捷键冲突 → 默认 `Ctrl+;`，有些编辑器占用了它

### 录到了但不出字

```bash
# Wayland
command -v wl-copy && command -v wtype
# X11
command -v xdotool && command -v xclip
```

缺工具会导致文字只进剪贴板、不自动粘贴。装上对应包即可：

```bash
sudo pacman -S --needed wl-clipboard      # Wayland
sudo pacman -S --needed xdotool xclip     # X11
```

### 识别很慢或一直转圈

看是不是网络到豆包云的问题：

```bash
journalctl --user -u doubao-say.service -n 50 --no-pager
```

日志里如果有 WebSocket 握手超时，检查代理。注意：**代理必须放行豆包的语音域名**，且要让 `doubao_input` 进程走代理（systemd 服务不继承你 shell 里的 `http_proxy`）。

### 双实例（两个托盘图标）

systemd 服务和 Doubao Say 设置里的「开机自启」同时开了。二选一：

```bash
# 推荐：统一用 systemd
systemctl --user enable --now doubao-say.service
# 然后在 Doubao Say 设置里关掉「开机自启」
```

### 麦克风选不到

```bash
wpctl status | grep -A5 Sources
```

在 Doubao Say 设置里选一个**正在工作**的输入设备。USB 麦克风重插后设备 ID 会变，需要重选。

---

## 外观

### 候选栏还是纵向

```bash
grep -i 'Vertical' ~/.config/fcitx5/conf/classicui.conf
```

应为 `Vertical Candidate List=False`。改了没生效 → 没重启 Fcitx5：

```bash
systemctl --user restart fcitx5
```

### 候选栏偏移、不贴光标

分数缩放环境（1.25 / 1.5 / 1.6 倍）下的经典问题。

```bash
grep -i Fractional ~/.config/fcitx5/conf/classicui.conf
```

应为 `EnableFractionalScale=True`。还不行就看合成器的缩放设置——有些合成器对 `wp_fractional_scale` 支持不完整。

### 中文显示成方块

字体缺失。

```bash
fc-list :lang=zh | head -5
sudo pacman -S --needed noto-fonts-cjk
fc-cache -fv
./install.sh --only-appearance
```

### 主题没生效

```bash
ls ~/.local/share/fcitx5/themes/Doubao-Compact/theme.conf
grep -E '^(Theme|DarkTheme)=' ~/.config/fcitx5/conf/classicui.conf
```

`Theme` 和 `DarkTheme` 都要指向 `Doubao-Compact`，且 `UseDarkTheme` 要和你实际用的主题模式一致。

---

## 通用

### 想彻底重来

```bash
./rollback.sh --apply
rm -rf ~/.cache/doubao-linux
rm -rf ~/src/doubao-ime-linux
./install.sh
```

### 收集诊断信息

提 issue 前请附：

```bash
./verify.sh 2>&1
./verify-deps.sh 2>&1
fcitx5-diagnose 2>&1 | head -80
systemctl --user status doubao-keyboard.service doubao-say.service --no-pager
```

**提交前请删掉**：账号信息、API Key、`~/.config/doubao-say/` 下的凭据文件、含个人输入的日志片段。
