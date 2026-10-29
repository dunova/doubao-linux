#!/usr/bin/env bash
# ==============================================================================
# 阶段 3 · 语音输入（Doubao Say）
#
#   Linux 录音 → 豆包云识别（流式）→ 可选文字润色 → 注入到当前光标
#
# Doubao Say 是独立的上游项目（MIT），本仓库不复制其源码，
# 而是从它的 GitHub Release 下载官方离线包、校验 SHA-256 后调用它自己的安装器。
# 这样上游发版只需改本文件的版本常量，不必跟随改一堆代码。
# ==============================================================================

# 按 CPython 主次版本选对应 wheel 集的离线包；上游为每个 Python 版本单独打包。
voice_asset_name() {
  local tag="$1" cp="$2"
  printf 'doubao-say-%s-app-linux-x86_64-cpython-%s.tar.gz' "$tag" "$cp"
}

voice_asset_sha() {
  # 与 DOUBAO_SAY_TAG 严格对应。上游换包必须同步这里，否则校验失败即中止。
  case "$1" in
    cpython-311) printf '%s' "$DOUBAO_SAY_SHA_311" ;;
    cpython-312) printf '%s' "$DOUBAO_SAY_SHA_312" ;;
    cpython-313) printf '%s' "$DOUBAO_SAY_SHA_313" ;;
    cpython-314) printf '%s' "$DOUBAO_SAY_SHA_314" ;;
    *) printf '' ;;
  esac
}

install_voice() {
  step "3/6 语音输入 · 环境检测"

  command -v python3 >/dev/null || die "未找到 python3，无法确定 Doubao Say 运行时版本"

  local cp
  cp="$(python3 -c 'import sys; print("cpython-%d%d" % sys.version_info[:2])')"
  local sha; sha="$(voice_asset_sha "$cp")"
  if [[ -z "$sha" ]]; then
    die "上游 $DOUBAO_SAY_TAG 没有为 $cp 提供离线包。
     已支持: cpython-311 / 312 / 313 / 314
     当前系统: $cp（$(python3 --version 2>&1)）
     可安装匹配版本后重试，或用 pyenv/mise 切换，或加 --no-voice 跳过语音部分。"
  fi
  ok "运行时 $cp，对应离线包已支持"

  step "3/6 语音输入 · 下载并校验离线包"
  local asset; asset="$(voice_asset_name "$DOUBAO_SAY_TAG" "$cp")"
  local url="https://github.com/$DOUBAO_SAY_REPO/releases/download/$DOUBAO_SAY_TAG/$asset"
  local archive="$STATE_ROOT/downloads/$asset"
  dl_verified "$url" "$sha" "$archive" "Doubao Say $DOUBAO_SAY_TAG"

  step "3/6 语音输入 · 调用上游安装器"
  local unpack="$STATE_ROOT/doubao-say-$DOUBAO_SAY_TAG"
  if [[ "${MODE:-install}" != "dry-run" ]]; then
    if [[ -d "$unpack" ]]; then
      info "复用已解包目录 $unpack"
    else
      mkdir -p "$unpack"
      tar -xzf "$archive" -C "$unpack" --strip-components=1 \
        || die "解包失败: $archive"
      ok "已解包到 $unpack"
    fi
    if [[ ! -x "$unpack/install.sh" ]]; then
      die "离线包结构异常：缺少 install.sh。上游打包格式可能已变更。"
    fi
  fi

  # 已有安装则先把它归档，而不是让上游安装器覆盖掉。
  local installed="$XDG_DATA_HOME/doubao-say/app"
  if [[ -d "$installed" ]]; then
    local ver; ver="$(cat "$installed/VERSION" 2>/dev/null || echo unknown)"
    if [[ "$ver" != "$DOUBAO_SAY_TAG" && "$ver" != "v$DOUBAO_SAY_TAG" && "$ver" != "$DOUBAO_SAY_VERSION" ]]; then
      warn "检测到已装版本 $ver，将升级到 $DOUBAO_SAY_TAG（旧版由上游安装器备份）"
    else
      ok "已安装同版本，交给上游安装器做幂等处理"
    fi
  fi

  run bash "$unpack/install.sh" --yes
  ok "Doubao Say 安装完成"

  step "3/6 语音输入 · 注册 systemd 用户服务"
  install_voice_service
}

# install_voice_service —— 上游不提供 systemd 单元，由本仓库补上
install_voice_service() {
  local unit_dir="$XDG_CONFIG_HOME/systemd/user"
  local unit="$unit_dir/doubao-say.service"
  local src="$REPO_ROOT/assets/systemd/doubao-say.service"

  if [[ "${MODE:-install}" == "dry-run" ]]; then
    printf '  %s[dry-run]%s 安装 %s 并 enable --now\n' "$C_DIM" "$C_RST" "$unit"
    return 0
  fi

  mkdir -p "$unit_dir"
  if [[ -f "$unit" ]] && cmp -s "$src" "$unit"; then
    ok "systemd 单元已是最新"
  else
    local bak=""; [[ -f "$unit" ]] && bak="$(backup_file "$unit")"
    install -Dm644 "$src" "$unit"
    ledger_add "write" "$unit" "${bak:--}" "doubao-say.service"
    ok "已安装 $unit"
  fi

  enable_user_service doubao-say.service

  warn "若在 Doubao Say 设置里同时开启「开机自启」，会与 systemd 服务重复启动"
  warn "二选一即可；本仓库统一用 systemd 管理"
}
