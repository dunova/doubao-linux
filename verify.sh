#!/usr/bin/env bash
# ==============================================================================
# doubao-linux · 端到端验证
#
# 分四层验证，任何一层失败都不影响其他层继续跑：
#   1. 打字引擎  —— 真实 broker + 真实官方引擎的集成测试
#   2. Fcitx 侧  —— 插件加载与引擎槽可切换
#   3. 语音      —— 服务状态、注入依赖、快捷键绑定
#   4. 外观      —— 主题文件与关键配置项是否生效
#
# 只读为主。唯一有副作用的是「停服务 → 跑隔离测试 → 启服务」，
# 这是上游集成测试的要求（测试需要独占 socket）。
# ==============================================================================
set -uo pipefail

SRC="${DOUBAO_SRC:-$HOME/src/doubao-ime-linux}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
pass=0; fail=0; skip=0
chk() {
  if [[ "$2" == "1" ]]; then
    printf '  %sPASS%s %s\n' "$C_OK" "$C_RST" "$1"; pass=$((pass+1))
  elif [[ "$2" == "skip" ]]; then
    printf '  %sSKIP%s %s%s\n' "$C_DIM" "$C_RST" "$1" "${3:+  ← $3}"; skip=$((skip+1))
  else
    printf '  %sFAIL%s %s%s\n' "$C_ERR" "$C_RST" "$1" "${3:+  ← $3}"; fail=$((fail+1))
  fi
}

# 兼容不同的 fcitx5 启动方式：
#   omarchy-fcitx5.service / fcitx5.service（独立单元）
#   dbus-:1.x-org.fcitx.Fcitx5@0.service（D-Bus 激活，无固定名）
#   裸进程（由 autostart 或会话脚本拉起）
fcitx_unit() {
  local u
  for u in omarchy-fcitx5.service fcitx5.service; do
    [[ "$(systemctl --user is-active "$u" 2>/dev/null)" == "active" ]] && { printf '%s' "$u"; return 0; }
  done
  u="$(systemctl --user list-units --type=service --state=active --no-legend 2>/dev/null \
        | awk '/org\.fcitx\.Fcitx5/ {print $1; exit}')"
  [[ -n "$u" ]] && { printf '%s' "$u"; return 0; }
  pgrep -x fcitx5 >/dev/null 2>&1 && { printf '%s' "bare-process"; return 0; }
  printf ''
}

printf 'doubao-linux 验证  |  %s\n\n' "$(date '+%F %T')"

# ── 1. 打字引擎 ─────────────────────────────────────────────────────────────
printf '%s══ 1. 打字引擎 ══%s\n' "$C_DIM" "$C_RST"
if [[ "$(systemctl --user is-active doubao-keyboard.service 2>/dev/null)" == "active" ]]; then
  chk "doubao-keyboard.service active" 1
else
  chk "doubao-keyboard.service active" 0 "服务未运行，先跑 ./install.sh"
fi

if [[ -d "$SRC" ]]; then
  echo "  ${C_DIM}停服务跑隔离集成测试（需独占 socket）…${C_RST}"
  systemctl --user stop doubao-keyboard.service >/dev/null 2>&1; sleep 2
  # 等 wineserver 退净并清掉陈旧 socket：陈留文件会让测试连到已关闭的监听端，
  # 报 ConnectionRefused，看起来像引擎失败，其实是残留。
  for _ in $(seq 1 20); do pgrep -x wineserver >/dev/null || break; sleep 0.5; done
  rm -f "$SRC/work/keyboard-test.sock"

  OUT=$( cd "$SRC" && timeout 300 python3 scripts/headless.py --prefix keyboard \
          -- python3 tests/integration_keyboard.py 2>&1 )
  if echo "$OUT" | grep -q 'official candidates include 你好'; then
    chk "官方引擎返回候选（含「你好」）" 1
  else
    chk "官方引擎返回候选（含「你好」）" 0 "$(echo "$OUT" | tail -3 | tr '\n' ' ')"
  fi
  N=$(echo "$OUT" | grep -c '^PASS')
  (( N >= 11 )) && chk "集成测试通过项 ≥ 11（实得 $N）" 1 || chk "集成测试通过项 ≥ 11（实得 $N）" 0
  systemctl --user start doubao-keyboard.service >/dev/null 2>&1; sleep 5
else
  chk "找到上游源码目录" 0 "$SRC 不存在"
fi

# ── 2. Fcitx 侧 ─────────────────────────────────────────────────────────────
printf '\n%s══ 2. Fcitx 侧 ══%s\n' "$C_DIM" "$C_RST"
UNIT="$(fcitx_unit)"
[[ -n "$UNIT" ]] && chk "Fcitx5 运行中（$UNIT）" 1 || chk "Fcitx5 运行中" 0
grep -qi 'doubao' "$XDG_CONFIG_HOME/fcitx5/profile" 2>/dev/null \
  && chk "profile 中有 doubao 引擎槽" 1 || chk "profile 中有 doubao 引擎槽" 0

