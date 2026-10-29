#!/usr/bin/env bash
# ==============================================================================
# doubao-linux · 回退
#
#   ./rollback.sh              dry-run（默认，只打印将要做什么）
#   ./rollback.sh --apply      实际回退
#   ./rollback.sh --snapshot   仅拍安装前快照（装之前建议先跑一次）
#   ./rollback.sh --ledger <dir>  指定某次安装的台账目录
#
# 回退顺序（刻意如此）：
#   1. 先按 ledger 逆序还原被合并/覆盖的配置 —— 这是最精确的一层
#   2. 再调上游卸载器清组件
#   3. 最后把残留文件移入 removed/（只移不删）
# 系统包只报告、不擅动：卸载 wine/gtk 可能连带影响你其它东西。
# ==============================================================================
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${XDG_CONFIG_HOME:=$HOME/.config}"

DST="${DOUBAO_BACKUP:-$HOME/.cache/doubao-linux/rollback}"
SRC="${DOUBAO_SRC:-$HOME/src/doubao-ime-linux}"
SNAP="$DST/snapshot"
LEDGER_ROOT="$HOME/.cache/doubao-linux/ledger"

MODE="dry-run"; LEDGER=""
while (( $# )); do
  case "$1" in
    --apply)    MODE="apply" ;;
    --snapshot) MODE="snapshot" ;;
    --dry-run)  MODE="dry-run" ;;
    --ledger)   shift; LEDGER="${1:-}" ;;
    -h|--help)  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "用法: $0 [--dry-run|--apply|--snapshot] [--ledger <dir>]"; exit 2 ;;
  esac
  shift
done

TS="$(date +%Y%m%d_%H%M%S)"; RB="$DST/rollback_$TS"
C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
step() { printf '\n%s══ %s ══%s\n' "$C_DIM" "$*" "$C_RST"; }
ok()   { printf '  ✔ %s\n' "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_RST" "$*"; }
act()  { if [[ "$MODE" == "dry-run" ]]; then printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RST" "$*"; else printf '  ✔ %s\n' "$*"; fi; }

# 本项目安装/写入的路径（来源：上游 install.py 清单 + 实测）
TRIAL_PATHS=(
  "$HOME/.local/lib/fcitx5/doubaoime.so"
  "$HOME/.local/share/fcitx5/addon/doubaoime.conf"
  "$HOME/.local/share/fcitx5/addon/doubaovoice.conf"
  "$HOME/.local/share/fcitx5/inputmethod/doubao.conf"
  "$HOME/.local/share/icons/hicolor/scalable/apps/doubao-ime-linux.svg"
  "$HOME/.local/bin/doubao-keyboard"
  "$HOME/.local/bin/doubao-settings"
  "$XDG_CONFIG_HOME/systemd/user/doubao-keyboard.service"
  "$XDG_CONFIG_HOME/systemd/user/doubao-say.service"
  "$HOME/.local/share/applications/doubao-settings.desktop"
  "$HOME/.local/share/fcitx5/themes/Doubao-Compact"
)
SNAP_REL=(".config/fcitx5" ".config/systemd/user")

printf 'doubao-linux 回退  |  模式=%s  |  %s\n' "$MODE" "$(date '+%F %T %z')"

# ── 自动挑最近一次台账 ──────────────────────────────────────────────────────
if [[ -z "$LEDGER" && -d "$LEDGER_ROOT" ]]; then
  LEDGER="$(ls -1d "$LEDGER_ROOT"/*/ 2>/dev/null | sort | tail -1)"
  LEDGER="${LEDGER%/}"
fi

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
    find "$HOME/.local/share/fcitx5" -name '*.userdb' -type d 2>/dev/null | head -20
    sha256sum "$XDG_CONFIG_HOME/fcitx5/profile" 2>/dev/null
    ls -1 "$HOME/.local/share/fcitx5/inputmethod" 2>/dev/null
  } > "$SNAP/ISOLATION_BASELINE.txt"
  ok "隔离基线 → $SNAP/ISOLATION_BASELINE.txt"
else
  [[ -d "$SNAP" ]] && ok "已有快照 $SNAP" || warn "尚无快照（建议安装前跑 --snapshot）"
fi

step "2. 台账还原"
if [[ -n "$LEDGER" && -f "$LEDGER/manifest.tsv" ]]; then
  ok "使用台账 $LEDGER（$(grep -c . "$LEDGER/manifest.tsv" 2>/dev/null || echo 0) 条变更）"
else
  warn "未找到台账，跳过精确还原（将退化为整体快照恢复 + 文件移除）"
fi

step "3. 回退动作"
act "停止并禁用 doubao-keyboard.service / doubao-say.service"
act "按台账逆序还原被合并的 fcitx5 配置与 Doubao Say 设置"
act "运行上游卸载：keyboard(install.py uninstall) + voice(install.sh --uninstall)"
act "移除 fcitx5 profile 中的 doubao 引擎槽"
act "重启 Fcitx"
act "残留文件移入 rollback_<ts>/removed/"

step "3b. 系统包（需 sudo，本脚本不动）"
printf '  本次可能新增：%s\n' "wine xorg-server-xvfb mingw-w64-gcc boost python-gobject gtk4 webkitgtk-6.0 portaudio"
warn "确认无其他依赖后再自行卸载，例如："
printf '    sudo pacman -Rns wine xorg-server-xvfb mingw-w64-gcc boost\n'

