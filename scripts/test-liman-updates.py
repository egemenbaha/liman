#!/usr/bin/env python3
"""Run the real updater policy with the pinned Sparkle framework, without XCTest."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parent.parent
subprocess.run(["swift", "build", "--target", "NashiUpdates"], cwd=ROOT, check=True)
binary = Path(subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=ROOT, text=True).strip())
frameworks = ROOT / ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
objects = sorted((binary / "NashiUpdates.build").glob("*.o"))
output = binary / "liman-update-checks"
subprocess.run(["swiftc", "-parse-as-library", "-I", str(binary / "Modules"), "-F", str(frameworks),
                str(ROOT / "Tests/LimanSecurityChecks/Updates.swift"), *map(str, objects),
                "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", str(frameworks), "-o", str(output)], check=True, cwd=ROOT)
subprocess.run([str(output)], check=True, cwd=ROOT)
