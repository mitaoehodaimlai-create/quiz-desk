#!/usr/bin/env python3
"""Build one quiz page per group from the template.

Each group is published as its own claude.ai Artifact, so it gets its own link
and its own database. Usage:

    python3 scripts/build_groups.py A B C        # writes dist/quiz-group-a.html ...
    python3 scripts/build_groups.py D --limit 40 # a larger group
"""
import argparse
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "src" / "quiz-desk.template.html"
DIST = ROOT / "dist"


def build(group: str, limit: int) -> pathlib.Path:
    html = TEMPLATE.read_text(encoding="utf-8")
    html = html.replace("name: '__GROUP__', limit: 30", f"name: 'Group {group}', limit: {limit}")
    html = html.replace("<title>Quiz Desk</title>", f"<title>Quiz Desk Group {group}</title>", 1)
    out = DIST / f"quiz-group-{group.lower()}.html"
    out.write_text(html, encoding="utf-8")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("groups", nargs="+", help="group letters or names, e.g. A B C")
    ap.add_argument("--limit", type=int, default=30, help="students per group (default 30)")
    args = ap.parse_args()
    DIST.mkdir(exist_ok=True)
    for g in args.groups:
        if not re.fullmatch(r"[A-Za-z0-9]{1,12}", g):
            raise SystemExit(f"Group name {g!r} must be letters or digits only.")
        print("wrote", build(g.upper(), args.limit).relative_to(ROOT))


if __name__ == "__main__":
    main()
