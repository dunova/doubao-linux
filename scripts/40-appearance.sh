#!/usr/bin/env bash
# ==============================================================================
# 阶段 4 · 外观（候选栏 / 主题 / 语音动效）
#
# 目标是"看起来像豆包"，分三层落地：
#   1. 主题     —— Doubao-Compact：纯色不透明紧凑候选栏，iOS 蓝 #0A84FF 高亮
#   2. 候选栏   —— 横向排列、屏幕级 DPI、分数缩放修正、CJK 字体
#   3. 语音动效 —— 波形条样式、完整动效（不降级）
#
# 关键约束：只做键级合并。用户原有的其它键、注释、自定义节一律保留；
# 改动前整文件备份并记入 ledger，rollback.sh 可逐条还原。
# ==============================================================================

# 抓一个可用的中文字体族名。豆包界面用苹方；Linux 上退到思源/Noto。
detect_cjk_family() {
  local candidate families
  families="$(fc-list : family 2>/dev/null | tr ',' '\n' | sed 's/:.*//' | sed 's/^ *//;s/ *$//' | sort -u)"
  for candidate in "PingFang SC" "Noto Sans CJK SC" "Noto Sans SC" \
                   "Source Han Sans SC" "Sarasa Term SC" "WenQuanYi Micro Hei"; do
    if printf '%s\n' "$families" | grep -qxF "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf '%s' ""
}

install_appearance() {
  step "4/6 外观 · 安装候选栏主题"
  local theme_dir="$FCITX_THEME_DIR/Doubao-Compact"
  local theme_src="$REPO_ROOT/assets/themes/Doubao-Compact/theme.conf"

  if [[ "${MODE:-install}" != "dry-run" ]]; then
    mkdir -p "$theme_dir"
    if [[ -f "$theme_dir/theme.conf" ]] && cmp -s "$theme_src" "$theme_dir/theme.conf"; then
      ok "主题已是最新"
    else
      local bak=""; [[ -f "$theme_dir/theme.conf" ]] && bak="$(backup_file "$theme_dir/theme.conf")"
      install -Dm644 "$theme_src" "$theme_dir/theme.conf"
      ledger_add "write" "$theme_dir/theme.conf" "${bak:--}" "Doubao-Compact theme"
      ok "已安装 $theme_dir/theme.conf"
    fi
  else
    printf '  %s[dry-run]%s 安装 %s\n' "$C_DIM" "$C_RST" "$theme_dir/theme.conf"
  fi

  step "4/6 外观 · 合并候选栏设置"
  local family; family="$(detect_cjk_family)"
  if [[ -n "$family" ]]; then
    ok "中文字体: $family"
  else
    family="Sans Serif"
    warn "未找到合适的中文字体，回退到 $family；候选词可能显示为方块"
  fi

  local classicui="$FCITX_CONF_DIR/classicui.conf"
  local patch; patch="$(mktemp)"
  cat > "$patch" <<EOF
# 横向候选排版
Vertical Candidate List=False
# 启用抗锯齿与多屏 DPI 自适应
PerScreenDPI=True
# 分数缩放(如 1.6)下避免候选窗口偏移/漂移：走 wp_fractional_scale 而非 wl_output.scale
EnableFractionalScale=True
Font="${family} 11"
MenuFont="${family} 12"
Theme=Doubao-Compact
DarkTheme=Doubao-Compact
UseDarkTheme=True
EOF

  if [[ "${MODE:-install}" != "dry-run" ]]; then
    local bak=""; [[ -f "$classicui" ]] && bak="$(backup_file "$classicui")"
    python3 "$REPO_ROOT/scripts/merge_conf.py" ini "$classicui" "$patch" || warn "classicui.conf 合并失败"
    ledger_add "merge-ini" "$classicui" "${bak:--}" "appearance: candidate layout + theme"
  else
    printf '  %s[dry-run]%s 合并 %s\n' "$C_DIM" "$C_RST" "$classicui"
  fi
  rm -f "$patch"

  step "4/6 外观 · 合并候选词行为"
  local pinyin="$FCITX_CONF_DIR/pinyin.conf"
  local ppatch; ppatch="$(mktemp)"
  cat > "$ppatch" <<'EOF'
# 下一词预测：豆包式的整句联想
Prediction=True
PredictionSize=10
# 词组候选数量
WordCandidateLimit=20
# 云拼音：注意这是 Google 在线接口，介意可设 False
CloudPinyinEnabled=True
CloudPinyinIndex=1
EOF

  if [[ "${MODE:-install}" != "dry-run" ]]; then
    local bak=""; [[ -f "$pinyin" ]] && bak="$(backup_file "$pinyin")"
    python3 "$REPO_ROOT/scripts/merge_conf.py" ini "$pinyin" "$ppatch" || warn "pinyin.conf 合并失败"
    ledger_add "merge-ini" "$pinyin" "${bak:--}" "appearance: prediction + candidate count"
  else
    printf '  %s[dry-run]%s 合并 %s\n' "$C_DIM" "$C_RST" "$pinyin"
  fi
  rm -f "$ppatch"

  if (( WITH_VOICE )); then
    step "4/6 外观 · 语音动效"
    local dsettings="$XDG_CONFIG_HOME/doubao-say/settings.json"
    if [[ "${MODE:-install}" != "dry-run" ]]; then
      if [[ -f "$dsettings" ]]; then
        local bak; bak="$(backup_file "$dsettings")"
        python3 "$REPO_ROOT/scripts/merge_conf.py" json "$dsettings" \
          waveform_style=bars reduced_motion=false \
          || warn "settings.json 合并失败"
        ledger_add "merge-json" "$dsettings" "${bak:--}" "appearance: waveform bars, full motion"
      else
        warn "尚未生成 $dsettings —— 首次启动 Doubao Say 后再跑一次 --only-appearance"
      fi
    else
      printf '  %s[dry-run]%s 设置波形样式与动效\n' "$C_DIM" "$C_RST"
    fi
  fi

  warn "外观改动需重启 Fcitx5 才生效: systemctl --user restart fcitx5"
}
