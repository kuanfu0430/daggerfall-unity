#!/usr/bin/env python3
"""全量譯文驗收：Key、巨集、簡體、覆蓋率。"""
from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXT = ROOT / "Assets" / "StreamingAssets" / "Text"
MASTER = TEXT / "Master Localization CSV Files"
BIOG = ROOT / "Assets" / "StreamingAssets" / "BIOGs"
BOOKS = TEXT / "Books"
QUESTS = TEXT / "Quests"

FAIL_MARKERS = ["信息", "里面", "设置", "屏幕", "默认", "游戏", "菜单", "选择", "加载", "保存", "鼠标", "视频", "质量"]
MACRO_RE = re.compile(r"%[A-Za-z][A-Za-z0-9]*")
MARKUP_RE = re.compile(r"\[/[^\]]*\]")
CJK_RE = re.compile(r"[\u4e00-\u9fff]")


def parse_csv(path: Path) -> list[tuple[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        return [(row.get("Key") or "", row.get("Value") or "") for row in csv.DictReader(f)]


def macros(text: str) -> list[str]:
    return MACRO_RE.findall(text or "")


def markups(text: str) -> list[str]:
    return MARKUP_RE.findall(text or "")


def csv_report(name: str) -> dict:
    trans = parse_csv(TEXT / name)
    orig = parse_csv(MASTER / name)
    orig_map = {k: v for k, v in orig}
    trans_keys = [k for k, _ in trans]
    orig_keys = [k for k, _ in orig]
    simplified, macro_bad, markup_bad, cjk = [], [], [], 0
    for k, v in trans:
        if CJK_RE.search(v):
            cjk += 1
        for m in FAIL_MARKERS:
            if m in v:
                simplified.append((k, m))
                break
        if k in orig_map:
            if sorted(macros(orig_map[k])) != sorted(macros(v)):
                macro_bad.append(k)
            if sorted(markups(orig_map[k])) != sorted(markups(v)):
                markup_bad.append(k)
    return {
        "name": name,
        "entries": len(trans),
        "key_ok": trans_keys == orig_keys,
        "cjk": cjk,
        "simplified": len(simplified),
        "macro_bad": len(macro_bad),
        "markup_bad": len(markup_bad),
        "sample_simplified": simplified[:8],
        "sample_macro": macro_bad[:8],
    }


def file_cjk_ratio(path: Path) -> tuple[int, int]:
    text = path.read_text(encoding="utf-8", errors="replace")
    # player-ish lines: skip codes
    lines = [ln for ln in text.splitlines() if ln.strip()]
    hit = sum(1 for ln in lines if CJK_RE.search(ln))
    return hit, len(lines)


def glob_ratio(files: list[Path]) -> dict:
    done = 0
    total = 0
    empty = []
    for p in files:
        hit, n = file_cjk_ratio(p)
        total += 1
        if hit > 0:
            done += 1
        else:
            empty.append(p.name)
    return {"files": total, "with_cjk": done, "none": empty[:20], "none_count": len(empty)}


def main() -> None:
    csvs = [
        "Internal_RSC.csv", "Internal_Items.csv", "Internal_MagicItems.csv",
        "Internal_Spells.csv", "Internal_Factions.csv", "Internal_Flats.csv",
        "Internal_Locations.csv", "Example_MageLight.csv",
        "Internal_Strings.csv", "Internal_Settings.csv",
    ]
    print("=== CSV ===")
    fail = False
    for name in csvs:
        if not (TEXT / name).exists():
            print(f"MISSING {name}")
            fail = True
            continue
        r = csv_report(name)
        print(
            f"{r['name']}: n={r['entries']} key_ok={r['key_ok']} cjk={r['cjk']} "
            f"simp={r['simplified']} macro={r['macro_bad']} markup={r['markup_bad']}"
        )
        if r["sample_simplified"]:
            print("  simp", r["sample_simplified"])
        if r["sample_macro"]:
            print("  macro", r["sample_macro"])
        if (not r["key_ok"]) or r["simplified"] or r["macro_bad"]:
            fail = True

    books = sorted(BOOKS.glob("BOK*-LOC.txt"))
    quests = sorted(QUESTS.glob("*-LOC.txt"))
    biogs = sorted(BIOG.glob("BIOG*.TXT"))
    print("\n=== FILES ===")
    for label, files in [("books", books), ("quests", quests), ("biogs", biogs)]:
        r = glob_ratio(files)
        print(f"{label}: {r['with_cjk']}/{r['files']} have CJK  none={r['none_count']} sample={r['none'][:8]}")

    print("\nFAIL" if fail else "\nCSV_STRUCT_OK")


if __name__ == "__main__":
    main()
