#!/usr/bin/env python3
"""Reject local installs that would invalidate the installed app's TCC identity."""
import argparse
import plistlib
import re
import subprocess
from pathlib import Path


def codesign(*arguments):
    result = subprocess.run(["/usr/bin/codesign", *map(str, arguments)],
                            capture_output=True, text=True)
    if result.returncode:
        raise ValueError(result.stderr.strip() or "Code signature verification failed.")
    return result.stdout + result.stderr


def bundle_id(app):
    with (Path(app) / "Contents/Info.plist").open("rb") as file:
        return plistlib.load(file)["CFBundleIdentifier"]


def verify_continuity(previous, candidate):
    if bundle_id(previous) != bundle_id(candidate):
        raise ValueError("The bundle identifier changed.")
    codesign("--verify", "--strict", previous)
    requirement = codesign("-d", "-r-", previous)
    match = re.search(r"^(?:# )?designated => (.+)$", requirement, re.MULTILINE)
    if not match:
        raise ValueError("Could not read the installed app's designated requirement.")
    codesign("--verify", "--strict", "--all-architectures", "-R=" + match[1], candidate)


def verify_install(candidate, previous=None):
    codesign("--verify", "--deep", "--strict", "--all-architectures", candidate)
    metadata = codesign("-dv", candidate)
    if "Signature=adhoc" in metadata or not re.search(
            r"^TeamIdentifier=(?!not set$)\S+$", metadata, re.MULTILINE):
        raise ValueError("An Apple Development or Developer ID signature is required for installation. "
                         "Ad-hoc builds change their permission identity on rebuild.")
    codesign("--verify", "-R=anchor apple generic", candidate)
    if previous and Path(previous).exists():
        try:
            verify_continuity(previous, candidate)
        except ValueError as error:
            raise ValueError("This build does not match the installed app's permission identity. "
                             "Installation stopped; the existing app is unchanged. " + str(error)) from error


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate")
    parser.add_argument("previous", nargs="?")
    args = parser.parse_args()
    try:
        verify_install(args.candidate, args.previous)
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f"Cannot install Duotlet: {error}\n")
