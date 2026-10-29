# 参与贡献

## 这个仓库做什么、不做什么

**做**：把上游的桥接与语音组件编排成一条可复现、可回退、可验证的安装流程；维护外观层；钉定版本与校验和。

**不做**：重写拼音算法、改造官方二进制、打包分发官方引擎、逆向官方协议（那属于上游 `docs/OFFICIAL-RPC.md` 的研究范畴）。

所以写代码前先想清楚：这个改动属于「编排/外观/文档」，还是应该提到上游？

- 引擎候选质量、RPC 协议、Fcitx 插件本体 → 上游 [royess/doubao-ime-linux](https://github.com/royess/doubao-ime-linux)
- 语音识别、润色、录音 → 上游 [quanru/doubao-say](https://github.com/quanru/doubao-say)
- 安装流程、回退、外观、文档 → 本仓库

---

## 硬性约束

这几条不是风格偏好，是踩过坑之后的规矩：

### 1. 任何写入必须可逆

改动用户文件前先备份，并记入台账：

```bash
bak="$(backup_file "$target")"
ledger_add "merge-ini" "$target" "$bak" "说明"
```

`rollback.sh` 依赖台账做精确还原。绕过台账写文件，等于让回退失效。

### 2. 绝不整文件覆盖用户配置

用 `scripts/merge_conf.py` 做键级合并。整文件覆盖会抹掉用户手工调过的键。

### 3. 版本常量必须配校验和

改 `install.sh` 顶部的版本号时，同步更新 SHA-256。校验失败即中止，不做"尽力继续"——上游在**不改版本号的情况下换过安装包内容**，这个坑真实存在。

### 4. dry-run 必须覆盖所有写操作

新增任何写操作，都要走 `run()` 或显式判断 `MODE == "dry-run"`。

### 5. 不擅自 sudo、不改系统状态

只有装系统包那一处可以 sudo。不改用户组、不改默认输入法、不自动重启 Fcitx——这些由用户自己决定。

---

## 提交前自检

```bash
# 语法
for f in bootstrap.sh install.sh rollback.sh verify.sh verify-deps.sh scripts/*.sh; do bash -n "$f" || echo "FAIL $f"; done
python3 -m py_compile scripts/merge_conf.py

# 流程（不落盘）
./install.sh --dry-run

# 若要改合并逻辑，先用副本验证幂等
cp ~/.config/fcitx5/conf/classicui.conf /tmp/t.conf
python3 scripts/merge_conf.py ini /tmp/t.conf /tmp/patch.ini
python3 scripts/merge_conf.py ini /tmp/t.conf /tmp/patch.ini   # 第二次应输出"无需变更"
```

---

## 提交信息

用 Conventional Commits，正文中文：

```
feat(voice): 支持 Python 3.14 离线包
fix(appearance): 分数缩放下面板边距
docs(readme): 补充非 Arch 安装说明
chore(deps): 引擎升级到 0.9.2.7 并同步校验和
```

作用域常用：`keyboard`、`voice`、`appearance`、`install`、`rollback`、`docs`、`deps`。

---

## 提交 PR

1. 一个 PR 只做一件事
2. 说明**为什么**，而不只是改了什么
3. 涉及安装流程的改动，附 `--dry-run` 输出
4. 改版本钉定，附新校验和的来源（怎么算出来的）

---

## 不要提交的东西

`.gitignore` 已覆盖大部分，仍请自查：

- 任何 `~/.config/doubao-say/` 里的凭据、token、API Key
- 官方引擎文件（`*.exe`、`rpc.dll`、`work/`）
- 你的个人输入记录、日志
- `config.local.json`（含本机绝对路径）

---

## 许可

提交即表示你同意以 MIT 许可贡献这些代码。
