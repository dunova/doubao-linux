# 安装说明

`README` 里的一键安装覆盖 Arch 系发行版。这篇补齐其他情况。

---

## 支持矩阵

| 项目 | 状态 |
|---|---|
| Arch / Omarchy / CachyOS / EndeavourOS | 一键安装（`./install.sh`） |
| 其他 systemd 发行版（Fedora / Debian / Ubuntu） | 需手动装包，然后 `./install.sh --skip-deps` |
| 非 systemd 发行版 | 需自行写服务管理，脚本不覆盖 |
| x86_64 | 支持 |
| aarch64 | 不支持（官方引擎是 x86 DLL） |
| 纯 TTY / 无图形会话 | 语音不可用；打字需手动起 Fcitx5 |

---

## 包名对照

### 打字

| Arch | Fedora | Debian / Ubuntu |
|---|---|---|
| `fcitx5` | `fcitx5` | `fcitx5` |
| `json-c` | `json-c-devel` | `libjson-c-dev` |
| `cmake` | `cmake` | `cmake` |
| `base-devel` | `gcc gcc-c++ make` | `build-essential` |
| `python` | `python3` | `python3` |
| `wine` | `wine` | `wine64` |
| `xorg-server-xvfb` | `xorg-x11-server-Xvfb` | `xvfb` |
| `mingw-w64-gcc` | `mingw64-gcc` | `gcc-mingw-w64-x86-64` |
| `boost` | `boost-devel` | `libboost-dev` |

### 语音

| Arch | Fedora | Debian / Ubuntu |
|---|---|---|
| `python-gobject` | `python3-gobject` | `python3-gi` |
| `python-cairo` | `python3-cairo` | `python3-cairo` |
| `gtk4` | `gtk4` | `libgtk-4-1` |
| `webkitgtk-6.0` | `webkitgtk6.0` | `libwebkitgtk-6.0-4` |
| `pipewire` | `pipewire` | `pipewire` |
| `portaudio` | `portaudio` | `libportaudio2` |
| `gtk4-layer-shell` | `gtk4-layer-shell` | `libgtk4-layer-shell0`（可能需自行编译） |
| `wl-clipboard` | `wl-clipboard` | `wl-clipboard` |

非 Arch 需要 Fcitx5 的开发头文件（`fcitx5-devel` / `libfcitx5core-dev`），否则插件编译不过。

---

## 手动流程（非 Arch）

```bash
# 1. 装上面表格里的包
# 2. 跳过自动装包
git clone https://github.com/dunova/doubao-linux.git
cd doubao-linux
./verify-deps.sh          # 会显示缺什么（pacman 不存在时会报错，属正常）
./install.sh --skip-deps --dry-run
./install.sh --skip-deps
```

`--skip-deps` 只跳过系统包安装，其余步骤（拉源码、构建、校验、部署）照常。

如果 `innoextract` 在你的发行版有现成包：

```bash
# 例如 Fedora
sudo dnf install innoextract
# 然后告诉脚本用系统的，别自己编译
export DOUBAO_INNOEXTRACT="$(command -v innoextract)"
```

---

## 设备权限

文字注入与全局快捷键需要读键盘事件，部分路径还需要写 `/dev/uinput`。

```bash
sudo usermod -aG input "$USER"
# 注销并重新登录（组变更对已有会话不生效）
```

验证：

```bash
id -nG | tr ' ' '\n' | grep -x input && echo "OK"
```

**不要**用 root 运行输入法本体。以 root 跑的 GUI 程序连不到你的会话总线，而且注入会带着 root 身份，得不偿失。

某些发行版的 `input` 组权限配置更严，可能需要额外的 udev 规则。若 `verify.sh` 报注入失败，先看 `docs/TROUBLESHOOTING.md`。

---

## 安装位置

| 内容 | 路径 | 是否可改 |
|---|---|---|
| 桥接源码 | `~/src/doubao-ime-linux` | 可，`DOUBAO_SRC=` |
| 官方引擎与 Wine prefix | `<源码目录>/work/` | 跟随源码目录 |
| 下载缓存 | `~/.cache/doubao-linux/downloads/` | 可，`DOUBAO_ART=` |
| 语音应用 | `~/.local/share/doubao-say/` | 上游决定 |
| 主题 | `~/.local/share/fcitx5/themes/` | 遵循 `XDG_DATA_HOME` |
| 配置 | `~/.config/fcitx5/`、`~/.config/doubao-say/` | 遵循 `XDG_CONFIG_HOME` |

源码目录**不要删**：启动器引用它，删了输入法就起不来。

---

## 卸载

```bash
./rollback.sh --dry-run
./rollback.sh --apply
```

系统包不会自动卸载。要清的话自己确认没有别的软件依赖：

```bash
sudo pacman -Rns wine xorg-server-xvfb mingw-w64-gcc boost
```

---

## 升级

```bash
cd doubao-linux
git pull
./install.sh            # 幂等：已装的会跳过，版本变了才重建
```

跨大版本升级前建议先 `./rollback.sh --snapshot`。
