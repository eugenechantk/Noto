#!/usr/bin/env python3
"""Flag platform-forked Swift code that has drifted between iOS and macOS.

Two failure modes, both seen live in this codebase:

  UNPAIRED  a func defined in an `#if os(iOS)` block with no macOS counterpart
            (or vice versa) — how todo markers ended up iOS-only and invisible
            on macOS for as long as they did.

  REDUNDANT a func implemented in BOTH forks whose bodies are identical once
            UIKit/AppKit type names are normalised — duplication with no reason
            to exist, and a standing invitation for one side to be fixed alone.

Usage:
    scripts/check_platform_parity.py [paths...]        # report
    scripts/check_platform_parity.py --strict [paths]  # exit 1 on UNPAIRED
"""
from __future__ import annotations

import difflib
import re
import sys
from pathlib import Path

FUNC_RE = re.compile(
    r"^(\s*)(?:private |fileprivate |public |internal |final |override |@objc |static |class |mutating )*"
    r"func (\w+)"
)

# Types that differ in name only between the two frameworks. Normalising these
# is what reveals "identical" bodies hiding behind UIColor vs NSColor.
PLATFORM_TYPES = (
    "Color", "Font", "View", "Button", "Image", "BezierPath", "EdgeInsets",
    "GraphicsContext", "ScrollView", "TextField", "TextView", "Responder",
    "LayoutConstraint", "StackView", "Event", "Screen", "Window", "ViewController",
)
NORM_RE = re.compile(r"\b(?:UI|NS)(" + "|".join(PLATFORM_TYPES) + r")\b")

# Symbols that are legitimately one-sided. Two groups:
#
#   input concepts that only exist on one platform (touch vs mouse), and
#   framework lifecycle/delegate entry points, which are named differently by
#   UIKit and AppKit and so can never "pair" by name.
#
# Everything NOT matched here is app-authored behaviour, where a missing
# counterpart is a genuine parity risk rather than a framework fact.
EXPECTED_ONE_SIDED = re.compile(
    # platform-specific input & chrome concepts
    r"keyboard|inputAccessory|touch|gesture|tap|swipe|pan|pinch|hover|"
    r"mouse|flagsChanged|dragging|cursor|trackingArea|menuBar|window|"
    r"photoLibrary|scenePhase|safeArea|homeIndicator|traitCollection|"
    r"responderChain|popover|contextMenu|toolbar"
    # UIKit / AppKit lifecycle & delegate entry points
    r"|^(?:load|make|update)(?:UI|NS)View(?:Controller)?$"
    r"|^view(?:DidLoad|DidLayout|WillLayout|DidAppear|WillAppear|DidLayoutSubviews)$"
    r"|^(?:layoutSubviews|didMoveToSuperview|hitTest|draw|drawInterior|drawRect)$"
    r"|^text(?:Did|View|Storage|Should)"
    r"|^control(?:Text)?Did"
    r"|^scrollView(?:Did|Will)",
    re.IGNORECASE,
)


def regions(lines: list[str]) -> list[str | None]:
    """Map each line to the platform fork it sits inside ('ios'/'macos'/'shared')."""
    stack: list[str] = []
    out: list[str | None] = []
    for line in lines:
        s = line.strip()
        if re.match(r"^#if os\(iOS\)", s):
            stack.append("ios"); out.append(None); continue
        if re.match(r"^#if os\(macOS\)", s):
            stack.append("macos"); out.append(None); continue
        if re.match(r"^#elseif os\(macOS\)", s):
            if stack: stack[-1] = "macos"
            out.append(None); continue
        if re.match(r"^#elseif os\(iOS\)", s):
            if stack: stack[-1] = "ios"
            out.append(None); continue
        if re.match(r"^#else\b", s):
            if stack: stack[-1] = "other"
            out.append(None); continue
        if re.match(r"^#endif", s):
            if stack: stack.pop()
            out.append(None); continue
        out.append(stack[-1] if stack else "shared")
    return out


def functions(lines: list[str], region: list[str | None], platform: str) -> dict[str, tuple[int, str]]:
    """Extract {name: (line_number, body)} for funcs inside the given fork."""
    found: dict[str, tuple[int, str]] = {}
    i = 0
    while i < len(lines):
        if region[i] == platform:
            m = FUNC_RE.match(lines[i])
            if m:
                body = [lines[i]]
                depth = lines[i].count("{") - lines[i].count("}")
                j = i + 1
                while j < len(lines) and depth > 0:
                    body.append(lines[j])
                    depth += lines[j].count("{") - lines[j].count("}")
                    j += 1
                found.setdefault(m.group(2), (i + 1, "\n".join(body)))
                i = j
                continue
        i += 1
    return found


def normalise(text: str) -> str:
    text = NORM_RE.sub(r"PLATFORM\1", text)
    return "\n".join(ln.strip() for ln in text.split("\n") if ln.strip())


def audit(path: Path) -> tuple[list[str], list[str]]:
    lines = path.read_text(encoding="utf-8").split("\n")
    region = regions(lines)
    ios = functions(lines, region, "ios")
    mac = functions(lines, region, "macos")

    unpaired: list[str] = []
    redundant: list[str] = []

    for name, (line_no, _) in sorted(ios.items()):
        if name not in mac and not EXPECTED_ONE_SIDED.search(name):
            unpaired.append(f"{path}:{line_no}  UNPAIRED  iOS-only func `{name}` has no macOS counterpart")
    for name, (line_no, _) in sorted(mac.items()):
        if name not in ios and not EXPECTED_ONE_SIDED.search(name):
            unpaired.append(f"{path}:{line_no}  UNPAIRED  macOS-only func `{name}` has no iOS counterpart")

    for name in sorted(set(ios) & set(mac)):
        a, b = normalise(ios[name][1]), normalise(mac[name][1])
        if a == b:
            redundant.append(f"{path}:{ios[name][0]}  REDUNDANT  `{name}` is identical on both platforms — hoist it")
        else:
            ratio = difflib.SequenceMatcher(None, a, b).ratio()
            if ratio > 0.95:
                redundant.append(
                    f"{path}:{ios[name][0]}  REDUNDANT  `{name}` is {ratio:.0%} identical — hoist the common part"
                )
    return unpaired, redundant


def main(argv: list[str]) -> int:
    strict = "--strict" in argv
    args = [a for a in argv if not a.startswith("--")]
    roots = [Path(a) for a in args] or [Path("Noto")]

    files: list[Path] = []
    for root in roots:
        files.extend(sorted(root.rglob("*.swift")) if root.is_dir() else [root])

    all_unpaired: list[str] = []
    all_redundant: list[str] = []
    for f in files:
        u, r = audit(f)
        all_unpaired += u
        all_redundant += r

    if all_unpaired:
        print(f"\n=== UNPAIRED ({len(all_unpaired)}) — a fix on one platform cannot reach the other ===")
        for line in all_unpaired:
            print("  " + line)
    if all_redundant:
        print(f"\n=== REDUNDANT ({len(all_redundant)}) — same code twice, drifts the moment one side changes ===")
        for line in all_redundant:
            print("  " + line)
    if not all_unpaired and not all_redundant:
        print("Platform parity: clean.")

    print(f"\nScanned {len(files)} file(s): {len(all_unpaired)} unpaired, {len(all_redundant)} redundant.")
    return 1 if (strict and all_unpaired) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
