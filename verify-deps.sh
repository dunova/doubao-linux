#!/usr/bin/env bash
# ==============================================================================
# doubao-linux · 只读依赖检查
#
# 不装包、不写文件、不启动服务。装之前想知道"会不会缺东西"就跑这个。
# ==============================================================================
set -uo pipefail

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'

PKGS_KEYBOARD=(fcitx5 json-c cmake base-devel python wine xorg-server-xvfb mingw-w64-gcc boost)
PKGS_VOICE=(python-gobject python-cairo gtk4 webkitgtk-6.0 pipewire portaudio)
PKGS_WAYLAND=(gtk4-layer-shell wl-clipboard)

echo "══ 系统 ══"
printf '  架构      : %s\n' "$(uname -m)"
printf '  发行版    : %s\n' "$( ( . /etc/os-release && echo "$PRETTY_NAME" ) 2>/dev/null )"
printf '  会话      : %s %s\n' "${XDG_SESSION_TYPE:-?}" "${XDG_CURRENT_DESKTOP:-}"
printf '  磁盘可用  : %s\n' "$(df -h "$HOME" | awk 'NR==2{print $4}')"

echo
echo "══ 运行时 ══"
if command -v python3 >/dev/null; then
  cpv="$(python3 -c 'import sys; print("cpython-%d%d" % sys.version_info[:2])' 2>/dev/null)"
  printf '  %s✔%s python3 %s（%s）\n' "$C_OK" "$C_RST" "$(python3 --version 2>&1 | awk '{print $2}')" "$cpv"
  case "$cpv" in
    cpython-311|cpython-312|cpython-313|cpython-314)
      printf '    %s·%s 语音离线包已支持该运行时\n' "$C_DIM" "$C_RST" ;;
    *)
      printf '    %s!%s 语音离线包不支持 %s，需 --no-voice 或换 Python 版本\n' "$C_WARN" "$C_RST" "$cpv" ;;
  esac
else
  printf '  %s✘%s python3 未安装\n' "$C_ERR" "$C_RST"
fi

if command -v fcitx5 >/dev/null; then
  printf '  %s✔%s fcitx5 %s\n' "$C_OK" "$C_RST" "$(fcitx5 --version 2>&1 | head -1)"
else
  printf '  %s✘%s fcitx5 未安装（这是硬依赖）\n' "$C_ERR" "$C_RST"
fi

echo
echo "══ 依赖包 ══"
miss=0

check_list() {
  local label="$1"; shift
  printf '  %s%s%s\n' "$C_DIM" "$label" "$C_RST"
  local p
  for p in "$@"; do
    if v=$(pacman -Q "$p" 2>/dev/null); then
      printf '    %s✔%s %s\n' "$C_OK" "$C_RST" "$v"
    else
      printf '    %s✘%s %-24s 未安装\n' "$C_ERR" "$C_RST" "$p"
      miss=$((miss+1))
    fi
  done
}

check_list "打字" "${PKGS_KEYBOARD[@]}"
check_list "语音" "${PKGS_VOICE[@]}"
if [[ -n "${WAYLAND_DISPLAY:-}" || "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  check_list "Wayland 补充" "${PKGS_WAYLAND[@]}"
fi

echo
echo "══ 群组 ══"
if id -nG | tr ' ' '\n' | grep -qx input; then
  printf '  %s✔%s 当前用户在 input 组\n' "$C_OK" "$C_RST"
else
  printf '  %s!%s 不在 input 组 —— evdev 快捷键与 /dev/uinput 注入会失败\n' "$C_WARN" "$C_RST"
  printf '    sudo usermod -aG input %s && 注销重登\n' "$(id -un)"
fi

echo
if (( miss == 0 )); then
  printf '%s依赖齐备，可以开始安装。%s\n' "$C_OK" "$C_RST"
else
  printf '%s缺少 %d 个包。%s运行 ./install.sh 会自动装（需 sudo）。\n' "$C_WARN" "$miss" "$C_RST"
fi
