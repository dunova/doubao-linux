#!/usr/bin/env bash
# ==============================================================================
# doubao-linux · 一键安装
#
#   ./install.sh                  完整安装：打字 + 语音 + 外观
#   ./install.sh --dry-run        只打印将做什么，不改动系统
#   ./install.sh --check          只读检查依赖与状态
#   ./install.sh --skip-deps      跳过 pacman（依赖已就绪时）
#   ./install.sh --no-voice       不装语音，只装打字
#   ./install.sh --no-appearance  不套用豆包外观，保留你自己的主题
#   ./install.sh --only-appearance 只重套外观（打字/语音已装好时用）
#
# 需要 sudo 的只有 pacman 装系统包这一处，其余全部以当前用户身份完成。
# 任何写入前先备份并记账，回退见 ./rollback.sh。
# ==============================================================================
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT

# ── 钉住的版本（改动必须同步校验和，否则校验失败即中止）──────────────────────
# 打字：上游 Fcitx5 桥接
UPSTREAM_REPO="https://github.com/royess/doubao-ime-linux.git"
UPSTREAM_COMMIT="cfb2af9fb191e0c1528975490c91011b2ea2106b"   # 0.1.0-rc.2 + 本地清理 opt-in
ENGINE_VERSION="0.9.2.7"                                      # 官方 Windows 引擎版本

# 打字：官方 Windows 安装包（从官方 CDN 下载，不随仓库分发）
DOUBAO_EXE_URL="https://lf-wave.doubaocdn.com/obj/doubao-ime/app/windows/DoubaoIME_Installer_${ENGINE_VERSION}_release.exe"
DOUBAO_EXE_SHA256="d777027cc822a67dac04ba502616f6e6216a54c06681e21f8f45ef0a89cec5db"

# 打字：Wine Mono（官方设置窗口需要）
WINE_MONO_URL="https://github.com/wine-mono/wine-mono/releases/download/wine-mono-11.3.0/wine-mono-11.3.0-x86.msi"
WINE_MONO_SHA256="df2dfc1665c2511882e7cabd56eafd0c0a3d94e5a7e86f969277f6c189d418d3"

# 语音：上游 Doubao Say（MIT）。本仓库不复制其源码，只下载其官方离线包。
DOUBAO_SAY_REPO="quanru/doubao-say"
DOUBAO_SAY_TAG="v1.8.1"
DOUBAO_SAY_VERSION="1.8.1"
DOUBAO_SAY_SHA_311="02df72461dbe85a948ce08c178c74f6a2f67f1b1b5e376da30d443d6ab565251"
DOUBAO_SAY_SHA_312="8afdf8d53477c424d7cd958d34175a2d9e3ce9fafc55cf6b536f83d898fc0e59"
DOUBAO_SAY_SHA_313="48421304ebb6d62961bdaa2365319b394c5d43d2f521e0942a79fc3989192c99"
DOUBAO_SAY_SHA_314="fd3a591bbe516c9a5d5272135fc8455407569ca65ea535ea7bace9b0c7ed4f53"

# ── 路径 ────────────────────────────────────────────────────────────────────
SRC="${DOUBAO_SRC:-$HOME/src/doubao-ime-linux}"
INNO_SRC="$HOME/src/innoextract-src"
INNO_BUILD="$HOME/src/innoextract-build"
INNO_BIN="$INNO_BUILD/innoextract"

# ── 参数 ────────────────────────────────────────────────────────────────────
MODE="install"; SKIP_DEPS=0; WITH_VOICE=1; WITH_APPEARANCE=1
ONLY_APPEARANCE=0; CHECK_ONLY=0

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

for a in "$@"; do
  case "$a" in
    --dry-run)         MODE="dry-run" ;;
    --check)           CHECK_ONLY=1 ;;
    --skip-deps)       SKIP_DEPS=1 ;;
    --no-voice)        WITH_VOICE=0 ;;
    --no-appearance)   WITH_APPEARANCE=0 ;;
    --only-appearance) ONLY_APPEARANCE=1 ;;
    -h|--help)         usage; exit 0 ;;
    *) printf '未知参数: %s\n\n' "$a" >&2; usage; exit 2 ;;
  esac
done

