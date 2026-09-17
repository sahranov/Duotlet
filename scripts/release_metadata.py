#!/usr/bin/env python3
"""Validate a stable release before building or making it the latest update."""
import argparse
import json
import plistlib
import re
from pathlib import Path


def version_tuple(version):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("Use a stable version such as 0.3.0 (no v prefix or prerelease suffix)")
    parts = tuple(map(int, version.split(".")))
    if parts[0] > 9999 or parts[1] > 99 or parts[2] > 99:
        raise ValueError("Apple bundle versions allow at most four, two and two digits")
    if parts == (0, 0, 0):
        raise ValueError("Version must be greater than 0.0.0")
    return parts


def validate_release(version, releases):
    current = version_tuple(version)
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        tag = release["tag_name"]
        if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
            raise ValueError(f"Review unrecognized stable release tag: {tag}")
        if current <= version_tuple(tag[1:]):
            raise ValueError(f"{version} must be newer than published release {tag}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--releases", type=Path, required=True)
    args = parser.parse_args()
    if not args.tag.startswith("v"):
        parser.error("Run the release workflow on a vX.Y.Z tag")
    version = args.tag[1:]
    pages = json.loads(args.releases.read_text())
    releases = [release for page in pages for release in page]
    validate_release(version, releases)
    info = plistlib.loads(Path("Resources/Info.plist").read_bytes())
    if version != info["CFBundleShortVersionString"]:
        raise ValueError("Tag and app version differ. Run scripts/prepare-release.py first")
    print(version)


if __name__ == "__main__":
    main()
