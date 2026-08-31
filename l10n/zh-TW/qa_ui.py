#!/usr/bin/env python3
"""UI 譯文抽樣驗收：核對 Key、簡體、巨集、英文殘留。"""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXT = ROOT / "Assets" / "StreamingAssets" / "Text"
MASTER = TEXT / "Master Localization CSV Files"

SIMPLIFIED_CHARS = "信息里面设置屏幕程序默认请点击打开关闭确定扫描组"
# 上面部分是簡繁都可能出現的字；改用明確簡體差異
SIMPLIFIED_MARKERS = [
    "信息", "里面", "設置" if False else "设置", "屏幕", "默认", "文件", "扫描",
    "游戏", "菜单", "选择", "加载", "保存", "开启", "关闭", "鼠标", "视频",
    "质量", "高级", "角色", "任务", "装备",
]
# 「文件」在臺灣有時也用，降級為警告而非失敗

FAIL_MARKERS = ["信息", "里面", "设置", "屏幕", "默认", "游戏", "菜单", "选择", "加载", "保存", "鼠标", "视频", "质量"]
WARN_MARKERS = ["文件", "开启", "关闭", "角色", "任务", "装备", "高级"]

MACRO_RE = re.compile(r"%[A-Za-z0-9]+")
CJK_RE = re.compile(r"[\u4e00-\u9fff]")
LATIN_WORD_RE = re.compile(r"[A-Za-z]{3,}")

KEEP_ENGLISH = {
    "Daggerfall Unity", "SDF", "FPS", "HUD", "GUI", "OK", "BSA", "VID", "arena2",
    "TEXTURE", "ARCH3D", "BLOCKS", "MAPS", "WOODS", "DAGGER", "settings.ini",
}


def parse_schema_txt(path: Path) -> list[tuple[str, str]]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("-") or s.startswith("schema:"):
            continue
        if "," not in s:
            continue
        key, val = s.split(",", 1)
        rows.append((key.strip(), val.strip()))
    return rows


def parse_csv(path: Path) -> list[tuple[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        return [(row.get("Key") or "", row.get("Value") or "") for row in reader]


def macros(text: str) -> list[str]:
    return MACRO_RE.findall(text)


def report_file(label: str, translated: list[tuple[str, str]], original: list[tuple[str, str]] | None = None) -> dict:
    orig_map = {k: v for k, v in (original or [])}
    orig_keys = [k for k, _ in (original or translated)]
    trans_keys = [k for k, _ in translated]
    issues = []
    stats = {
        "label": label,
        "entries": len(translated),
        "with_cjk": 0,
        "no_cjk_player_text": [],
        "simplified": [],
        "warn_cn": [],
        "macro_mismatch": [],
        "key_mismatch": trans_keys != orig_keys if original else False,
    }
    if original and trans_keys != orig_keys:
        issues.append(f"KEY 不一致：orig={len(orig_keys)} trans={len(trans_keys)}")
    for key, val in translated:
        if CJK_RE.search(val):
            stats["with_cjk"] += 1
        else:
            if LATIN_WORD_RE.search(val) and val not in {"OK", "HUD", "GUI", "FPS"}:
                if not re.fullmatch(r"[A-Za-z0-9 ._\-:/\\]+", val or ""):
                    stats["no_cjk_player_text"].append((key, val[:80]))
                elif len(val.split()) >= 2 and not any(tok in val for tok in KEEP_ENGLISH):
                    stats["no_cjk_player_text"].append((key, val[:80]))
        for m in FAIL_MARKERS:
            if m in val:
                stats["simplified"].append((key, m, val[:80]))
                break
        for m in WARN_MARKERS:
            if m in val:
                stats["warn_cn"].append((key, m, val[:80]))
                break
        if key in orig_map:
            a, b = sorted(macros(orig_map[key])), sorted(macros(val))
            if a != b:
                stats["macro_mismatch"].append((key, a, b))
    return stats


def print_stats(stats: dict) -> None:
    print(f"\n== {stats['label']} ==")
    print(f"entries={stats['entries']} with_cjk={stats['with_cjk']} key_mismatch={stats['key_mismatch']}")
    print(f"simplified={len(stats['simplified'])} warn_cn={len(stats['warn_cn'])} "
          f"macro_mismatch={len(stats['macro_mismatch'])} leftover_en={len(stats['no_cjk_player_text'])}")
    for bucket in ("simplified", "macro_mismatch", "no_cjk_player_text"):
        rows = stats[bucket][:12]
        if rows:
            print(f"  sample {bucket}:")
            for row in rows:
                print(f"    {row}")


def main() -> None:
    files = [
        ("MainMenu.txt", parse_schema_txt, None),
        ("GameSettings.txt", parse_schema_txt, None),
        ("ModSystem.txt", parse_schema_txt, None),
        ("Internal_Settings.csv", parse_csv, MASTER / "Internal_Settings.csv"),
        ("Internal_Strings.csv", parse_csv, MASTER / "Internal_Strings.csv"),
    ]
    all_stats = []
    for name, parser, master in files:
        path = TEXT / name
        translated = parser(path)
        original = parser(master) if master else None
        if original is None and name.endswith(".txt"):
            # 與 git HEAD 比不了時，至少自檢譯文
            original = None
        stats = report_file(name, translated, original)
        print_stats(stats)
        all_stats.append(stats)

    fail = any(
        s["key_mismatch"] or s["simplified"] or s["macro_mismatch"]
        for s in all_stats
    )
    cjk_ratio = sum(s["with_cjk"] for s in all_stats) / max(1, sum(s["entries"] for s in all_stats))
    print(f"\nCJK coverage={cjk_ratio:.1%} FAIL={fail}")
    raise SystemExit(1 if fail else 0)


if __name__ == "__main__":
    main()
