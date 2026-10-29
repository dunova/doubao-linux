#!/usr/bin/env bash
# ==============================================================================
# doubao-linux · 公共函数库
#
# 被 install.sh 与 scripts/ 下各阶段共享。约定：
#   * 所有函数以当前用户身份运行，绝不自行 sudo
#   * 任何写入前先备份，并把「动作 / 原路径 / 备份路径」记进 ledger
#   * MODE=dry-run 时只打印，不落盘
# ==============================================================================

# ── 颜色（非 TTY 时自动关闭）────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
  C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RST=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''; C_BOLD=''; C_RST=''
fi

step() { printf '\n%s══ %s ══%s\n' "$C_DIM" "$*" "$C_RST"; }
ok()   { printf '  %s✔%s %s\n' "$C_OK" "$C_RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_RST" "$*"; }
info() { printf '  %s·%s %s\n' "$C_DIM" "$C_RST" "$*"; }
die()  { printf '  %s✘%s %s\n' "$C_ERR" "$C_RST" "$*" >&2; exit 1; }

# run —— dry-run 感知的命令执行。用数组传参，避免 eval 注入。
run() {
  if [[ "${MODE:-install}" == "dry-run" ]]; then
    printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RST" "$*"
    return 0
  fi
  "$@"
}

# ── 路径 ────────────────────────────────────────────────────────────────────
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"

STATE_ROOT="${DOUBAO_ART:-$XDG_CACHE_HOME/doubao-linux}"
LEDGER_DIR="$STATE_ROOT/ledger"
BACKUP_ROOT="$STATE_ROOT/backup"
FCITX_THEME_DIR="$XDG_DATA_HOME/fcitx5/themes"
FCITX_CONF_DIR="$XDG_CONFIG_HOME/fcitx5/conf"

# 本次运行的 ledger；init_ledger 由 install.sh 调用
LEDGER=""

init_ledger() {
  local stamp; stamp="$(date '+%Y%m%d-%H%M%S')"
  LEDGER="$LEDGER_DIR/$stamp"
  if [[ "${MODE:-install}" == "dry-run" ]]; then
    printf '  %s[dry-run]%s 将创建 ledger %s\n' "$C_DIM" "$C_RST" "$LEDGER"
    return 0
  fi
  mkdir -p "$LEDGER" "$BACKUP_ROOT" || die "无法创建 $LEDGER"
  : > "$LEDGER/manifest.tsv"
  printf '# timestamp\t%s\n# host\t%s\n# version\t%s\n' \
    "$stamp" "$(hostname)" "$(cat "$REPO_ROOT/VERSION" 2>/dev/null || echo unknown)" > "$LEDGER/meta.tsv"
  ok "变更台账: $LEDGER"
}

# ledger_add 动作 原路径 备份路径 [备注]
ledger_add() {
  local action="$1" target="$2" backup="${3:--}" note="${4:--}"
  [[ -z "$LEDGER" ]] && return 0
  [[ "${MODE:-install}" == "dry-run" ]] && return 0
  printf '%s\t%s\t%s\t%s\n' "$action" "$target" "$backup" "$note" >> "$LEDGER/manifest.tsv"
}

# backup_file 路径 —— 备份到 BACKUP_ROOT/<stamp>/ 并返回备份路径
# 用 cp -a 保持权限与时间戳；失败即中止（备份不成不许继续动）
backup_file() {
  local src="$1"
  [[ -e "$src" || -L "$src" ]] || return 0
  if [[ "${MODE:-install}" == "dry-run" ]]; then
    printf '  %s[dry-run]%s 备份 %s\n' "$C_DIM" "$C_RST" "$src"
    printf '%s' "-"
    return 0
  fi
  local stamp; stamp="$(basename "${LEDGER:-$BACKUP_ROOT/manual}")"
  local dst="$BACKUP_ROOT/$stamp/${src#/}"
  mkdir -p "$(dirname "$dst")" || die "无法创建备份目录 $(dirname "$dst")"
  cp -a "$src" "$dst" || die "备份失败: $src"
  printf '%s' "$dst"
}

# have <cmd> —— 命令是否存在
have() { command -v "$1" >/dev/null 2>&1; }

# pkg_installed <pacman 包名>
pkg_installed() { pacman -Q "$1" >/dev/null 2>&1; }

# dl_verified <url> <sha256> <输出路径> <名称>
# 已存在且校验通过则跳过；下载到 .part 再原子改名，绝不半截文件落到目标名
dl_verified() {
  local url="$1" sha="$2" out="$3" name="$4"
  if [[ -f "$out" && "$(sha256sum "$out" | cut -d' ' -f1)" == "$sha" ]]; then
    ok "$name 已存在且校验通过"
    return 0
  fi
  if [[ "${MODE:-install}" == "dry-run" ]]; then
    printf '  %s[dry-run]%s 下载 %s\n' "$C_DIM" "$C_RST" "$name"
    return 0
  fi
  mkdir -p "$(dirname "$out")"
  curl -fL --retry 3 --connect-timeout 15 -o "$out.part" "$url" 2>/dev/null \
    || { rm -f "$out.part"; die "$name 下载失败（网络或上游不可达）"; }
  local got; got="$(sha256sum "$out.part" | cut -d' ' -f1)"
  if [[ "$got" != "$sha" ]]; then
    rm -f "$out.part"
    die "$name SHA-256 不匹配
     期望 $sha
     实际 $got
     上游可能已更新版本；请核对 VERSION 与本脚本的钉版本常量。"
  fi
  mv "$out.part" "$out"
  ok "$name 校验通过"
}

# restore_systemd_user_service <unit 名> —— 启用并立即启动用户服务
enable_user_service() {
  local unit="$1"
  run systemctl --user daemon-reload
  run systemctl --user enable --now "$unit"
  if [[ "${MODE:-install}" != "dry-run" ]]; then
    ok "$unit: $(systemctl --user is-active "$unit" 2>/dev/null || echo unknown)"
  fi
}

# detect_session —— 导出 SESSION_KIND=wayland|x11
detect_session() {
  if [[ -n "${WAYLAND_DISPLAY:-}" || "${XDG_SESSION_TYPE:-}" == "wayland" \
        || -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    SESSION_KIND=wayland
  else
    SESSION_KIND=x11
  fi
  export SESSION_KIND
}
