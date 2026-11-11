"""Gathers what the licences of FFmpeg's libraries ask for, from the sources FFmpeg-Builds downloaded to build them.

Usage: collect.py <downloads> <stages.txt> <licences out> <sources out> <LGPL library names...>

- Each library's licence files go to <licences out>/<library>/, as they stand in its source.
- The whole source of each LGPL library is copied to <sources out>/<library>-source.tar.xz.
"""
import os
import re
import shutil
import sys
import tarfile

downloads, stages_file, licences, sources = sys.argv[1:5]
lgpl = set(sys.argv[5:])

NAMES = re.compile(r"^(copying|copyright|licen[cs]e|notice|patents?|ftl|unlicense)([._-][a-z0-9._-]*)?$", re.I)
# Licence files of tests and examples, which aren't built into anything.
SKIP_DIRS = {".git", "test", "tests", "testdata", "test-data", "testing", "examples", "fuzz", "fuzzing", "googletest",
             "benchmark", "benchmarks"}


def licence_files(tar):
    for member in tar.getmembers():
        if not member.isfile():
            continue
        parts = [p for p in member.name.split("/") if p not in ("", ".")]
        if not parts or len(parts) > 4:
            continue
        if any(p.lower() in SKIP_DIRS for p in parts[:-1]):
            continue
        if NAMES.match(parts[-1]):
            yield member, "/".join(parts)


stages = []
with open(stages_file, encoding="utf-8") as f:
    for line in f:
        stage = line.split(" ", 1)[0].strip()
        if stage:
            stages.append(stage)

os.makedirs(licences, exist_ok=True)
os.makedirs(sources, exist_ok=True)
found = set()
for stage in stages:
    name = re.sub(r"^\d\d-", "", stage)
    archive = os.path.join(downloads, stage + ".tar.xz")
    if not os.path.exists(archive):
        print(f"{stage}: nothing downloaded")
        continue
    picked = []
    with tarfile.open(archive) as tar:
        for member, path in licence_files(tar):
            target = os.path.join(licences, name, *path.split("/"))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with tar.extractfile(member) as src, open(target, "wb") as dst:
                shutil.copyfileobj(src, dst)
            picked.append(path)
    print(f"{stage}: {', '.join(picked) if picked else 'NO LICENCE FILE FOUND'}")
    if name in lgpl:
        shutil.copyfile(os.path.realpath(archive), os.path.join(sources, f"{name}-source.tar.xz"))
        found.add(name)

missing = lgpl - found
if missing:
    sys.exit("No source for the LGPL libraries " + ", ".join(sorted(missing)))
