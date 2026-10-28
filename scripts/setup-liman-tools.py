#!/usr/bin/env python3
"""Install pinned runtimes through the production checksum and network boundary."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parent.parent
subprocess.run(["swift", "build", "--target", "NashiCore"], cwd=ROOT, check=True)
binary = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=ROOT, text=True).strip())
objects = sorted((binary / "NashiCore.build").glob("*.o"))
output = binary / "setup-liman-tools"
subprocess.run(["swiftc", "-parse-as-library", "-I", str(binary / "Modules"), str(ROOT / "scripts/setup-liman-tools.swift"),
                *map(str, objects), "-o", str(output)], cwd=ROOT, check=True)
subprocess.run([str(output)], cwd=ROOT, check=True)
