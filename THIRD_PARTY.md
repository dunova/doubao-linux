# 第三方组件与许可

本仓库的 MIT 许可**只覆盖**我们自己写的部分：安装脚本、文档、外观主题、合并工具。

它**不覆盖**豆包官方引擎、词库、设置程序、商标或云服务，也不覆盖任何上游项目——那些各有自己的许可与版权人。

本项目是非官方的互操作性实验，与字节跳动、豆包无隶属关系，未获其背书。用户需自备官方安装包（脚本代为从官方渠道下载并校验）。

---

## 上游代码

| 项目 | 用途 | 引用方式 | 许可 | 是否随本仓库分发 |
|---|---|---|---|---|
| [royess/doubao-ime-linux](https://github.com/royess/doubao-ime-linux) | Fcitx5 桥接、Wine RPC 宿主、官方引擎对接 | 安装时 `git clone` 并钉 commit | MIT | **否**，运行时拉取 |
| [quanru/doubao-say](https://github.com/quanru/doubao-say) | 语音输入应用（GTK4） | 安装时从其 GitHub Release 下载离线包 | MIT | **否**，运行时下载 |
| [wurong98/doubao-input-for-linux](https://github.com/wurong98/doubao-input-for-linux) | Doubao Say 的直接上游 | 经 Doubao Say 间接引入 | MIT（沿用上游） | 否 |
| [lilong7676/doubao-murmur](https://github.com/lilong7676/doubao-murmur) | 语音与登录组件的原始来源 | 经上述链条间接引入 | MIT，Copyright (c) 2026 lilong7676 | 否 |

### Doubao Say 的传承链说明

这条链容易搞错，所以单独写清楚（依据其 `NOTICE` 文件，2026-09 版本）：

1. `lilong7676/doubao-murmur` 是语音/登录组件的原始项目，MIT。
2. 该项目的 Linux 组件被导入 `wurong98/doubao-input-for-linux`，**导入时未保留原始 Git 历史**，因此提交记录上看不出源头。
3. `quanru/doubao-say` 基于 `wurong98/doubao-input-for-linux`（base commit `98ce357`）另起独立历史，重命名包名，并做了 Linux 资源路径适配。
4. 按源码比对，导入的版本对应 `doubao-murmur` 的 `50d16e0b`：七个核心 Python 模块在改名后完全一致，两个注入的 JavaScript 文件逐字节相同。

上游 README 里有一句"非商业使用"的免责声明，但 `LICENSE` 给出的是明确的 MIT 授权。本项目依据 `LICENSE` 的 MIT 条款使用继承代码。**软件许可不等于服务授权**——用不用豆包的服务，取决于你与字节跳动的条款，与本仓库无关。

---

## 构建与运行时依赖（均不随仓库分发）

| 依赖 | 用途 | 许可 |
|---|---|---|
| [Fcitx 5](https://github.com/fcitx/fcitx5) | 输入法框架与原生插件 API | LGPL-2.1+ |
| [Wine](https://gitlab.winehq.org/wine/wine) | 运行 Windows 键盘引擎 | LGPL-2.1+ |
| [Wine Mono 11.3.0](https://github.com/wine-mono/wine-mono/releases/tag/wine-mono-11.3.0) | 官方设置窗口的 .NET 运行时 | MIT / LGPL 混合 |
| [innoextract_win](https://github.com/UserUnknownFactor/innoextract_win) | 在 Linux 上解 Inno Setup 安装包 | zlib |
| [Noto CJK](https://github.com/notofonts/noto-cjk) | 设置窗口与候选栏中文字体 | SIL OFL 1.1 |
| [MinGW-w64](https://www.mingw-w64.org/) | 编译 Windows RPC 宿主 | 多种（GPL 例外条款） |
| GTK4 / WebKitGTK / PipeWire / PortAudio | 语音应用的 GUI 与录音 | LGPL / MIT |

装这些包时你系统里已有的许可文件继续有效，本仓库不做二次分发。

---

## 参考而未复制代码的项目

| 项目 | 参考了什么 | 说明 |
|---|---|---|
| [xdqi/rime-winime](https://github.com/xdqi/rime-winime) | Windows 引擎桥接的架构思路 | 未复制源码；本项目走豆包自己的 RPC 通道而非 IMM |
| [xifan2333/vinput-registry](https://github.com/xifan2333/vinput-registry)（Doubao streaming 适配器） | 可选外部 ASR 适配器的接口形态 | **未包含**其适配器源码、凭据或协议实现 |

关于 ASR 适配器：如果要用第三方适配器，请自行向其作者确认再分发许可。本项目只提供调用它的启动器，不为其代码重新授权；协议逆向研究归其上游贡献者。

---

## 不分发清单

明确**不**包含在本仓库、也不在安装脚本下载范围之外的东西：

- 豆包官方安装包（脚本从官方 CDN 下载，不转存）
- `rpc.dll`、`ImeService.exe` 及任何官方 EXE/DLL
- 官方词库、用户词频、账号数据
- 微软字体（设置窗口不依赖，也不需要）
- Wine 本体、Wine Mono 之外的任何运行库

若你制作二进制分发包，需自行评估上述依赖的许可义务，并保留各自的声明文件。
