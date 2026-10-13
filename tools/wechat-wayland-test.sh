#!/bin/bash
# ============================================================================
# wechat-wayland-test.sh —— 微信 Wayland 原生启动测试（**非替换方案**）
#
# 目的：验证「候选窗在微信中黑屏」是否由 XWayland + Hyprland
#       `xwayland:force_zero_scaling=true` 的双坐标空间引起。
#
# 做法：在原有启动方式上**只多一个** CEF 图形后端开关：
#           --ozone-platform=wayland
#       让微信走 Wayland 原生，从而与 fcitx5 候选窗（Wayland 原生 popup）处于
#       同一个坐标/缩放空间。
#
# ⚠️ 本脚本**不修改** `~/.local/bin/wechat`。原启动器保持原样，可随时回退到它。
# ⚠️ 若微信在本模式下无法启动或表现异常，直接用原 `wechat` 启动器即可，无副作用。
#
# 用法：
#   bash wechat-wayland-test.sh            # 以 Wayland 原生后端启动微信
#   bash wechat-wayland-test.sh -r         # 先清理残留进程再启动
#
# 对照：先在本脚本下输入拼音看候选窗是否正常可读；
#       若正常 → 根因确认为 XWayland 坐标空间错配，可考虑把开关并入正式启动器；
#       若仍黑屏 → 排除该假设，转向 force_zero_scaling 或更换候选窗前端。
# ============================================================================
set -uo pipefail

if [[ "${1:-}" == "-r" || "${1:-}" == "--restart" || "${1:-}" == "-f" ]]; then
  pkill -9 -x wechat 2>/dev/null || true
  pkill -9 -f "/opt/wechat" 2>/dev/null || true
  sleep 0.5
  shift
fi

# 清理无引用的陈旧单例锁（与原启动器一致的做法）
if [[ -f "$HOME/.xwechat/lock/lock.ini" ]]; then
  if ! fuser "$HOME/.xwechat/lock/lock.ini" >/dev/null 2>&1; then
    rm -f "$HOME/.xwechat/lock/lock.ini" 2>/dev/null || true
  fi
fi

# Fcitx5 输入法环境
export XMODIFIERS=@im=fcitx

echo "[wayland-test] 启动微信：--ozone-platform=wayland（原启动器未被修改）" >&2
exec /opt/wechat/wechat --ozone-platform=wayland "$@"