# shellcheck source=scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"
# shellcheck source=scripts/10-deps.sh
source "$REPO_ROOT/scripts/10-deps.sh"
# shellcheck source=scripts/20-keyboard.sh
source "$REPO_ROOT/scripts/20-keyboard.sh"
# shellcheck source=scripts/30-voice.sh
source "$REPO_ROOT/scripts/30-voice.sh"
# shellcheck source=scripts/40-appearance.sh
source "$REPO_ROOT/scripts/40-appearance.sh"

detect_session
FONT_PATH=""

printf '%s%s%s  |  v%s  |  模式=%s  |  %s\n' \
  "$C_BOLD" "doubao-linux" "$C_RST" "$(cat "$REPO_ROOT/VERSION")" "$MODE" "$(date '+%F %T %z')"

# ── 前置检查 ────────────────────────────────────────────────────────────────
[[ "$(uname -s)" == "Linux" ]] || die "仅支持 Linux（当前 $(uname -s)）"
[[ "$(uname -m)" == "x86_64" ]] || die "目前仅支持 x86_64（当前 $(uname -m)）
 官方引擎是 x86 DLL，ARM 需要额外模拟层，本项目尚未覆盖。"
(( EUID != 0 )) || die "请以普通桌面用户运行，不要用 root/sudo 跑本脚本"

if (( ! ONLY_APPEARANCE )); then
  have fcitx5 || die "未找到 fcitx5。请先安装并确认输入法框架可用。"
  free_kb=$(df -Pk "$HOME" | awk 'NR==2{print $4}')
  (( free_kb > 6*1024*1024 )) || die "磁盘可用空间不足 6 GB（当前 $(awk -v k="$free_kb" 'BEGIN{printf "%.1f GB", k/1048576}')）"
  ok "x86_64 / $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") / fcitx5 / 磁盘 $(awk -v k="$free_kb" 'BEGIN{printf "%.0f GB", k/1048576}')"
  ok "会话: ${XDG_SESSION_TYPE:-未知} ${XDG_CURRENT_DESKTOP:-}"
  if [[ "$SESSION_KIND" == "wayland" ]]; then
    info "Wayland 会话：文字注入走 wl-clipboard / wtype，键盘部分为实测可用状态"
  fi
fi

if (( CHECK_ONLY )); then
  step "只读检查"
  MODE="dry-run"
  init_ledger
  check_font
  if (( WITH_VOICE )); then
    cp_ver="$(python3 -c 'import sys; print("cpython-%d%d" % sys.version_info[:2])' 2>/dev/null)"
    if [[ -n "$(voice_asset_sha "${cp_ver:-}")" ]]; then
      ok "语音运行时 $cp_ver 已支持"
    else
      warn "语音运行时 ${cp_ver:-未知} 无对应离线包，安装时需 --no-voice"
    fi
  fi
  info "检查完成，未改动任何文件。--check 不验证设备权限（那需要真实按键）"
  exit 0
fi

init_ledger

# ── 执行 ────────────────────────────────────────────────────────────────────
if (( ONLY_APPEARANCE )); then
  check_font
  install_appearance
else
  install_deps
  check_font
  install_keyboard
  if (( WITH_VOICE )); then
    install_voice
  else
    step "3/6 语音输入 · 已跳过（--no-voice）"
  fi
  if (( WITH_APPEARANCE )); then
    install_appearance
  else
    step "4/6 外观 · 已跳过（--no-appearance）"
  fi
fi

# ── 收尾 ────────────────────────────────────────────────────────────────────
step "5/6 设备权限自检"
if ! id -nG | tr ' ' '\n' | grep -qx input; then
  warn "当前用户不在 input 组：evdev 快捷键与 /dev/uinput 输入注入可能失败"
  warn "需要时执行（本脚本不会替你改）:"
  printf '    sudo usermod -aG input %s\n' "$(id -un)"
  warn "然后注销重新登录"
else
  ok "已在 input 组"
fi

step "6/6 完成"
cat <<EOF

  下一步：
    1. 重启输入法框架：systemctl --user restart fcitx5
    2. 按 Ctrl+Space 切到「豆包」，输入 nihao 验证候选
    3. 语音：聚焦文本框后按 Ctrl+;（默认快捷键），首次需登录豆包账号
    4. 端到端验证：./verify.sh

  变更台账：${LEDGER:-未创建}
  回退：    ./rollback.sh --dry-run   # 先看会做什么
            ./rollback.sh --apply
EOF
