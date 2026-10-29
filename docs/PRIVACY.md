# 隐私

这份文档说明数据往哪里去。结论先行：**打字基本本地，语音必须上传**。

---

## 打字

### 留在本地

- 按键事件（`evdev` 读取）
- 预编辑缓冲区
- 候选词列表
- 你选了哪个候选（本地词频学习，存在私有 Wine prefix 里）

这些都不出本机。

### 可能上传

官方引擎 `ImeService.exe` 是完整的云服务客户端，**它会自己联网**：云候选、账号、词库同步。这是官方设计，不是本项目加的。

本项目没有改造它的网络行为——要拦就得动官方二进制，那既不可靠也不合规。如果你的威胁模型不接受这一点，就不要用这套方案，用 Rime 之类纯本地的输入法。

想观察它连了什么：

```bash
ss -tp | grep -i wine
```

### 关于云拼音

`pinyin.conf` 里的 `CloudPinyinEnabled=True` 走的是 Fcitx5 自带的云拼音，接的是 Google 的接口，**与豆包无关**。不想要就设 `False`：

```bash
# 编辑 ~/.config/fcitx5/conf/pinyin.conf
CloudPinyinEnabled=False
```

---

## 语音

语音**必然**上传——识别在云端做，本项目不打包本地 ASR 引擎。

| 数据 | 去向 | 何时 |
|---|---|---|
| 麦克风音频 | 豆包云（默认）或你配置的火山引擎账号 | 每次录音 |
| 识别出的文本 | 同上 | 同上 |
| 润色请求（可选） | 你配置的 OpenAI 兼容接口（如 DeepSeek） | 开启润色时 |

两个后端：

1. **豆包网页账号**（默认）—— 走豆包的 Web 协议，用你的登录态
2. **火山引擎 Seed ASR**（可选）—— 用你自己的 API Key，按其计费条款收费

### 润色

如果开了「润色」，识别文本和临时文本会发到你在设置里填的 endpoint。默认示例是 DeepSeek。这是第三方服务，适用它自己的条款。

关掉：设置里关闭润色，或

```bash
python3 -c "
import json,pathlib
p=pathlib.Path.home()/'.config/doubao-say/settings.json'
d=json.loads(p.read_text()); d['polish_enabled']=False
p.write_text(json.dumps(d,ensure_ascii=False,indent=2))
"
```

---

## 凭据存在哪

| 凭据 | 路径 | 权限 |
|---|---|---|
| 豆包登录态 | `~/.config/doubao-say/`（由上游管理） | 应为 600 |
| 火山引擎 API Key | 同上 | 应为 600 |
| 润色 API Key | `~/.config/doubao-say/polish_api_key` | 应为 600 |
| 账号数据（Wine 侧） | `<源码目录>/work/settings-prefix/` | 私有 prefix |

本仓库**不收集、不上传**任何凭据，也没有遥测。

```bash
chmod 600 ~/.config/doubao-say/*
```

---

## 本仓库自身的行为

| 行为 | 说明 |
|---|---|
| 安装时下载 | 官方 CDN（引擎）、GitHub（桥接源码、语音离线包、Wine Mono、innoextract） |
| 遥测 | **无** |
| 自动更新检查 | **无**（本仓库不检查更新） |
| 上游的更新检查 | Doubao Say 会向 GitHub 查最新 Release（最多每天一次），只缓存时间和 tag |

想彻底断开这项：

```bash
# 阻断 doubao-say 的出站，但不影响语音功能本身
# 注意：这会同时阻断语音，因为识别也要联网
```

实际上单独关掉更新检查没有配置项，上游按天轮询 GitHub releases 接口。它只发一个 GET，不带任何用户标识。

---

## 提交 issue 前

请删掉：

- `~/.config/doubao-say/` 下的任何文件内容（含凭据）
- 日志里你的实际输入内容
- `settings.json` 里的 key / token 字段
- `~/.config/doubao-say/polish_api_key`

`./verify.sh` 的输出不含凭据，可以直接贴。
