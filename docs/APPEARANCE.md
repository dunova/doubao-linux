# 外观

目标只有一个：**看起来像豆包**。候选栏紧凑、纯色、蓝色高亮，语音有波形反馈。

所有改动都是配置项，可逆。`./rollback.sh --apply` 会按台账逐条还原。

---

## 三个层次

### 1. 主题：候选栏长什么样

文件：`assets/themes/Doubao-Compact/theme.conf`
安装到：`~/.local/share/fcitx5/themes/Doubao-Compact/`

```ini
[InputPanel/Background]
Color=#2b2b2b          # 深灰不透明底
BorderColor=#1a1a1a
BorderWidth=1

[InputPanel]
HighlightColor=#0A84FF            # iOS 系统蓝
HighlightBackgroundColor=#0A84FF
PageButtonAlignment=Last Candidate
```

两个刻意的决定：

- **不用 SVG 背景**。SVG 在高 DPI 下会被拉伸模糊，纯色块不会。
- **`ScaleWithDPI=False`**。开着的话，2 倍屏上内边距会被放大到 8px，候选栏看着松散。这是我们踩过的坑。

### 2. 候选栏：怎么排列

文件：`~/.config/fcitx5/conf/classicui.conf`

```ini
Vertical Candidate List=False
```

豆包是横向候选。Fcitx5 默认纵向，这一项是关键。

```ini
PerScreenDPI=True
EnableFractionalScale=True
```

`EnableFractionalScale` 修的是真 bug：1.6 倍缩放（常见于 2.5K/4K 屏）下，候选窗口会偏离光标。根因是 classicui 走了 `wl_output.scale(2)`（整数），而不是 `wp_fractional_scale(1.6)`。开着它才会走分数缩放协议。

```ini
Font="PingFang SC 11"
MenuFont="PingFang SC 12"
```

字体由脚本**运行时探测**，优先级：

1. `PingFang SC`（苹方，豆包界面同款，需自行安装）
2. `Noto Sans CJK SC`（思源黑体，`noto-fonts-cjk` 自带）
3. `Source Han Sans SC` / `Sarasa Term SC` / `WenQuanYi Micro Hei`
4. 都没有 → `Sans Serif`，并给出警告

想用苹方：把 macOS 的 `PingFang.ttc` 放到 `~/.local/share/fonts/`，`fc-cache -fv`，再跑 `./install.sh --only-appearance`。

### 3. 候选词行为

文件：`~/.config/fcitx5/conf/pinyin.conf`

```ini
Prediction=True          # 下一词预测
PredictionSize=10        # 预测候选数
WordCandidateLimit=20    # 词组候选数
CloudPinyinEnabled=True  # 云拼音
```

注意：`CloudPinyinEnabled` 走的是 Google 的在线接口，不在豆包的链路上。介意的话设成 `False`，不影响其它功能。

### 4. 语音动效

文件：`~/.config/doubao-say/settings.json`

```json
{ "waveform_style": "bars", "reduced_motion": false }
```

| 值 | 效果 |
|---|---|
| `waveform_style: "bars"` | 柱状波形（豆包风格） |
| `waveform_style: "wave"` | 连续波形 |
| `reduced_motion: true` | 关闭动效，省电 / 晕动敏感 |

---

## 合并逻辑

`scripts/merge_conf.py` 做的是**键级合并**，不是文件覆盖。

| 情况 | 行为 |
|---|---|
| 键已存在、值不同 | 就地替换该行 |
| 键已存在、值相同 | 不动（幂等） |
| 键不存在 | 插到顶层区域末尾（第一个 `[section]` 之前） |
| 其他键 | **完全不动** |
| 注释行 | **完全保留** |
| 自定义节（如 `[Fuzzy]`） | **完全不动** |

改动前整文件备份到 `~/.cache/doubao-linux/backup/<时间戳>/`，并记入台账。

举例，你原本的 `classicui.conf` 里 `MenuFont="PingFang SC 12"` 不在我们的补丁范围内，它就不会被碰。

---

## 自定义

### 换高亮色

改 `~/.local/share/fcitx5/themes/Doubao-Compact/theme.conf`：

```ini
[InputPanel]
HighlightColor=#FF6B35
HighlightBackgroundColor=#FF6B35
[InputPanel/Highlight]
Color=#FF6B35
```

三处都要改，否则文字和底色会不一致。改完 `systemctl --user restart fcitx5`。

### 候选栏太大或太小

调 `theme.conf` 的 `[InputPanel/TextMargin]`，或改 `classicui.conf` 里的字号：

```ini
Font="Noto Sans CJK SC 13"
```

### 不想要外观

```bash
./install.sh --no-appearance     # 首次安装时跳过
./rollback.sh --apply            # 已经装了则回退
```

---

## 验证

```bash
./verify.sh          # 会检查主题文件与关键配置项
```

或手动看：

```bash
grep -E '^(Theme|DarkTheme|Font|Vertical)' ~/.config/fcitx5/conf/classicui.conf
ls ~/.local/share/fcitx5/themes/Doubao-Compact/
```
