#!/usr/bin/env python3
"""Wrap the menu-bar artwork as a custom symbol for WidgetKit controls.

Run after changing Resources/MenuBarIcon.svg; commit the generated symbol.
Controls require a symbol asset rather than a plain PDF or SVG image.
The artwork is optically enlarged by 40% around its original centre to match
the adjacent Control Center symbols; font baseline/capline metrics stay fixed.
"""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
source = ET.parse(root / "Resources/MenuBarIcon.svg").getroot()
paths = list(source)
styles = []
glyphs = []
for index, path in enumerate(paths):
    opacity = path.get("opacity", "1")
    styles.append(f".monochrome-{index} {{fill:#000000;opacity:{opacity}}}")
    styles.append(f".hierarchical-{index}:primary {{fill:#000000;opacity:{opacity}}}")
    glyphs.append(f'      <path class="monochrome-{index} hierarchical-{index}:primary" d="{path.attrib["d"]}"/>')

catalog = root / "Resources/Control/Assets.xcassets"
symbol = catalog / "DuotletControlIcon.symbolset"
symbol.mkdir(parents=True, exist_ok=True)
(catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
(symbol / "Contents.json").write_text(json.dumps({
    "info": {"author": "xcode", "version": 1},
    "symbols": [{"filename": "DuotletControlIcon.svg", "idiom": "universal"}],
}, indent=2) + "\n")
(symbol / "DuotletControlIcon.svg").write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!-- Generated from Resources/MenuBarIcon.svg by scripts/generate-control-icon.py. -->
<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="3300" height="2200">
  <style>''' + "\n".join(styles) + '''</style>
  <g id="Guides">
    <line id="Baseline-S" x1="263" x2="3036" y1="696" y2="696"/>
    <line id="Capline-S" x1="263" x2="3036" y1="625.54" y2="625.54"/>
    <line id="Baseline-M" x1="263" x2="3036" y1="1126" y2="1126"/>
    <line id="Capline-M" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
    <line id="Baseline-L" x1="263" x2="3036" y1="1556" y2="1556"/>
    <line id="Capline-L" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
    <line id="left-margin-Regular-M" x1="1382" x2="1382" y1="1030" y2="1140"/>
    <line id="right-margin-Regular-M" x1="1508" x2="1508" y1="1030" y2="1140"/>
  </g>
  <g id="Symbols">
    <g id="Regular-M" transform="matrix(6.3 0 0 6.3 1381.76 1028.1)">
''' + "\n".join(glyphs) + '''
    </g>
  </g>
</svg>
''')