# ── 执行 ────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "apply" ]]; then
  step "执行中"
  mkdir -p "$RB/removed" "$RB/current"

  # 1) 停服务
  for unit in doubao-say.service doubao-keyboard.service; do
    if systemctl --user disable --now "$unit" >/dev/null 2>&1; then
      ok "已停止并禁用 $unit"
    else
      warn "$unit 未在运行"
    fi
  done

  # 2) 台账逆序还原（最精确的一层）
  if [[ -n "$LEDGER" && -f "$LEDGER/manifest.tsv" ]]; then
    mkdir -p "$RB/current"
    tac "$LEDGER/manifest.tsv" | while IFS=$'\t' read -r action target backup note; do
      [[ -z "$action" || "$action" == \#* ]] && continue
      case "$action" in
        merge-ini|merge-json|write)
          if [[ "$backup" == "-" || ! -e "$backup" ]]; then
            # 原文件本来不存在 —— 移除我们新增的
            if [[ -e "$target" ]]; then
              mkdir -p "$RB/removed/$(dirname "${target#/}")"
              mv "$target" "$RB/removed/${target#/}" 2>/dev/null && ok "移除新增文件 $target"
            fi
          else
            cp -a "$target" "$RB/current/$(basename "$target").$TS" 2>/dev/null || true
            install -Dm644 "$backup" "$target" 2>/dev/null && ok "还原 $target ← $backup"
          fi
          ;;
        *) : ;;
      esac
    done
    ok "台账还原完成（当前状态另存于 $RB/current/）"
  fi

  # 3) 上游卸载
  if [[ -f "$SRC/scripts/install.py" ]]; then
    ( cd "$SRC" && python3 scripts/install.py uninstall ) >/dev/null 2>&1 \
      && ok "键盘组件卸载完成" || warn "键盘组件卸载返回非零（继续）"
  fi
  voice_unpack="$(ls -1d "$HOME/.cache/doubao-linux"/doubao-say-* 2>/dev/null | sort | tail -1)"
  if [[ -n "$voice_unpack" && -x "$voice_unpack/install.sh" ]]; then
    ( cd "$voice_unpack" && ./install.sh --uninstall ) >/dev/null 2>&1 \
      && ok "语音组件卸载完成" || warn "语音组件卸载返回非零（继续）"
  elif [[ -d "$HOME/.local/share/doubao-say" ]]; then
    mv "$HOME/.local/share/doubao-say" "$RB/removed/doubao-say" 2>/dev/null \
      && ok "Doubao Say 安装目录已移出"
  fi

  # 4) 清引擎槽
  PROF="$XDG_CONFIG_HOME/fcitx5/profile"
  if [[ -f "$PROF" ]] && grep -qi 'doubao' "$PROF"; then
    systemctl --user stop fcitx5.service 2>/dev/null || true; sleep 1
    python3 - "$PROF" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
blocks = re.split(r'(?=\[Groups/\d+/Items/\d+\])', s)
out, idx = [], 0
for b in blocks:
    if re.match(r'\[Groups/\d+/Items/\d+\]', b):
        if 'doubao' in b.lower():
            continue
        out.append(re.sub(r'^\[Groups/\d+/Items/\d+\]', f'[Groups/0/Items/{idx}]', b, count=1)); idx += 1
        continue
    out.append(b)
res = ''.join(out)
if re.search(r'^DefaultIM=doubao', res, re.M):
    res = re.sub(r'^DefaultIM=.*$', 'DefaultIM=keyboard-us', res, flags=re.M)
p.write_text(res, encoding='utf-8')
print('  ✔ doubao 引擎槽已移除')
PY
  fi

  # 5) 移出残留
  for p in "${TRIAL_PATHS[@]}"; do
    [[ -e "$p" ]] || continue
    mkdir -p "$RB/removed/$(dirname "${p#/}")"
    mv "$p" "$RB/removed/${p#/}" 2>/dev/null && ok "移出 $p"
  done
  [[ -d "$SRC" ]] && { mv "$SRC" "$RB/removed/doubao-ime-linux" 2>/dev/null && ok "移出 $SRC"; }

  systemctl --user daemon-reload
  systemctl --user restart fcitx5.service 2>/dev/null || warn "Fcitx 重启失败，请手动重启"
  sleep 3
fi

# ── 自检 ────────────────────────────────────────────────────────────────────
step "4. 自检"
printf '  doubao 服务 : %s\n' "$(systemctl --user is-active doubao-keyboard.service 2>/dev/null || echo 已停)"
printf '  语音服务    : %s\n' "$(systemctl --user is-active doubao-say.service 2>/dev/null || echo 已停)"
printf '  Fcitx 服务  : %s\n' "$(systemctl --user is-active fcitx5.service 2>/dev/null || echo 未知)"
if [[ -f "$XDG_CONFIG_HOME/fcitx5/profile" ]]; then
  printf '  DefaultIM   : %s\n' "$(grep -m1 '^DefaultIM=' "$XDG_CONFIG_HOME/fcitx5/profile")"
  printf '  引擎槽      : %s\n' "$(grep -E '^Name=' "$XDG_CONFIG_HOME/fcitx5/profile" | tr '\n' ' ')"
  if grep -qi doubao "$XDG_CONFIG_HOME/fcitx5/profile"; then
    warn "profile 中仍有 doubao"
  else
    ok "profile 中已无 doubao"
  fi
fi

printf '\n'
if [[ "$MODE" == "dry-run" ]]; then
  printf '%s这是 dry-run，未做任何改动。%s确认后执行：./rollback.sh --apply\n' "$C_WARN" "$C_RST"
elif [[ "$MODE" == "snapshot" ]]; then
  printf '%s快照完成。%s\n' "$C_OK" "$C_RST"
else
  printf '%s回退完成。%s 现场快照 %s/current/  移出物 %s/removed/\n' "$C_OK" "$C_RST" "$RB" "$RB"
fi
