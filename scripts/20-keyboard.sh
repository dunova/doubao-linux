#!/usr/bin/env bash
# ==============================================================================
# 阶段 2 · 打字（键盘引擎）
#
#   按键 → Fcitx5 原生插件 → Unix socket → Wine RPC 宿主 → 官方豆包引擎
#                ← 预编辑 / 候选词 / 提交文字 ←
#
# 本阶段做四件事：
#   1. 拉取上游桥接源码（钉 commit）
#   2. 构建 innoextract（解包官方安装包）
#   3. 下载并校验官方安装包与 Wine Mono
#   4. 编译插件 + 搭建私有 Wine 环境 + 注册 Fcitx 引擎槽
#
# 官方引擎与安装包不随本仓库分发，只在此处从官方 CDN 下载并校验。
# ==============================================================================

install_keyboard() {
  step "2/6 打字引擎 · 获取上游桥接源码"

  if [[ -d "$SRC/.git" ]]; then
    ok "已存在 $SRC"
    # 钉住 commit；本地有改动时先停下，不覆盖用户工作
    if [[ -n "$(git -C "$SRC" status --porcelain 2>/dev/null)" ]]; then
      warn "$SRC 有未提交改动，保留现状不切换 commit"
    else
      run git -C "$SRC" fetch --quiet origin || warn "fetch 失败，继续用本地已有提交"
      run git -C "$SRC" checkout --quiet "$UPSTREAM_COMMIT"
    fi
  else
    run git clone --quiet "$UPSTREAM_REPO" "$SRC"
    run git -C "$SRC" checkout --quiet "$UPSTREAM_COMMIT"
  fi
  [[ "${MODE:-install}" == "dry-run" ]] || ok "上游源码固定在 $UPSTREAM_COMMIT"

  step "2/6 打字引擎 · 准备 innoextract"
  # 官方安装包是 Inno Setup 6.7 格式，上游要求能解 6.7 的版本。
  # 若用户显式指定了可用的二进制（发行版自带包），就不重复编译。
  if [[ -n "${DOUBAO_INNOEXTRACT:-}" ]]; then
    [[ -x "${DOUBAO_INNOEXTRACT}" ]] \
      || die "DOUBAO_INNOEXTRACT 指向的文件不可执行: $DOUBAO_INNOEXTRACT"
    INNO_BIN="$DOUBAO_INNOEXTRACT"
    ok "使用指定的 innoextract: $INNO_BIN"
  elif [[ -x "$INNO_BIN" ]]; then
    ok "已存在 $INNO_BIN"
  else
    [[ -d "$INNO_SRC/.git" ]] || run git clone --quiet "$INNOEXTRACT_REPO" "$INNO_SRC"
    run git -C "$INNO_SRC" checkout --quiet "$INNOEXTRACT_COMMIT"
    run cmake -S "$INNO_SRC" -B "$INNO_BUILD" -DCMAKE_BUILD_TYPE=Release
    run cmake --build "$INNO_BUILD" -j"$(nproc)"
    ok "innoextract 构建完成"
  fi

  step "2/6 打字引擎 · 下载并校验官方组件"
  mkdir -p "$STATE_ROOT/downloads" 2>/dev/null || true
  dl_verified "$DOUBAO_EXE_URL" "$DOUBAO_EXE_SHA256" \
    "$STATE_ROOT/downloads/DoubaoIME_Installer_${ENGINE_VERSION}_release.exe" "官方安装包 ${ENGINE_VERSION}"
  dl_verified "$WINE_MONO_URL" "$WINE_MONO_SHA256" \
    "$STATE_ROOT/downloads/wine-mono-11.3.0-x86.msi" "Wine Mono 11.3.0"

  step "2/6 打字引擎 · 编译插件"
  if [[ "${MODE:-install}" != "dry-run" ]]; then
    # 生成 config.local.json，把工具路径显式写进去
    python3 - "$INNO_BIN" "$SRC/work" "$FONT_PATH" "$SRC/config.example.json" "$SRC/config.local.json" <<'PY'
import json, sys, pathlib
inno, state, font, src, dst = sys.argv[1:6]
cfg = {}
p = pathlib.Path(src)
if p.exists():
    cfg = json.loads(p.read_text(encoding='utf-8'))
cfg['innoextract'] = inno
if state: cfg['state_dir'] = state
if font:  cfg['settings_font'] = font
pathlib.Path(dst).write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding='utf-8')
print('  · config.local.json 已生成')
PY
  fi
  run cmake -S "$SRC" -B "$SRC/build/fcitx" -DCMAKE_BUILD_TYPE=Release
  run cmake --build "$SRC/build/fcitx" -j"$(nproc)"
  run python3 "$SRC/scripts/build_windows.py"
  ok "Fcitx 插件与 Windows RPC 宿主编译完成"

  step "2/6 打字引擎 · 准备私有 Wine 环境"
  info "使用全新 Wine prefix，不导入任何既有账号、词库或输入法数据"
  local mono_args=() font_args=()
  local mono_msi="$STATE_ROOT/downloads/wine-mono-11.3.0-x86.msi"
  # dry-run 下 MSI 尚未下载，但也要把 --settings 展示出来，否则看不出真实流程
  if [[ -f "$mono_msi" || "${MODE:-install}" == "dry-run" ]]; then
    mono_args=(--settings --mono-msi "$mono_msi")
  fi
  [[ -n "$FONT_PATH" ]] && font_args=(--font "$FONT_PATH")

  run python3 "$SRC/scripts/prepare.py" extract \
    --installer "$STATE_ROOT/downloads/DoubaoIME_Installer_${ENGINE_VERSION}_release.exe"
  run python3 "$SRC/scripts/prepare.py" init "${mono_args[@]}" "${font_args[@]}"
  ok "Wine 环境就绪"

  step "2/6 打字引擎 · 部署并注册"
  run python3 "$SRC/scripts/install.py" install --settings
  enable_user_service doubao-keyboard.service
  register_fcitx_engine
}

