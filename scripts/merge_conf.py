#!/usr/bin/env python3
"""键级合并 Fcitx5 配置与 Doubao Say 设置。

存在的意义：外观调优只该改动我们关心的那几个键，其余键、注释、顺序、
用户自己的节都必须原样保留。任何"整文件覆盖"都会把用户手工调过的配置抹掉。

用法：
    merge_conf.py ini  <目标文件> <patch.ini> [--dry-run]
    merge_conf.py json <目标文件> <key=value>...  [--dry-run]

退出码：0 有变更或无需变更；1 出错。
"""
from __future__ import annotations

import json
import pathlib
import shutil
import sys


def parse_patch(path: pathlib.Path) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("["):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        pairs.append((k.strip(), v.strip()))
    return pairs


def merge_ini(target: pathlib.Path, pairs: list[tuple[str, str]], dry: bool) -> int:
    """只改顶层键（第一个 [section] 之前）；节内同名键不碰。"""
    text = target.read_text(encoding="utf-8") if target.exists() else ""
    lines = text.splitlines()

    # 顶层区域的结束位置 = 第一个节标题的行号
    top_end = len(lines)
    for i, line in enumerate(lines):
        if line.lstrip().startswith("["):
            top_end = i
            break

    wanted = dict(pairs)
    changed: list[str] = []
    seen: set[str] = set()

    for i in range(top_end):
        line = lines[i]
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        k = stripped.split("=", 1)[0].strip()
        if k in wanted:
            new = f"{k}={wanted[k]}"
            if line.rstrip() != new:
                changed.append(f"{k}: {line.strip()} -> {new}")
                lines[i] = new
            seen.add(k)

    # 未出现过的键，插到顶层末尾（节标题之前），保持原有的空行布局
    missing = [(k, v) for k, v in pairs if k not in seen]
    if missing:
        insert_at = top_end
        while insert_at > 0 and not lines[insert_at - 1].strip():
            insert_at -= 1
        block = [f"{k}={v}" for k, v in missing]
        lines[insert_at:insert_at] = block
        changed.extend(f"{k}: (新增) -> {k}={v}" for k, v in missing)

    if not changed:
        print("  · 无需变更")
        return 0

    for c in changed:
        print(f"  · {c}")
    if not dry:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


def merge_json(target: pathlib.Path, assignments: list[tuple[str, object]], dry: bool) -> int:
    data = {}
    if target.exists():
        try:
            data = json.loads(target.read_text(encoding="utf-8") or "{}")
        except json.JSONDecodeError:
            print(f"  ! {target} 不是合法 JSON，拒绝改写", file=sys.stderr)
            return 1

    changed = []
    for key, value in assignments:
        if data.get(key) != value:
            changed.append(f"{key}: {data.get(key)!r} -> {value!r}")
            data[key] = value

    if not changed:
        print("  · 无需变更")
        return 0

    for c in changed:
        print(f"  · {c}")
    if not dry:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    return 0


def coerce(raw: str):
    """把命令行值解析成 JSON 类型，允许 true/false/数字/字符串。"""
    low = raw.lower()
    if low in ("true", "false"):
        return low == "true"
    if low in ("null", "none"):
        return None
    try:
        return int(raw)
    except ValueError:
        pass
    try:
        return float(raw)
    except ValueError:
        pass
    return raw


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 1

    mode, target_arg = argv[1], argv[2]
    rest = argv[3:]
    dry = "--dry-run" in rest
    rest = [a for a in rest if a != "--dry-run"]
    target = pathlib.Path(target_arg).expanduser()

    if mode == "ini":
        patch = pathlib.Path(rest[0]).expanduser()
        if not patch.exists():
            print(f"  ! 找不到 patch 文件 {patch}", file=sys.stderr)
            return 1
        return merge_ini(target, parse_patch(patch), dry)

    if mode == "json":
        assignments = []
        for item in rest:
            if "=" not in item:
                print(f"  ! 参数格式应为 key=value: {item}", file=sys.stderr)
                return 1
            k, v = item.split("=", 1)
            assignments.append((k.strip(), coerce(v.strip())))
        return merge_json(target, assignments, dry)

    print(f"未知模式: {mode}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
