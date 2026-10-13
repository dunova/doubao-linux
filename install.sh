#!/usr/bin/env bash
# ==============================================================================
# doubao-linux · 一键安装
#
#   sudo ./install.sh              # 完整安装（sudo 仅用于 pacman 装系统包）
#   ./install.sh --dry-run         # 只打印将做什么
#   ./install.sh --skip-deps       # 跳过 pacman（依赖已就绪时）
#
# 需要 sudo 的只有一步：pacman 装系统包。其余全部以当前用户身份完成。
# ==============================================================================
set -uo pipefail

# ── 固定版本（不可随意改动；改版必须同步更新 SHA-256）──────────────────────
UPSTREAM_REPO="https://github.com/royess/doubao-ime-linux.git"
UPSTREAM_COMMIT="62117ce"                    # 0.1.0-rc.1 之后的最新提交
INNOEXTRACT_REPO="https://github.com/UserUnknownFactor/innoextract_win.git"
INNOEXTRACT_COMMIT="e561d8cb6004776eecb3184c0d56b3534a0c7e15"

DOUBAO_EXE_URL="https://lf-wave.doubaocdn.com/obj/doubao-ime/app/windows/DoubaoIME_Installer_0.9.0.0_release.exe"
DOUBAO_EXE_SHA256="610b8bf696835b5c4bad654b87de8695dfa808bc57aa900bcc7603e06f427f7f"

WINE_MONO_URL="https://github.com/wine-mono/wine-mono/releases/download/wine-mono-11.3.0/wine-mono-11.3.0-x86.msi"
WINE_MONO_SHA256="df2dfc1665c2511882e7cabd56eafd0c0a3d94e5a7e86f969277f6c189d418d3"

# ── 依赖清单（Arch 包名）──────────────────────────────────────────────────
PKGS=(wine xorg-server-xvfb mingw-w64-gcc boost libpulse)
PKGS_VOICE=(python-gobject opus)             # 需语音/设置窗口时另加

# ── 路径 ─────────────────────────────────────────────────────────────────
SRC="${DOUBAO_SRC:-$HOME/src/doubao-ime-linux}"
INNO_SRC="$HOME/src/innoextract-src"
INNO_BIN="$HOME/src/innoextract-build/innoextract"
ART="${DOUBAO_ART:-$HOME/.cache/doubao-linux}"
SERVICE="doubao-keyboard.service"

MODE="install"; SKIP_DEPS=0
for a in "$@"; do
  case "$a" in
    --dry-run)   MODE="dry-run" ;;
    --skip-deps) SKIP_DEPS=1 ;;
    -h|--help)   sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "未知参数: $a"; exit 2 ;;
  esac