if command -v fcitx5-remote >/dev/null; then
  ORIG=$(timeout 5 fcitx5-remote -n 2>/dev/null || echo '')
  timeout 5 fcitx5-remote -s doubao >/dev/null 2>&1; sleep 1
  CUR=$(timeout 5 fcitx5-remote -n 2>/dev/null || echo '')
  [[ "$CUR" == "doubao" ]] && chk "可切换到豆包引擎" 1 || chk "可切换到豆包引擎" 0 "当前=$CUR"
  # 还原用户原本的引擎，不要留在 doubao 上
  if [[ -n "$ORIG" && "$ORIG" != "doubao" ]]; then
    timeout 5 fcitx5-remote -s "$ORIG" >/dev/null 2>&1 && printf '  %s·%s 已还原原引擎 %s\n' "$C_DIM" "$C_RST" "$ORIG"
  fi
else
  chk "fcitx5-remote 可用" skip "未安装，跳过引擎切换测试"
fi

# ── 3. 语音 ─────────────────────────────────────────────────────────────────
printf '\n%s══ 3. 语音输入 ══%s\n' "$C_DIM" "$C_RST"
VOICE_APP="$XDG_DATA_HOME/doubao-say/app"
if [[ -d "$VOICE_APP" ]]; then
  chk "Doubao Say 已安装" 1
  if [[ -f "$VOICE_APP/VERSION" ]]; then
    printf '  %s·%s 已装版本 %s\n' "$C_DIM" "$C_RST" "$(cat "$VOICE_APP/VERSION" 2>/dev/null)"
  fi
else
  chk "Doubao Say 已安装" 0 "未找到 $VOICE_APP（可能用 --no-voice 安装）"
fi

[[ "$(systemctl --user is-active doubao-say.service 2>/dev/null)" == "active" ]] \
  && chk "doubao-say.service active" 1 \
  || chk "doubao-say.service active" 0 "服务未运行"

if pgrep -f 'doubao_input' >/dev/null 2>&1; then
  chk "语音进程在运行" 1
else
  chk "语音进程在运行" skip "无 doubao_input 进程"
fi

# 文字注入依赖：Wayland 下需 wl-clipboard 或 wtype
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  if command -v wl-copy >/dev/null || command -v wtype >/dev/null; then
    chk "Wayland 注入工具可用" 1
  else
    chk "Wayland 注入工具可用" 0 "缺 wl-clipboard / wtype"
  fi
else
  if command -v xdotool >/dev/null || command -v xclip >/dev/null; then
    chk "X11 注入工具可用" 1
  else
    chk "X11 注入工具可用" skip "缺 xdotool/xclip，文字会留在剪贴板待手动粘贴"
  fi
fi

if [[ -f "$XDG_CONFIG_HOME/doubao-say/settings.json" ]]; then
  if python3 -c "
import json,sys
d=json.load(open('$XDG_CONFIG_HOME/doubao-say/settings.json'))
sys.exit(0 if d.get('mic_device') or d.get('microphone') else 1)
" 2>/dev/null; then
    chk "已选择麦克风" 1
  else
    chk "已选择麦克风" skip "首次启动时在设置里选一次"
  fi
else
  chk "Doubao Say 配置文件" skip "尚未生成，首次启动后才有"
fi

# ── 4. 外观 ─────────────────────────────────────────────────────────────────
printf '\n%s══ 4. 外观 ══%s\n' "$C_DIM" "$C_RST"
THEME="$XDG_DATA_HOME/fcitx5/themes/Doubao-Compact/theme.conf"
[[ -f "$THEME" ]] && chk "Doubao-Compact 主题已安装" 1 || chk "Doubao-Compact 主题已安装" 0 "$THEME 缺失"

CLASSIC="$XDG_CONFIG_HOME/fcitx5/conf/classicui.conf"
if [[ -f "$CLASSIC" ]]; then
  grep -q '^Theme=Doubao-Compact' "$CLASSIC" 2>/dev/null \
    && chk "classicui 使用 Doubao-Compact" 1 || chk "classicui 使用 Doubao-Compact" 0
  grep -qi '^Vertical Candidate List=False' "$CLASSIC" 2>/dev/null \
    && chk "候选栏为横向排列" 1 || chk "候选栏为横向排列" skip "未设置则用 Fcitx 默认"
  grep -qi '^EnableFractionalScale=True' "$CLASSIC" 2>/dev/null \
    && chk "分数缩放修正已开启" 1 || chk "分数缩放修正已开启" skip "非分数缩放环境可忽略"
else
  chk "classicui.conf 存在" skip "文件不存在，说明尚未套用外观"
fi

PINYIN="$XDG_CONFIG_HOME/fcitx5/conf/pinyin.conf"
if [[ -f "$PINYIN" ]]; then
  grep -qi '^Prediction=True' "$PINYIN" 2>/dev/null \
    && chk "下一词预测已开启" 1 || chk "下一词预测已开启" skip
fi

# ── 汇总 ────────────────────────────────────────────────────────────────────
printf '\n════════════════════════════════\n'
if (( fail == 0 )); then
  printf '%s全部通过：%d 项%s' "$C_OK" "$pass" "$C_RST"
else
  printf '%s通过 %d / 失败 %d%s' "$C_ERR" "$pass" "$fail" "$C_RST"
fi
(( skip > 0 )) && printf '，跳过 %d（非致命）' "$skip"
printf '\n'
exit $(( fail > 0 ))
