#!/usr/bin/env python3
"""Set the next version locally. Does not commit, push, tag, or publish."""
import argparse
import plistlib
import subprocess
from pathlib import Path
from release_metadata import version_tuple

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("version")
args = parser.parse_args()
next_version = version_tuple(args.version)
current = plistlib.loads((root / "Resources/Info.plist").read_bytes())
if next_version <= version_tuple(current["CFBundleShortVersionString"]):
    parser.error("The next version must be greater than the current version")
for relative in ["Resources/Info.plist", "Resources/Control/Info.plist"]:
    path = root / relative
    info = plistlib.loads(path.read_bytes())
    info.update(CFBundleShortVersionString=args.version, CFBundleVersion=args.version)
    path.write_bytes(plistlib.dumps(info))
subprocess.run(["python3", str(root / "scripts/generate-xcode-project.py")], check=True)
print(f"Prepared {args.version}. Update RELEASE_NOTES.md, review changes, then commit.")
print(f"Publish explicitly with: git tag v{args.version} && git push origin main v{args.version}")
