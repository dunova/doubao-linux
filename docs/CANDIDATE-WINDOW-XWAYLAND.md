# 候选窗在 XWayland 应用（微信）中黑屏 —— 排查记录

**日期**：2026-10-13 · **状态**：根因已定位到机制层，修复方案待目视验收

---

## 1. 现象（用户报告）

| 项 | 内容 |
|---|---|
| 应用 | 微信（`/opt/wechat`，CEF 内核） |
| 现象 | 输入拼音时**候选窗内容区渲染为完全黑屏** |
| 关键澄清 | **不是「没弹出」**。候选**存在且有效**：按空格能输出默认选项，基础词能完整上屏 |
| 影响 | 输入功能可用，**仅候选窗不可读**（无法看词/选词） |

`ROADMAP.md` 明确「候选框继续由 Fcitx 绘制」，因此这是 **Fcitx5 classicui 的渲染问题**，不是豆包引擎问题。

---

## 2. 实测验证（本次用真实 GUI 驱动 + 截图完成）

本机 `wtype`(x86) / `grim` / `slurp` / `ydotool` **均已安装**（注：`HANDOFF.md` 中「ydotool 未安装」已过时）。

方法：启动受控终端 → **强制校验焦点在测试窗口后才打字**（防止误输入到其它应用）→ `wtype` 打 `nihao` →
`grim` **只截取测试窗口区域**（避免截取用户其它窗口内容）。

### 2.1 基线：Wayland 原生应用（foot）—— 渲染正常 ✅

`verify/candidate_after.png`：候选窗深色背景、白字、首候选蓝底高亮，
`1 你好  2 👋  3 ヾ(=^▽^=)ノ  4 你号  5 拟好  6 泥嚎  7 你还  8 倪好  9 泥蒿` 全部可读。

同时 `fcitx5-remote -n` → `doubao`，证明**整条豆包桥接链路是活的**。

### 2.2 A/B 对照：换主题能否复现 —— **不能，假设被证伪** ❌

原假设（本文件初稿）：`MacOS-Dark` 主题的候选窗背景是 SVG 位图（`Image=panel.svg` + `ScaleWithDPI=True`），
在 scale=1.6 下光栅化到非整数尺寸失败 → 未初始化表面 → 纯黑。

**实测推翻**：`verify/groupA_macos_dark.png` 与 `verify/candidate_after.png` **渲染完全一致、均正常**。
在 Wayland 原生应用下，`MacOS-Dark` 与 `default-dark` **都正常**。

⇒ **主题不是元凶**。配置已还原为原始 `MacOS-Dark`。

---

## 3. 根因方向（机制已定位，待最终确认）

### 3.1 关键配置差异

```
xwayland:force_zero_scaling = True      ← Hyprland
DP-3 scale = 1.6, 3840x2160
```

`force_zero_scaling = true` 让 **XWayland 应用运行在 1:1 未缩放坐标空间**，由合成器整体放大；
而 **Wayland 原生表面运行在 1.6 的逻辑空间**。

fcitx5 classicui 的候选窗是 **Wayland 原生 popup 表面**，但它需要**按焦点窗口（可能是 XWayland）的几何**来定位与决定缓冲尺寸。
两个坐标/缩放空间不一致时，缓冲尺寸与表面尺寸对不上 → 合成出**未初始化的黑缓冲**。

这解释了为什么：
- 候选**数据**完好（引擎侧正常，空格能选）
- 候选**画面**全黑（渲染侧缓冲错配）
- 只在**微信**出现（微信是 XWayland 应用；foot 是 Wayland 原生，故正常）

### 3.2 微信确实具备 Wayland 原生能力（二进制证据）

```
strings /opt/wechat/wechat | grep -i wayland
  libwayland-client.so.0
  libwayland-cursor.so.0
  libwayland-egl.so.1
  Wayland stub: dlopen(libwayland-client.so.0) failed: %s
```
微信为 **CEF 内核**，且 `/opt/wechat/wechat` **未强制**图形后端；
用户启动器 `/home/dunova/.local/bin/wechat` 只设 `XMODIFIERS=@im=fcitx`，**不指定后端**
⇒ 微信默认很可能走 XWayland。

---

## 4. 待验收的修复路径（**未改动现有启动器**）

现有启动器是用户调好的资产，**未做任何修改**。提供并行测试入口：

```bash
tools/wechat-wayland-test.sh
```

它用 `--ozone-platform=wayland` 让 CEF 走 Wayland 原生，从根上绕开 `force_zero_scaling`
的双坐标空间问题。**不动原 `wechat` 启动器**，验证有效后再决定是否合并。

备选（若 ozone 参数无效）：
- 临时 `xwayland:force_zero_scaling = false`（需 Daniel 确认，会改变所有 XWayland 应用的缩放表现）
- 换 `fcitx5-rs` / `kimpanel` 前端

---

## 5. 未确认项（诚实清单）

- ⬜ **微信当前实际走 XWayland 还是 Wayland 原生** —— 未实测（需启动微信，会打扰用户，留待验收时确认）
- ⬜ 修复方案**未做过微信内实测**，需 Daniel 目视
- ⬜ 是否**所有 XWayland 应用**都黑屏、还是仅微信 —— 未确认
