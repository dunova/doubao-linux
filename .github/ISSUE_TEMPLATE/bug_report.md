---
name: Bug 报告
about: 有东西不工作
title: '[bug] '
labels: bug
---

## 哪一部分

- [ ] 打字（候选不出、切不到引擎、字乱序）
- [ ] 语音（没反应、不出字、识别失败）
- [ ] 外观（候选栏样式、字体、缩放偏移）
- [ ] 安装 / 回退脚本本身
- [ ] 文档错误

## 现象

发生了什么，期望是什么。

## 复现步骤

1.
2.
3.

## 环境

安装脚本会自动收集大部分信息，贴 `./verify.sh` 的输出即可：

```
（粘贴 ./verify.sh 输出）
```

另外请补充：

- 发行版与版本：
- 桌面环境 / 合成器（Hyprland / GNOME / KDE / 其他）：
- 会话类型（Wayland / X11）：
- 会话缩放比例：
- doubao-linux 版本（`cat VERSION`）：

## 日志

```
（journalctl --user -u doubao-keyboard.service -n 50 --no-pager）
（或 journalctl --user -u doubao-say.service -n 50 --no-pager）
```

## 已尝试

看过 `docs/TROUBLESHOOTING.md` 的哪几条，结果如何。

---

**提交前请删除**：账号信息、API Key、`~/.config/doubao-say/` 下的任何文件内容、含个人输入的日志片段。
