#!/usr/bin/env python3
"""Smoke-test the packaged app's native conversions without launching its UI."""
import argparse
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import wave
import zipfile
import zlib

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path, default=ROOT / "build/Liman.app")
parser.add_argument("--with-tools", action="store_true", help="Also exercise installed FFmpeg and Office runtimes")
args = parser.parse_args()
APP = args.app.resolve()
EXE = APP / "Contents/MacOS/Liman"
passed = 0

def check(name, value):
    global passed
    assert value, name
    passed += 1
    print("PASS", name)

def run(*args):
    return json.loads(subprocess.check_output([str(EXE), *map(str, args)], text=True, timeout=120))

info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
check("packaged independent identity", info["CFBundleIdentifier"] == "local.liman.filetoolkit" and info["CFBundleDisplayName"] == "Liman")
check("packaged updater has no trust key or feed", info["LimanLocalOnly"] and "SUPublicEDKey" not in info and "SUFeedURL" not in info and not info["SUEnableAutomaticChecks"])
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(APP)], check=True)
check("local ad-hoc bundle integrity", True)
check("MIT license bundled verbatim", (APP / "Contents/Resources/LICENSE.txt").read_bytes() == (ROOT / "LICENSE").read_bytes())
catalog = run("catalog")
check("catalog retains all tools", len(catalog["tools"]) == 27)
with tempfile.TemporaryDirectory(prefix="liman-app-smoke-") as directory:
    root = Path(directory)
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress((b"\0" + b"\xff\0\0" * 16) * 16)) + chunk(b"IEND", b"")
    source = root / "source.png"
    source.write_bytes(png)
    options = json.dumps({"outputDirectory": str(root / "exports")})
    jpg = run("convert", "jpg", source, "--options", options, "--json")[0]
    check("native image conversion retains dimensions", run("inspect", jpg) == {"category": "image", "width": 16, "height": 16})
    pdf = run("convert", "pdf", source, "--options", options, "--json")[0]
    check("native PDF export readable", run("inspect", pdf)["pages"] == 1)
    check("conversion preserves original", source.read_bytes() == png)
    archive = root / "safe.zip"
    with zipfile.ZipFile(archive, "w") as z:
        z.writestr("nested/text.txt", "unchanged")
    extracted = Path(run("tool", "extractArchive", archive, "--options", options, "--json")[0])
    check("packaged archive extraction", (extracted / "nested/text.txt").read_text() == "unchanged")
    hostile = root / "hostile.zip"
    with zipfile.ZipFile(hostile, "w") as z:
        z.writestr("../escaped.txt", "must not escape")
    before = sorted(str(p.relative_to(root / "exports")) for p in (root / "exports").rglob("*"))
    result = subprocess.run([str(EXE), "tool", "extractArchive", str(hostile), "--options", options, "--json"], capture_output=True, text=True)
    after = sorted(str(p.relative_to(root / "exports")) for p in (root / "exports").rglob("*"))
    check("packaged hostile archive rejected with clean rollback", result.returncode != 0 and before == after and not (root / "escaped.txt").exists())
    if args.with_tools:
        audio = root / "source.wav"
        with wave.open(str(audio), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16000)
            output.writeframes(b"\0\0" * 16000)
        mp3 = run("convert", "mp3", audio, "--options", options, "--json")[0]
        media = run("inspect", mp3)
        check("real FFmpeg export and ffprobe", media["hasAudio"] and abs(media["duration"] - 1) < 0.3)
        document = root / "source.rtf"
        document.write_text(r"{\rtf1\ansi Liman installation test.}")
        exported = run("convert", "pdf", document, "--options", options, "--json")[0]
        check("real office PDF export", run("inspect", exported)["pages"] == 1)
        tools = run("dependencies")
        check("independent runtime locations", "Liman/Tools" in tools["ffmpeg"] and "Liman/Tools" in tools["soffice"] and "Liman.app" in tools["exiftool"])
print(f"{passed} packaged app checks passed (UI not launched)")
