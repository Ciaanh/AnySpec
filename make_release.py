#!/usr/bin/env python3
"""Build the release zip: dist/AnySpec-v<version>.zip containing an AnySpec/ folder.

Usage:  python make_release.py [--version X.Y.Z]

The version comes from AnySpec.toc (## Version). Only files tracked by git are
packaged, minus dev-only files, so untracked scratch files never end up in the zip.
Unpack the result into World of Warcraft/_retail_/Interface/AddOns/.
"""
import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ADDON = "AnySpec"
EXCLUDE = (".gitignore", "make_release.py", ".github/", "docs/", "refs/",
           "assets/configuration_frame", "assets/instance_toast", "assets/spec_selector")  # README screenshots


def toc_version() -> str:
    text = (ROOT / f"{ADDON}.toc").read_text(encoding="utf-8")
    m = re.search(r"^##\s*Version:\s*(\S+)", text, re.M)
    if not m:
        sys.exit("No '## Version:' line found in the .toc file")
    return m.group(1)


def tracked_files() -> list[str]:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout.splitlines()
    return [f for f in out if not f.startswith(EXCLUDE)]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--version", help="override the version read from the .toc")
    args = ap.parse_args()

    version = args.version or toc_version()
    files = tracked_files()
    if f"{ADDON}.toc" not in files:
        sys.exit("AnySpec.toc is not tracked by git")

    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    target = dist / f"{ADDON}-v{version}.zip"
    target.unlink(missing_ok=True)

    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in files:
            zf.write(ROOT / f, f"{ADDON}/{f}")

    print(f"{target.relative_to(ROOT)}  ({len(files)} files, version {version})")


if __name__ == "__main__":
    main()
