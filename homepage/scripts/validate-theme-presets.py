#!/usr/bin/env python3
"""Validate palette variables used by the non-Dracula Homepage presets."""

from __future__ import annotations

import re
import sys
from pathlib import Path


COLOR_RE = re.compile(r"--(hp-[\w-]+):\s*([^;]+);")


def parse_color(value: str) -> tuple[float, float, float, float]:
    value = value.strip()
    if value.startswith("#"):
        raw = value[1:]
        if len(raw) == 3:
            raw = "".join(char * 2 for char in raw)
        if len(raw) != 6:
            raise ValueError(value)
        return tuple(int(raw[index : index + 2], 16) / 255 for index in (0, 2, 4)) + (1.0,)

    match = re.fullmatch(r"rgba?\(([^)]+)\)", value)
    if match:
        parts = [part.strip() for part in match.group(1).split(",")]
        if len(parts) not in (3, 4):
            raise ValueError(value)
        alpha = float(parts[3]) if len(parts) == 4 else 1.0
        return tuple(float(part) / 255 for part in parts[:3]) + (alpha,)

    raise ValueError(value)


def blend(foreground: tuple[float, float, float, float], background: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    alpha = foreground[3]
    return tuple(foreground[index] * alpha + background[index] * (1 - alpha) for index in range(3)) + (1.0,)


def luminance(color: tuple[float, float, float, float]) -> float:
    channels = []
    for channel in color[:3]:
        channels.append(channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4)
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def contrast(first: tuple[float, float, float, float], second: tuple[float, float, float, float]) -> float:
    bright, dark = sorted((luminance(first), luminance(second)), reverse=True)
    return (bright + 0.05) / (dark + 0.05)


def main() -> int:
    root = Path(__file__).resolve().parents[1] / "config-template" / "themes"
    failures: list[str] = []
    checked = 0
    for css_path in sorted(root.glob("*/theme.css")):
        values = dict(COLOR_RE.findall(css_path.read_text()))
        required = {"hp-page-bg", "hp-surface", "hp-text", "hp-muted", "hp-heading", "hp-accent"}
        missing = required - values.keys()
        if missing:
            failures.append(f"{css_path.parent.name}: missing {', '.join(sorted(missing))}")
            continue
        try:
            page = parse_color(values["hp-page-bg"])
            surface = blend(parse_color(values["hp-surface"]), page)
            checks = {
                "text/surface": (contrast(parse_color(values["hp-text"]), surface), 4.5),
                "muted/surface": (contrast(parse_color(values["hp-muted"]), surface), 3.0),
                "heading/page": (contrast(parse_color(values["hp-heading"]), page), 3.0),
                "accent/surface": (contrast(parse_color(values["hp-accent"]), surface), 3.0),
            }
        except ValueError as exc:
            failures.append(f"{css_path.parent.name}: invalid color {exc}")
            continue
        checked += 1
        for label, (actual, minimum) in checks.items():
            if actual < minimum:
                failures.append(f"{css_path.parent.name}: {label} contrast {actual:.2f} < {minimum:.2f}")
        print(f"ok contrast {css_path.parent.name}")

    if failures:
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1
    if checked == 0:
        print("error: no theme palettes checked", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
