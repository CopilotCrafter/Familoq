#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator on the GitHub macOS runner
# (newest iOS runtime, prefers "iPhone 17", then any iPhone).
# Usage: UDID=$(scripts/ci/pick-simulator.sh)
set -euo pipefail

xcrun simctl list devices available --json | python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
candidates = []
for runtime, devices in data.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            preferred = 1 if d["name"] in ("iPhone 17", "iPhone 16", "iPhone 17 Pro") else 0
            candidates.append((version, preferred, d["name"], d["udid"]))
if not candidates:
    sys.exit("No available iPhone simulator found")
candidates.sort(reverse=True)
version, _, name, udid = candidates[0]
print(f"Using {name} (iOS {version[0]}.{version[1]}) {udid}", file=sys.stderr)
print(udid)
'
