#!/usr/bin/env bash
# ==============================================================================
# doubao-linux · 回退
#
#   ./rollback.sh              # dry-run（默认，只打印）
#   ./rollback.sh --apply      # 实际回退
#   ./rollback.sh --snapshot   # 仅拍安装前快照（安装前建议先跑）
#
# 原则：幂等 / 只移不删（move 进 rollback-<ts>/removed/）/ 先快照后动作 /
#       系统包只报告不擅动 / 回退后验证其他输入法未被波及
# ==============================================================================
set -uo pipefail

DST="${DOUBAO_BACKUP:-$HOME/.cache/doubao-linux/rollback}"
SRC="${DOUBAO_SRC:-$HOME/src/doubao-ime-linux}"
SERVICE="doubao-keyboard.service"
SNAP="$DST/snapshot"

MODE="dry-run"
case "${1:-}" in
  --apply)    MODE="apply" ;;
  --snapshot) MODE="snapshot" ;;
  --dry-run|"") MODE="dry-run" ;;
  *) echo "用法: $0 [--dry-run|--apply|--snapshot]"; exit 2 ;;
esac

TS="$(date +%Y%m%d_%H%M%S)"; RB="$DST/rollback_$TS"
C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
step() { printf '\n%s══ %s ══%s\n' "$C_DIM" "$*" "$C_RST"; }
act()  { [[ "$MODE" == "dry-run" ]] && printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RST" "$*" || printf '  ✔ %s\n' "$*"; }
ok()   { printf '  ✔ %s\n' "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_RST" "$*"; }

# 本项目安装的路径（源：install.py 清单 + 实测）
TRIAL_PATHS=(
  "$HOME/.local/lib/fcitx5/doubaoime.so"
  "$HOME/.local/share/fcitx5/addon/doubaoime.conf"
  "$HOME/.local/share/fcitx5/inputmethod/doubao.conf"
  "$HOME/.local/share/icons/hicolor/scalable/apps/doubao-ime-linux.svg"
  "$HOME/.local/bin/doubao-keyboard"
  "$HOME/.local/bin/doubao-settings"
  "$HOME/.config/systemd/user/doubao-keyboard.service"
  "$HOME/.local/share/applications/doubao-settings.desktop"
)
SNAP_REL=(".config/fcitx5" ".config/systemd/user")

printf 'doubao-linux 回退  |  模式=%s  |  %s\n' "$MODE" "$(date '+%F %T %z')"

step "1. 安装前快照"
if [[ "$MODE" == "snapshot" ]]; then
  mkdir -p "$SNAP"
  for rel in "${SNAP_REL[@]}"; do
    [[ -e "$HOME/$rel" ]] || continue
    tag=$(echo "$rel" | tr '/' '_')
    tar -C "$HOME" -I 'zstd -3 -T0' -cf "$SNAP/${tag}.tar.zst" "$rel" 2>/dev/null && ok "归档 ~/$rel"
  done
  {
    echo "# 其他输入法的隔离基线 @ $(date '+%F %T %z')"
    find "$HOME/.local/share/fcitx5/rime" -o -name '*.userdb' -type d 2>/dev/null | head -20
    sha256sum "$HOME/.local/share/fcitx5/rime/rime_ice.custom.yaml" 2>/dev/null
    sha256sum "$HOME/.config/fcitx5/profile" 2>/dev/null
    ls -1 "$HOME/.local/share/fcitx5/inputmethod" 2>/dev/null
  } > "$SNAP/ISOLATION_BASELINE.txt"
  ok "隔离基线 → $SNAP/ISOLATION_BASELINE.txt"
else
  [[ -d "$SNAP" ]] && ok "已有快照 $SNAP" || warn "尚无快照（建议安装前跑 --snapshot）"
fi

step "2. 回退动作"
act "停止并禁用 $SERVICE"
act "运行上游卸载：python3 scripts/install.py uninstall"
act "从快照恢复 ~/.config/fcitx5/profile"
act "就地移除 doubao 引擎槽（保留其他引擎不动）"
act "重启 Fcitx：systemctl --user restart omarchy-fcitx5.service"
act "源码目录与 work/ 移入 rollback-<ts>/removed/"

step "2b. 系统包（需 sudo，本脚本不动）"
printf '  本次安装新增：%s\n' "wine xorg-server-xvfb mingw-w64-gcc boost python-gobject opus libpulse"
warn "确认无其他依赖后再卸载："
printf '    sudo pacman -Rns wine xorg-server-xvfb mingw-w64-gcc boost python-gobject opus libpulse\n'

# ── 执行 ─────────────────────────────────────────────────────────────────
if [[ "$MODE" == "apply" ]]; then
  step "执行中"
  mkdir -p "$RB/removed" "$RB/current"

  systemctl --user disable --now "$SERVICE" >/dev/null 2>&1 && ok "已停止并禁用 $SERVICE" || warn "$SERVICE 未在运行"

  if [[ -f "$SRC/scripts/install.py" ]]; then
    ( cd "$SRC" && python3 scripts/install.py uninstall ) >/dev/null 2>&1 \
      && ok "上游卸载完成" || warn "上游卸载返回非零（继续）"
  fi

  for rel in "${SNAP_REL[@]}"; do
    [[ -e "$HOME/$rel" ]] || continue
    tag=$(echo "$rel" | tr '/' '_')
    tar -C "$HOME" -I 'zstd -3 -T0' -cf "$RB/current/${tag}.tar.zst" "$rel" 2>/dev/null
  done

  if [[ -f "$SNAP/.config_fcitx5.tar.zst" ]]; then
    T=$(mktemp -d "$HOME/.cache/db-rb.XXXXXX")
    tar --zstd -C "$T" -xf "$SNAP/.config_fcitx5.tar.zst" 2>/dev/null \
      && cp -a "$T/.config/fcitx5/profile" "$HOME/.config/fcitx5/profile" 2>/dev/null \
      && ok "profile 已从快照恢复"
    rm -rf "$T"
  fi

  PROF="$HOME/.config/fcitx5/profile"
  if [[ -f "$PROF" ]] && grep -qi 'doubao' "$PROF"; then
    systemctl --user stop omarchy-fcitx5.service 2>/dev/null || true; sleep 1
    python3 - <<'PY'
import os, re
p = os.path.expanduser('~/.config/fcitx5/profile')
s = open(p, encoding='utf-8').read()
blocks = re.split(r'(?=\[Groups/\d+/Items/\d+\])', s); out=[]; idx=0
for b in blocks:
    if re.match(r'\[Groups/\d+/Items/\d+\]', b):
        if 'doubao' in b.lower(): continue
        out.append(re.sub(r'^\[Groups/\d+/Items/\d+\]', f'[Groups/0/Items/{idx}]', b, count=1)); idx+=1
    else: out.append(b)
res = ''.join(out)
if re.search(r'^DefaultIM=doubao', res, re.M):
    res = re.sub(r'^DefaultIM=.*$', 'DefaultIM=keyboard-us', res, flags=re.M)
open(p, 'w', encoding='utf-8').write(res)
print('  ✔ doubao 引擎槽已移除')
PY
  fi

  for p in "${TRIAL_PATHS[@]}"; do
    [[ -e "$p" ]] || continue
    mv "$p" "$RB/removed/$(basename "$p")" 2>/dev/null && ok "移出 $p"
  done
  [[ -d "$SRC" ]] && { mv "$SRC" "$RB/removed/doubao-ime-linux" 2>/dev/null && ok "移出 $SRC"; }

  systemctl --user daemon-reload
  systemctl --user restart omarchy-fcitx5.service 2>/dev/null \
    || systemctl --user restart fcitx5.service 2>/dev/null \
    || warn "Fcitx 重启失败，请手动重启"
  sleep 4
fi

step "3. 自检"
printf '  doubao 服务   : %s\n' "$(systemctl --user is-active $SERVICE 2>/dev/null || echo 已停)"
printf '  Fcitx 服务    : %s\n' "$(systemctl --user is-active omarchy-fcitx5.service 2>/dev/null)"
if [[ -f "$HOME/.config/fcitx5/profile" ]]; then
  printf '  DefaultIM     : %s\n' "$(grep -m1 '^DefaultIM=' "$HOME/.config/fcitx5/profile")"
  printf '  引擎槽        : %s\n' "$(grep -E '^Name=' "$HOME/.config/fcitx5/profile" | tr '\n' ' ')"
  grep -qi doubao "$HOME/.config/fcitx5/profile" && warn "profile 中仍有 doubao" || ok "profile 中已无 doubao"
fi
printf '  活动引擎      : %s\n' "$(timeout 5 fcitx5-remote -n 2>&1)"
if [[ -f "$SNAP/ISOLATION_BASELINE.txt" ]]; then
  B=$(grep -m1 'rime_ice.custom.yaml' "$SNAP/ISOLATION_BASELINE.txt" | awk '{print $1}')
  N=$(sha256sum "$HOME/.local/share/fcitx5/rime/rime_ice.custom.yaml" 2>/dev/null | awk '{print $1}')
  [[ -n "$B" && "$B" == "$N" ]] && ok "其他输入法（rime）数据未被改动" || warn "rime 配置与基线不同（$B vs $N）"
fi

printf '\n'
if [[ "$MODE" == "dry-run" ]]; then
  printf '%s这是 dry-run，未做任何改动。%s确认后执行：./rollback.sh --apply\n' "$C_WARN" "$C_RST"
else
  printf '%s回退完成。%s 现场快照 $RB/current/  移出物 $RB/removed/\n' "$C_OK" "$C_RST"
fi