done

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
step() { printf '\n%s══ %s ══%s\n' "$C_DIM" "$*" "$C_RST"; }
ok()   { printf '  %s✔%s %s\n' "$C_OK" "$C_RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_RST" "$*"; }
die()  { printf '  %s✘%s %s\n' "$C_ERR" "$C_RST" "$*"; exit 1; }
run()  { if [[ "$MODE" == "dry-run" ]]; then printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RST" "$*"; else eval "$@"; fi; }

printf 'doubao-linux 安装  |  模式=%s  |  %s\n' "$MODE" "$(date '+%F %T %z')"

# ─────────────────────────────────────────────────────────────────────────
step "1/8 环境检查"
[[ "$(uname -m)" == "x86_64" ]] || die "仅支持 x86_64（当前 $(uname -m)）"
command -v pacman >/dev/null || die "仅支持 Arch 系发行版（未找到 pacman）"
command -v fcitx5  >/dev/null || die "未找到 fcitx5"
free_kb=$(df -Pk "$HOME" | awk 'NR==2{print $4}')
(( free_kb > 6*1024*1024 )) || die "磁盘可用空间不足 6 GB"
ok "x86_64 / Arch / fcitx5 / 磁盘 $(awk -v k="$free_kb" 'BEGIN{printf "%.0f GB", k/1048576}')"
[[ -n "${XDG_SESSION_TYPE:-}" ]] && ok "会话: $XDG_SESSION_TYPE ${XDG_CURRENT_DESKTOP:-}"
[[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && warn "Wayland 会话：键盘部分上游未做专项回归，请先跑 ./verify.sh"

# ─────────────────────────────────────────────────────────────────────────
step "2/8 安装系统依赖"
if (( SKIP_DEPS )); then
  ok "已跳过（--skip-deps）"
else
  MISSING=()
  for p in "${PKGS[@]}" "${PKGS_VOICE[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || MISSING+=("$p"); done
  if (( ${#MISSING[@]} == 0 )); then ok "依赖已齐备"; else
    ok "需安装: ${MISSING[*]}"
    run "sudo pacman -S --noconfirm --needed ${MISSING[*]}"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────
step "3/8 获取上游桥接源码"
if [[ -d "$SRC/.git" ]]; then
  ok "已存在 $SRC"
else
  run "git clone --quiet '$UPSTREAM_REPO' '$SRC'"
fi
run "git -C '$SRC' checkout --quiet '$UPSTREAM_COMMIT'" && ok "已固定在 $UPSTREAM_COMMIT"

# ─────────────────────────────────────────────────────────────────────────
step "4/8 构建 innoextract（解包官方安装包用）"
if [[ -x "$INNO_BIN" ]]; then ok "已存在 $INNO_BIN"; else
  [[ -d "$INNO_SRC/.git" ]] || run "git clone --quiet '$INNOEXTRACT_REPO' '$INNO_SRC'"
  run "git -C '$INNO_SRC' checkout --quiet '$INNOEXTRACT_COMMIT'"
  run "cmake -S '$INNO_SRC' -B '$HOME/src/innoextract-build' -DCMAKE_BUILD_TYPE=Release >/dev/null"
  run "cmake --build '$HOME/src/innoextract-build' -j\$(nproc) >/dev/null"
fi
[[ "$MODE" == "dry-run" || -x "$INNO_BIN" ]] && ok "innoextract 就绪"

# ─────────────────────────────────────────────────────────────────────────
step "5/8 下载并校验官方安装包与 Wine Mono"
mkdir -p "$ART"
dl_verified() {  # $1=url $2=sha256 $3=输出路径 $4=名称
  if [[ -f "$3" ]] && [[ "$(sha256sum "$3" | cut -d' ' -f1)" == "$2" ]]; then ok "$4 已存在且校验通过"; return 0; fi
  if [[ "$MODE" == "dry-run" ]]; then printf '  %s[dry-run]%s 下载 %s\n' "$C_DIM" "$C_RST" "$4"; return 0; fi
  curl -fL --retry 3 -o "$3.part" "$1" >/dev/null 2>&1 || die "$4 下载失败"
  [[ "$(sha256sum "$3.part" | cut -d' ' -f1)" == "$2" ]] || { rm -f "$3.part"; die "$4 SHA-256 不匹配（版本不符或下载被篡改）"; }
  mv "$3.part" "$3"; ok "$4 校验通过"
}
dl_verified "$DOUBAO_EXE_URL"  "$DOUBAO_EXE_SHA256"  "$ART/DoubaoIME_Installer_0.9.0.0_release.exe" "豆包官方安装包"
dl_verified "$WINE_MONO_URL"   "$WINE_MONO_SHA256"   "$ART/wine-mono-11.3.0-x86.msi"                "Wine Mono"

# ─────────────────────────────────────────────────────────────────────────
step "6/8 编译桥接（Fcitx 插件 + Windows RPC 宿主）"
FONT=$(ls /usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc 2>/dev/null \
       || find /usr/share/fonts -iname 'NotoSansCJK-*.ttc' 2>/dev/null | head -1 || true)
[[ -n "$FONT" ]] || warn "未找到 Noto CJK 字体，官方设置窗口中文可能显示为方块"

if [[ "$MODE" != "dry-run" ]]; then
  python3 - "$INNO_BIN" "$SRC/work" "$FONT" <<'PY'
import json, sys, pathlib
inno, state, font = sys.argv[1], sys.argv[2], sys.argv[3]
src = pathlib.Path('config.example.json'); dst = pathlib.Path('config.local.json')
cfg = json.loads(src.read_text(encoding='utf-8')) if src.exists() else {}
cfg['innoextract'] = inno
if state: cfg['state_dir'] = state
if font:  cfg['settings_font'] = font
dst.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding='utf-8')
print('  config.local.json 已生成')
PY
fi > /dev/null
run "cd '$SRC' && cmake -S . -B build/fcitx -DCMAKE_BUILD_TYPE=Release >/dev/null"
run "cd '$SRC' && cmake --build build/fcitx -j\$(nproc) >/dev/null"
run "cd '$SRC' && python3 scripts/build_windows.py >/dev/null"
ok "插件与宿主编译完成"

# ─────────────────────────────────────────────────────────────────────────
step "7/8 准备私有 Wine 环境（全新 prefix，不导入任何既有账号或词库）"
run "cd '$SRC' && python3 scripts/prepare.py extract --installer '$ART/DoubaoIME_Installer_0.9.0.0_release.exe' >/dev/null"
MONO_ARG=""; [[ -f "$ART/wine-mono-11.3.0-x86.msi" ]] && MONO_ARG="--settings --mono-msi '$ART/wine-mono-11.3.0-x86.msi'"
FONT_ARG=""; [[ -n "$FONT" ]] && FONT_ARG="--font '$FONT'"
run "cd '$SRC' && python3 scripts/prepare.py init $MONO_ARG $FONT_ARG >/dev/null"
ok "Wine 环境就绪"

# ─────────────────────────────────────────────────────────────────────────
step "8/8 部署并注册"
run "cd '$SRC' && python3 scripts/install.py install --settings >/dev/null"
run "systemctl --user daemon-reload"
run "systemctl --user enable --now $SERVICE"
if [[ "$MODE" != "dry-run" ]]; then sleep 6; ok "服务: $(systemctl --user is-active $SERVICE)"; fi

# 注册 Fcitx 引擎槽（幂等；DefaultIM 不动，由用户决定何时切过去）
if [[ "$MODE" != "dry-run" ]]; then
  systemctl --user stop omarchy-fcitx5.service 2>/dev/null || systemctl --user stop fcitx5.service 2>/dev/null || true
  sleep 1
  python3 - <<'PY'
import os, re
p = os.path.expanduser('~/.config/fcitx5/profile')
if not os.path.exists(p):
    print('  profile 不存在，跳过（重启 Fcitx5 后手动添加「豆包」）')
else:
    s = open(p, encoding='utf-8').read()
    if 'doubao' in s.lower():
        print('  doubao 引擎槽已存在，跳过')
    else:
        n = 0
        for m in re.finditer(r'\[Groups/0/Items/(\d+)\]', s): n = max(n, int(m.group(1)) + 1)
        block = f"[Groups/0/Items/{n}]\n# Name\nName=doubao\n# Layout\n# Layout=\n\n"
        if s.count('[GroupOrder]') == 1:
            open(p, 'w', encoding='utf-8').write(s.replace('[GroupOrder]', block + '[GroupOrder]'))
            print(f'  已追加 [Groups/0/Items/{n}] Name=doubao（DefaultIM 保持不变）')
        else:
            print('  profile 结构与预期不符，未改动；请在 Fcitx 配置工具中手动添加「豆包」')
PY
  systemctl --user start omarchy-fcitx5.service 2>/dev/null || systemctl --user start fcitx5.service 2>/dev/null || true
  sleep 4
  ok "Fcitx 引擎槽已注册"
fi

printf '\n%s安装完成。%s\n' "$C_OK" "$C_RST"
cat <<'EOF'
  下一步：
    1. 重启 Fcitx5：systemctl --user restart omarchy-fcitx5.service
    2. 按 Ctrl+Space 切到「豆包」，打一句 nihao 验证
    3. 跑 ./verify.sh 做端到端验证
  回退：
    ./rollback.sh --apply
EOF
