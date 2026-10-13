#!/usr/bin/env bash
# doubao-linux · 端到端验证（真机组件 + Fcitx 侧 + 性能抽样）
set -uo pipefail
SRC="${DOUBAO_SRC:-$HOME/src/doubao-ime-linux}"
SERVICE="doubao-keyboard.service"
C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
pass=0; fail=0
chk() { if [[ "$2" == "1" ]]; then printf '  %sPASS%s %s\n' "$C_OK" "$C_RST" "$1"; pass=$((pass+1));
        else printf '  %sFAIL%s %s%s\n' "$C_ERR" "$C_RST" "$1" "${3:+  ← $3}"; fail=$((fail+1)); fi; }

printf 'doubao-linux 端到端验证  |  %s\n\n' "$(date '+%F %T')"

printf '%s══ 1. 服务与集成 ══%s\n' "$C_DIM" "$C_RST"
[[ "$(systemctl --user is-active $SERVICE)" == "active" ]] && chk "doubao-keyboard.service active" 1 || chk "doubao-keyboard.service active" 0 "服务未运行，先跑 install.sh"

if [[ -d "$SRC" ]]; then
  echo "  ${C_DIM}停止服务以跑隔离测试…${C_RST}"
  systemctl --user stop $SERVICE >/dev/null 2>&1; sleep 2
  # 等 wineserver 退净，并清掉上一次遗留的 socket：
  # 上游测试的等待循环只检查 socket 文件是否存在，陈旧文件会让它连到已关闭的
  # 监听端并报 ConnectionRefused（看起来像引擎失败，其实是残留）。
  for _ in $(seq 1 20); do pgrep -x wineserver >/dev/null || break; sleep 0.5; done
  rm -f "$SRC/work/keyboard-test.sock"
  OUT=$( cd "$SRC" && timeout 300 python3 scripts/headless.py --prefix keyboard -- python3 tests/integration_keyboard.py 2>&1 )
  echo "$OUT" | grep -q 'official candidates include 你好' \
    && chk "官方引擎返回候选（含「你好」）" 1 || chk "官方引擎返回候选（含「你好」）" 0 "$(echo "$OUT" | tail -3 | tr '\n' ' ')"
  N=$(echo "$OUT" | grep -c '^PASS')
  (( N >= 11 )) && chk "集成测试通过项 ≥ 11（实得 $N）" 1 || chk "集成测试通过项 ≥ 11（实得 $N）" 0
  systemctl --user start $SERVICE >/dev/null 2>&1; sleep 5
else
  chk "找到源码目录 $SRC" 0
fi

printf '\n%s══ 2. Fcitx 侧 ══%s\n' "$C_DIM" "$C_RST"
[[ "$(systemctl --user is-active omarchy-fcitx5.service 2>/dev/null)" == "active" ]] \
  && chk "omarchy-fcitx5.service active" 1 || chk "omarchy-fcitx5.service active" 0
grep -qi 'doubao' "$HOME/.config/fcitx5/profile" 2>/dev/null \
  && chk "profile 中有 doubao 引擎槽" 1 || chk "profile 中有 doubao 引擎槽" 0
CUR=$(timeout 5 fcitx5-remote -s doubao >/dev/null 2>&1; sleep 1; timeout 5 fcitx5-remote -n 2>&1)
[[ "$CUR" == "doubao" ]] && chk "可切换到豆包引擎" 1 || chk "可切换到豆包引擎" 0 "当前=$CUR"

printf '\n%s══ 3. 性能抽样 ══%s\n' "$C_DIM" "$C_RST"
python3 - <<'PY'
import json, os, socket, statistics, sys, time
try:
    sys.path.insert(0, os.path.expanduser('~/src/doubao-ime-linux/bridge'))
    from runtime import keyboard_socket
    path = str(keyboard_socket())
    def call(cmd):
        t=time.perf_counter()
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(5); s.connect(path); s.sendall((cmd+'\n').encode())
            d=bytearray()
            while b'\n' not in d:
                c=s.recv(65536)
                if not c: raise RuntimeError('disconnected')
                d.extend(c)
        return json.loads(d), (time.perf_counter()-t)*1000
    call('F')
    lat=[]
    for w in ('nihao','zhongguo','wobuzhidao'):
        call('F')
        for ch in w:
            _,a=call('K %d 0'%ord(ch.upper())); _,b=call('K %d 1'%ord(ch.upper()))
            lat.append(a+b)
    q=sorted(lat)
    print('  按键往返中位 %.1f ms  (min %.1f / p90 %.1f / max %.1f, n=%d)'
          % (statistics.median(q), q[0], q[max(0,int(len(q)*.9)-1)], q[-1], len(q)))
    print('  → 单次事件 ≈ %.2f ms' % (statistics.median(q)/2))
except Exception as e:
    print('  性能抽样失败:', e)
PY

printf '\n%s══ 4. 内存 ══%s\n' "$C_DIM" "$C_RST"
CG=$(systemctl --user show $SERVICE -p ControlGroup --value 2>/dev/null)
[[ -n "$CG" && -r "/sys/fs/cgroup$CG/memory.stat" ]] && \
  awk '/^anon /{printf "  真实匿名内存 %.1f MB\n", $2/1048576}
       /^file /{printf "  页缓存(可回收) %.1f MB\n", $2/1048576}' "/sys/fs/cgroup$CG/memory.stat"

printf '\n════════════════════════════════\n'
if (( fail == 0 )); then printf '%s全部通过：%d 项%s\n' "$C_OK" "$pass" "$C_RST"
else printf '%s通过 %d / 失败 %d%s\n' "$C_ERR" "$pass" "$fail" "$C_RST"; fi
exit $(( fail > 0 ))
