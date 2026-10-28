#!/usr/bin/env python3
"""Read pinned manifests and query public OSV advisories; never install packages."""
import datetime
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
queries = []
seen = set()
for lock in sorted((ROOT / "windows").glob("*/packages.lock.json")):
    for dependencies in json.loads(lock.read_text())["dependencies"].values():
        for name, item in dependencies.items():
            version = item.get("resolved")
            if version and (name.lower(), version) not in seen:
                seen.add((name.lower(), version))
                queries.append({"package": {"ecosystem": "NuGet", "name": name}, "version": version})
queries.extend([
    {"package": {"ecosystem": "npm", "name": "pdf-lib"}, "version": "1.17.1"},
    {"package": {"ecosystem": "npm", "name": "cupertino-files"}, "version": "0.4.0"},
    {"package": {"ecosystem": "npm", "name": "@esbuild/darwin-arm64"}, "version": "0.25.12"},
    {"package": {"ecosystem": "PyPI", "name": "yt-dlp"}, "version": "2026.8.19"},
    {"commit": json.loads((ROOT / "Package.resolved").read_text())["pins"][0]["state"]["revision"]},
])
request = urllib.request.Request("https://api.osv.dev/v1/querybatch", data=json.dumps({"queries": queries}).encode(), headers={"Content-Type": "application/json"})
with urllib.request.urlopen(request, timeout=60) as response:
    result = json.load(response)
report = {"queriedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(), "source": "https://api.osv.dev/v1/querybatch", "scope": "Pinned NuGet, selected vendored packages, yt-dlp and Sparkle commit. Empty results are not a security guarantee or proof of OSV ecosystem coverage.", "results": [{"query": q, "result": r} for q, r in zip(queries, result["results"], strict=True)]}
output = ROOT / "audit/dependency-advisories.json"
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"{len(queries)} queries; {sum(bool(r.get('vulns')) for r in result['results'])} with advisory matches")
for row in report["results"]:
    if row["result"].get("vulns"):
        print(row["query"], row["result"])
