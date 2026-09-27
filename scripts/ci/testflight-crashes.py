#!/usr/bin/env python3
"""Prints the newest TestFlight crash reports as GitHub annotations.

Crash reports appear in App Store Connect when a tester taps "Share" on the
TestFlight crash prompt. This reads them with the App Store Connect API
(same API key as the release workflow) so they can be read without a Mac.
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error

import jwt  # PyJWT

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
PRIVATE_KEY = os.environ["ASC_PRIVATE_KEY"]
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.carolandmartin.familoq")
LIMIT = int(os.environ.get("CRASH_LIMIT", "3"))
API = "https://api.appstoreconnect.apple.com"


def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      PRIVATE_KEY, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def get(path):
    req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:500]
        print(f"::error title=App Store Connect API::{e.code} for {path}: {body}")
        sys.exit(1)


def annotate(kind, title, text):
    # GitHub workflow commands: escape %, CR, LF.
    text = text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::{kind} title={title}::{text}")


def summarize_ips(log):
    """iOS .ips crash report: header JSON line + body JSON."""
    parts = log.split("\n", 1)
    body = json.loads(parts[1] if len(parts) > 1 else parts[0])
    lines = []
    exc = body.get("exception", {})
    lines.append(f"Exception: {exc.get('type')} {exc.get('signal', '')} {exc.get('subtype', '')}".strip())
    term = body.get("termination", {})
    if term:
        lines.append(f"Termination: {term.get('namespace')} {term.get('indicator', '')} {' | '.join(term.get('reasons', []) if isinstance(term.get('reasons'), list) else [])}")
    if body.get("asi"):
        lines.append("Crash info: " + json.dumps(body["asi"])[:1500])
    images = body.get("usedImages", [])
    fault = body.get("faultingThread", 0)
    threads = body.get("threads", [])
    if fault < len(threads):
        t = threads[fault]
        lines.append(f"Crashed thread {fault} {t.get('queue', '')}:")
        for i, f in enumerate(t.get("frames", [])[:30]):
            img = images[f["imageIndex"]]["name"] if f.get("imageIndex", -1) < len(images) else "?"
            sym = f.get("symbol")
            loc = f"{sym} + {f.get('symbolLocation', 0)}" if sym else f"offset 0x{f.get('imageOffset', 0):x}"
            src = f" ({f['sourceFile']}:{f.get('sourceLine')})" if f.get("sourceFile") else ""
            lines.append(f"{i:2} {img:28} {loc}{src}")
    return "\n".join(lines)


def summarize_text(log):
    """Classic text crash report: keep the header and the crashed thread."""
    out, keep = [], False
    for line in log.splitlines():
        if line.startswith(("Exception Type", "Exception Codes", "Termination Reason", "Triggered by Thread", "Application Specific", "Crashed Thread")):
            out.append(line)
        if "Crashed:" in line:
            keep = True
        elif keep and not line.strip():
            keep = False
        if keep:
            out.append(line)
    return "\n".join(out[:60]) or log[:3500]


def main():
    apps = get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        annotate("error", "Crash reports", f"No app with bundle ID {BUNDLE_ID}")
        return
    app_id = apps[0]["id"]
    shots = get(f"/v1/apps/{app_id}/betaFeedbackScreenshotSubmissions?sort=-createdDate&limit=5")["data"]
    for sub in shots:
        a = sub.get("attributes", {})
        annotate("notice", "Feedback", f"{a.get('createdDate')} · {a.get('deviceModel')} iOS {a.get('osVersion')} · {a.get('comment') or '-'}")
    subs = get(f"/v1/apps/{app_id}/betaFeedbackCrashSubmissions?sort=-createdDate&limit={LIMIT}")["data"]
    if not subs:
        annotate("notice", "Crash reports", "No shared TestFlight crash reports yet. After a crash, open Familoq again and tap 'Share' in the TestFlight prompt (or TestFlight app -> Familoq -> Send Beta Feedback).")
        return
    for n, sub in enumerate(subs, 1):
        a = sub.get("attributes", {})
        head = (f"#{n} {a.get('createdDate')} · {a.get('deviceModel')} iOS {a.get('osVersion')} · "
                f"build {a.get('buildBundleId', '')} · comment: {a.get('comment') or '-'}")
        log = get(f"/v1/betaFeedbackCrashSubmissions/{sub['id']}/crashLog")["data"]["attributes"].get("logText", "")
        try:
            summary = summarize_ips(log)
        except Exception:
            summary = summarize_text(log)
        annotate("warning", f"Crash {n}", head + "\n" + summary[:3800])


if __name__ == "__main__":
    main()
