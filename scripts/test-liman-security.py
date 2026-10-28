#!/usr/bin/env python3
"""Run production-core security regressions with Command Line Tools (no XCTest)."""
from pathlib import Path
import subprocess
import os
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
subprocess.run(["swift", "build", "--target", "NashiCore"], cwd=ROOT, check=True)
bin_path = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=ROOT, text=True).strip())
objects = sorted((bin_path / "NashiCore.build").glob("*.o"))
assert objects, "No production core objects found"
output = bin_path / "liman-security-checks"
subprocess.run(["swiftc", "-I", str(bin_path / "Modules"), str(ROOT / "Tests/LimanSecurityChecks/main.swift"),
                *map(str, objects), "-o", str(output)], cwd=ROOT, check=True)
with tempfile.TemporaryDirectory(prefix="liman-fixtures-") as directory:
    for name, entry in [("traversal.zip", "../escaped.txt"), ("absolute.zip", "/tmp/liman-must-not-write"), ("backslash.zip", "..\\escaped.txt")]:
        with zipfile.ZipFile(Path(directory) / name, "w") as archive:
            archive.writestr(entry, "fixture")
    with zipfile.ZipFile(Path(directory) / "entries.zip", "w") as archive:
        archive.writestr("a", "a")
        archive.writestr("b", "b")
    subprocess.run([str(output)], cwd=ROOT, check=True, env={**os.environ, "LIMAN_FIXTURES": directory})
