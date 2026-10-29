#!/usr/bin/env bash
# ==============================================================================
# doubao-linux · 在线自举安装（一条命令）
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/dunova/doubao-linux/master/bootstrap.sh)
#
# 这个文件只做三件事：取回对应版本的仓库、校验、把控制权交给 install.sh。
# 真正的安装逻辑全在 install.sh 里，这里不重复实现任何东西。
#
# 环境变量：
#   DOUBAO_VERSION     装哪个版本（默认见下方 VERSION）
#   DOUBAO_SRC_DIR     仓库落地位置（默认 ~/.local/share/doubao-linux/src）
#
# 传给本脚本的参数会原样转给 install.sh，例如 --no-voice。
# ==============================================================================
set -uo pipefail

VERSION="${DOUBAO_VERSION:-2.1.0}"
REPO="${DOUBAO_REPO:-https://github.com/dunova/doubao-linux.git}"
DEST="${DOUBAO_SRC_DIR:-$HOME/.local/share/doubao-linux/src}"

C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_RST=$'\033[0m'
ok()   { printf '  %s✔%s %s\n' "$C_OK" "$C_RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_WARN" "$C_RST" "$*"; }
die()  { printf '  %s✘%s %s\n' "$C_ERR" "$C_RST" "$*" >&2; exit 1; }

printf 'doubao-linux 自举  |  v%s\n' "$VERSION"

# ── 把 stdin 接回终端 ───────────────────────────────────────────────────────
# 用 `curl | bash` 时 stdin 是管道，sudo 读不到密码、上游安装器也没法交互。
# 这里重新绑到 /dev/tty，让后续所有交互恢复正常。
if [[ ! -t 0 ]]; then
  if { exec </dev/tty; } 2>/dev/null; then
    :
  else
    die "当前没有可用的终端，sudo 无法询问密码。
     请改用：bash <(curl -fsSL https://raw.githubusercontent.com/dunova/doubao-linux/master/bootstrap.sh)"
  fi
fi

# ── 前置条件 ────────────────────────────────────────────────────────────────
[[ "$(uname -s)" == "Linux" ]] || die "仅支持 Linux（当前 $(uname -s)）"
(( EUID != 0 )) || die "请以普通用户运行，不要用 sudo 跑本脚本"

missing=()
for c in git curl; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( ${#missing[@]} )); then
  die "缺少必要工具: ${missing[*]}
     安装后重试：sudo pacman -S --needed ${missing[*]}"
fi

# ── 取回仓库 ────────────────────────────────────────────────────────────────
TAG="v$VERSION"

# 统一走 fetch + 解引用 checkout：annotated tag 直接 checkout 会刷一屏
# detached HEAD 提示和一个"不是一个提交"的警告，对用户是纯噪音。
if [[ ! -d "$DEST/.git" ]]; then
  mkdir -p "$DEST" || die "无法创建 $DEST"
  git init -q "$DEST" || die "初始化 git 仓库失败: $DEST"
  git -C "$DEST" remote add origin "$REPO" || die "添加远端失败"
else
  ok "复用已有目录 $DEST"
  # 远端地址可能变过（例如 fork），对齐一次
  git -C "$DEST" remote set-url origin "$REPO" 2>/dev/null || true
fi

git -C "$DEST" fetch --quiet --depth 1 origin "+refs/tags/$TAG:refs/tags/$TAG" 2>/dev/null \
  || die "无法获取 $TAG。检查网络，或确认该版本是否存在：
     https://github.com/dunova/doubao-linux/releases"

SHA="$(git -C "$DEST" rev-parse --verify "$TAG^{commit}" 2>/dev/null)" \
  || die "无法解析 $TAG 指向的提交"
git -C "$DEST" -c advice.detachedHead=false checkout --quiet "$SHA" \
  || die "切换到 $TAG 失败"

ok "仓库就位 $DEST ($TAG)"

# 确认拿到的确实是这个 tag，而不是同名分支
HEAD_TAG="$(git -C "$DEST" describe --tags --exact-match 2>/dev/null || true)"
[[ "$HEAD_TAG" == "$TAG" ]] || warn "当前 checkout 不是精确的 $TAG（得到 ${HEAD_TAG:-未知}），继续但请留意"

[[ -x "$DEST/install.sh" ]] || die "仓库结构异常：install.sh 缺失或不可执行"

# ── 交给 install.sh ─────────────────────────────────────────────────────────
printf '  %s→%s 开始安装（后续步骤由 install.sh 负责）\n\n' "$C_OK" "$C_RST"
exec bash "$DEST/install.sh" "$@"
