"""Derive public identity assets from the official SVG; no paths or colors are redrawn.

SVGs use the standard library. --raster uses Playwright 1.61.0 and installed Chrome
to render the social PNG. --check verifies SVG outputs without a browser.
"""
import argparse
import copy
import importlib.metadata
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "app/assets/branding/openrc-official.svg"
DEST = ROOT / "site/assets/branding"
NS = "{http://www.w3.org/2000/svg}"
ET.register_namespace("", NS[1:-1])


def svg(viewbox, width, height, groups, background=False):
    root = ET.Element(NS + "svg", {"viewBox": viewbox, "width": str(width), "height": str(height)})
    ET.SubElement(root, NS + "title").text = "OpenRC Simulator ALPHA"
    if background:
        x, y, w, h = viewbox.split()
        ET.SubElement(root, NS + "rect", {"x": x, "y": y, "width": w, "height": h, "fill": "#080808"})
    for group in groups:
        root.append(copy.deepcopy(group))
    return ET.tostring(root, encoding="unicode") + "\n"


def outputs():
    groups = ET.parse(SOURCE).getroot().findall(NS + "g")
    return {
        DEST / "openrc-logo.svg": svg("95 293 1505 327", 1505, 327, groups),
        DEST / "openrc-banner.svg": svg("-5 223 1705 467", 1705, 467, groups, True),
        DEST / "openrc-social.svg": svg("-75 -28 1845 969", 1200, 630, groups, True),
        ROOT / "site/favicon.svg": svg("784 203 410 410", 64, 64,
                                       [g for g in groups if g.get("id") in ("R", "C")], True),
    }


def raster():
    from playwright.sync_api import sync_playwright
    if importlib.metadata.version("playwright") != "1.61.0":
        raise SystemExit("Use Playwright==1.61.0 for the optional PNG renderer")
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="chrome", headless=True)
        page = browser.new_page(viewport={"width": 1200, "height": 630}, device_scale_factor=1)
        page.goto((DEST / "openrc-social.svg").as_uri())
        page.screenshot(path=str(DEST / "openrc-social.png"))
        browser.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--raster", action="store_true")
    args = parser.parse_args()
    for path, content in outputs().items():
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                raise SystemExit(f"Stale branding: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if args.raster:
        raster()
    print("Public branding verified" if args.check else "Public branding generated")
