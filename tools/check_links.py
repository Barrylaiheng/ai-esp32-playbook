#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Minimal docs lint: verify every relative link in Markdown actually exists.

Keeps the repo honest as it grows -- a renamed doc should fail CI, not silently
break a reader. Deliberately dependency-free (stdlib only).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINK_RE = re.compile(r"(!?)\[[^\]]*\]\(([^)]+)\)")
# fenced code blocks are skipped: they legitimately contain placeholder paths
FENCE_RE = re.compile(r"^\s*(```|~~~)")


def iter_markdown():
    for p in sorted(ROOT.rglob("*.md")):
        if ".git" in p.parts or "node_modules" in p.parts:
            continue
        yield p


def check_file(path: Path) -> list[str]:
    errors: list[str] = []
    in_fence = False
    for lineno, line in enumerate(
        path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
    ):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for _, target in LINK_RE.findall(line):
            target = target.strip().split()[0] if target.strip() else target
            if not target or target.startswith(
                ("http://", "https://", "#", "mailto:", "tel:")
            ):
                continue
            local = target.split("#")[0].split("?")[0]
            if not local:
                continue
            if not (path.parent / local).exists():
                errors.append(f"{path.relative_to(ROOT)}:{lineno} -> missing {target}")
    return errors


def main() -> int:
    errors: list[str] = []
    for md in iter_markdown():
        # links in README.en.md resolve relative to repo root regardless of mood
        errors.extend(check_file(md))
    if errors:
        print("Broken relative links:")
        for e in errors:
            print("  -", e)
        return 1
    print(f"OK: links checked in {len(list(iter_markdown()))} markdown files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
