#!/usr/bin/env bash
# doubao-linux · 只读依赖检查（不改动任何东西）
set -uo pipefail
C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_RST=$'\033[0m'
PKGS=(fcitx5 json-c cmake base-devel python wine xorg-server-xvfb mingw-w64-gcc boost)
PKGS_VOICE=(python-gobject opus libpulse)

echo "══ 系统 ══"
printf '  架构      : %s\n' "$(uname -m)"
printf '  发行版    : %s\n' "$( ( . /etc/os-release && echo "$PRETTY_NAME" ) 2>/dev/null )"
printf '  会话      : %s %s\n' "${XDG_SESSION_TYPE:-?}" "${XDG_CURRENT_DESKTOP:-}"
printf '  磁盘可用  : %s\n' "$(df -h "$HOME" | awk 'NR==2{print $4}')"

echo
echo "══ 依赖包 ══"
miss=0; dl=0
for p in "${PKGS[@]}" "${PKGS_VOICE[@]}"; do
  if v=$(pacman -Q "$p" 2>/dev/null); then
    printf '  %s✔%s %s\n' "$C_OK" "$C_RST" "$v"
  else
    printf '  %s✘%s %-22s 未安装\n' "$C_ERR" "$C_RST" "$p"
    sz=$(pacman -Si "$p" 2>/dev/null | awk -F': ' '/^下载大小/{print $2}')
    [[ -n "$sz" ]] && dl=$((dl+1))
    miss=$((miss+1))
  fi
done

echo
echo "══ 是否需要 sudo ══"
if (( miss )); then
  printf '  需要 --- 由 install.sh 调用 pacman，仅此一步需要 sudo\n'
else
  printf '  不需要 --- 依赖已齐备\n'
fi

echo
echo "══ 命令可用性 ══"
for t in wine Xvfb x86_64-w64-mingw32-gcc fcitx5-remote; do
  if c=$(command -v "$t" 2>/dev/null); then printf '  %s✔%s %-26s %s\n' "$C_OK" "$C_RST" "$t" "$c"
  else printf '  %s✘%s %-26s 缺失\n' "$C_ERR" "$C_RST" "$t"; fi
done

echo
if (( miss )); then
  printf '%s缺 %d 个包，可直接跑：sudo ./install.sh%s\n' "$C_WARN" "$miss" "$C_RST"
else
  printf '%s依赖齐备，可跑：sudo ./install.sh（或 ./install.sh --skip-deps）%s\n' "$C_OK" "$C_RST"
fi