# register_fcitx_engine —— 幂等地往 fcitx5 profile 追加 doubao 引擎槽
# 刻意不修改 DefaultIM：装完不等于立刻切换，由用户自己按 Ctrl+Space 决定。
register_fcitx_engine() {
  local profile="$XDG_CONFIG_HOME/fcitx5/profile"
  if [[ "${MODE:-install}" == "dry-run" ]]; then
    printf '  %s[dry-run]%s 在 %s 中确保存在 doubao 引擎槽\n' "$C_DIM" "$C_RST" "$profile"
    return 0
  fi
  if [[ ! -f "$profile" ]]; then
    warn "fcitx5 profile 不存在；启动 Fcitx5 后在配置工具里手动添加「豆包」"
    return 0
  fi

  local result
  result=$(python3 - "$profile" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
if re.search(r'^Name=doubao$', s, re.M):
    print('SKIP 已存在 doubao 引擎槽')
    raise SystemExit
nums = [int(m.group(1)) for m in re.finditer(r'\[Groups/0/Items/(\d+)\]', s)]
n = (max(nums) + 1) if nums else 0
block = f"[Groups/0/Items/{n}]\n# Name\nName=doubao\n# Layout\n# Layout=\n\n"
if s.count('[GroupOrder]') != 1:
    print('WARN profile 结构不符合预期，未改动')
    raise SystemExit
p.write_text(s.replace('[GroupOrder]', block + '[GroupOrder]'), encoding='utf-8')
print(f'ADD 已追加 [Groups/0/Items/{n}] Name=doubao')
PY
)
  case "$result" in
    SKIP*) ledger_add "keep" "$profile" - "$result"; ok "${result#SKIP }" ;;
    ADD*)  ledger_add "append-im-slot" "$profile" - "$result"; ok "${result#ADD }（DefaultIM 保持不变）" ;;
    *)     warn "${result#WARN }" ;;
  esac
}
