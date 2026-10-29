#!/usr/bin/env bash
# ==============================================================================
# 阶段 1 · 系统依赖
#
# 只为「确实缺失」的包调用一次 pacman。已齐备则完全不动系统。
# 需要 sudo 的只有这一处；其余阶段全部以当前用户身份完成。
# ==============================================================================

# 打字（Fcitx5 桥接 + Wine 引擎）
PKGS_KEYBOARD=(fcitx5 json-c cmake base-devel python wine xorg-server-xvfb mingw-w64-gcc boost)

# 语音（Doubao Say：GTK4 应用 + PipeWire 录音）
PKGS_VOICE=(python-gobject python-cairo gtk4 webkitgtk-6.0 pipewire portaudio)

# 仅在 Wayland 会话需要
PKGS_WAYLAND=(gtk4-layer-shell wl-clipboard)

# 可选：候选栏中文字体（缺失不阻断安装）
PKGS_FONT=(noto-fonts-cjk)

collect_packages() {
  WANT_PKGS=()
  local p
  for p in "${PKGS_KEYBOARD[@]}"; do WANT_PKGS+=("$p"); done
  if (( WITH_VOICE )); then
    for p in "${PKGS_VOICE[@]}"; do WANT_PKGS+=("$p"); done
    if [[ "$SESSION_KIND" == "wayland" ]]; then
      for p in "${PKGS_WAYLAND[@]}"; do WANT_PKGS+=("$p"); done
    fi
  fi
}

install_deps() {
  step "1/6 系统依赖"

  command -v pacman >/dev/null \
    || die "本脚本的系统依赖步骤目前只支持 Arch 系发行版（未找到 pacman）。
     其他发行版请参考 docs/INSTALL.md 的包名对照表手动安装，然后加 --skip-deps 重跑。"

  collect_packages

  local missing=() p
  for p in "${WANT_PKGS[@]}"; do
    pkg_installed "$p" || missing+=("$p")
  done

  if (( ${#missing[@]} == 0 )); then
    ok "依赖已齐备（${#WANT_PKGS[@]} 个）"
    return 0
  fi

  info "缺失 ${#missing[@]} 个: ${missing[*]}"

  if (( SKIP_DEPS )); then
    warn "已跳过（--skip-deps）；缺失的包可能导致后续阶段失败"
    return 0
  fi

  if [[ "${MODE:-install}" == "dry-run" ]]; then
    printf '  %s[dry-run]%s sudo pacman -S --needed %s\n' "$C_DIM" "$C_RST" "${missing[*]}"
    return 0
  fi

  sudo pacman -S --needed --noconfirm "${missing[@]}" || die "系统依赖安装失败"
  ok "依赖安装完成"
}

check_font() {
  # 官方设置窗口是 Qt/WebKit 界面，缺 CJK 字体时中文会变方块。
  # 优先 Regular 字重：Black/Bold 当界面字体会糊成一片。
  local found
  found=$(find /usr/share/fonts -iname 'NotoSansCJK-Regular.ttc' 2>/dev/null | head -1)
  if [[ -z "$found" ]]; then
    found=$(find /usr/share/fonts -iname 'NotoSansCJK*.ttc' 2>/dev/null | grep -i 'regular' | head -1)
  fi
  if [[ -z "$found" ]]; then
    found=$(find /usr/share/fonts -iname 'NotoSansCJK*.ttc' 2>/dev/null | head -1)
  fi

  if [[ -n "$found" ]]; then
    FONT_PATH="$found"
    ok "CJK 字体: $(basename "$found")"
  else
    FONT_PATH=""
    warn "未找到 NotoSansCJK 字体 —— 官方设置窗口中文可能显示为方块"
    warn "可安装: sudo pacman -S --needed ${PKGS_FONT[*]}"
  fi
}
