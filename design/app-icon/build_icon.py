#!/usr/bin/env python3
"""Generate the layered Liquid Glass app icon (.icon bundle) for Abbay.

Usage: design/app-icon/build_icon.py Abbay/Resources/AppIcon.icon [--no-gaps]
           [--gradient=painted|auto|none]

--gradient=painted (the shipped icon) draws the original icon's top-to-bottom fade into
the sheet artwork; auto leaves the art flat and asks Icon Composer for its automatic
gradient; none keeps the sheets flat.

Open the result in Icon Composer (bundled with Xcode 26) to tune the glass.
"""
import json
import pathlib
import sys

CANVAS = 1024
GREEN_BACK = "#2F8A47"
GREEN_FRONT = "#4DB856"
GREEN_DISC = "#1F6E3A"
WAVE = "#F2FFF4"
# Sampled from the pre-glass icon: one fade spanning the whole book.
FADE_TOP = "#50B94E"
FADE_BOTTOM = "#125A2E"


def svg(body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">{body}</svg>\n'
    )


def mirror(path_d):
    """Wrap a left-side path so it also renders mirrored on the right."""
    return (
        f'<path d="{path_d}"/>'
        f'<path d="{path_d}" transform="translate({CANVAS} 0) scale(-1 1)"/>'
    )


def sheet_fill(flat, gradient, darken=False):
    """Fill attribute plus any <defs> needed for a sheet layer."""
    if gradient != "painted":
        return f'fill="{flat}"', ""
    top, bottom = ("#43A645", "#0E4D27") if darken else (FADE_TOP, FADE_BOTTOM)
    defs = (
        '<defs><linearGradient id="fade" gradientUnits="userSpaceOnUse" '
        'x1="0" y1="140" x2="0" y2="810">'
        f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>'
        "</linearGradient></defs>"
    )
    return 'fill="url(#fade)"', defs


def back_sheets(gaps, gradient):
    # Outer covers peeking out from behind the front pages.
    inner = 486 if gaps else 512
    d = (
        f"M 205 227 H {inner} V 793 H 205 "
        "Q 165 793 165 753 V 267 Q 165 227 205 227 Z"
    )
    fill, defs = sheet_fill(GREEN_BACK, gradient, darken=True)
    return svg(f"{defs}<g {fill}>{mirror(d)}</g>")


def front_pages(gaps, gradient):
    # Slanted page: left edge x=238, spine edge pushed out/down toward the binding.
    spine = 498 if gaps else 512
    d = (
        f"M 238 182 Q 238 140 280 156 L {spine} 240 V 806 "
        "L 270 712 Q 238 698 238 664 Z"
    )
    fill, defs = sheet_fill(GREEN_FRONT, gradient)
    return svg(f"{defs}<g {fill}>{mirror(d)}</g>")


def badge_disc():
    return svg(f'<circle cx="512" cy="513" r="178" fill="{GREEN_DISC}"/>')


def badge_wave():
    bars = [(426, 37), (467, 60), (512, 86), (557, 60), (598, 37)]
    widths = {37: 12, 60: 13, 86: 15}
    body = "".join(
        f'<ellipse cx="{x}" cy="513" rx="{widths[ry]}" ry="{ry}"/>' for x, ry in bars
    )
    return svg(f'<g fill="{WAVE}">{body}</g>')


def icon_json(gradient):
    # Base colors for Icon Composer's automatic gradient (GREEN_FRONT / GREEN_BACK).
    auto_fills = {
        "front-pages": "display-p3:0.302,0.722,0.337,1.00000",
        "back-sheets": "display-p3:0.184,0.541,0.278,1.00000",
    }

    def layer(n):
        entry = {"name": n, "image-name": f"{n}.svg", "glass": True}
        if gradient == "auto" and n in auto_fills:
            entry["fill"] = {"automatic-gradient": auto_fills[n]}
        return entry

    def group(name, layers, translucency):
        return {
            "name": name,
            "layers": [layer(n) for n in layers],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": translucency},
        }

    return {
        "fill": {
            "linear-gradient": [
                "display-p3:0.231,0.235,0.255,1.00000",
                "display-p3:0.106,0.106,0.118,1.00000",
            ],
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}},
        },
        # Groups are listed front-most first.
        "groups": [
            group("Badge", ["wave", "disc"], 0.3),
            group("Front pages", ["front-pages"], 0.4),
            group("Back sheets", ["back-sheets"], 0.5),
        ],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }


def main():
    out = pathlib.Path(sys.argv[1])
    gaps = "--no-gaps" not in sys.argv
    gradient = next(
        (a.split("=", 1)[1] for a in sys.argv if a.startswith("--gradient=")), "painted"
    )
    assets = out / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "back-sheets.svg").write_text(back_sheets(gaps, gradient))
    (assets / "front-pages.svg").write_text(front_pages(gaps, gradient))
    (assets / "disc.svg").write_text(badge_disc())
    (assets / "wave.svg").write_text(badge_wave())
    (out / "icon.json").write_text(json.dumps(icon_json(gradient), indent=2) + "\n")


if __name__ == "__main__":
    main()
