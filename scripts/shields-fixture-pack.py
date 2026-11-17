#!/usr/bin/env python3
"""Builds the small, unsigned Shields pack scenarios run with (scripts/scenario.sh): the lists in
Tests/Fixtures/Shields (a file's name is its group: trackers.txt, cookies.txt), a no-op stand-in
and one scriptlet. The format is scripts/shields-pack.mjs's: raw-deflated JSON.

    scripts/shields-fixture-pack.py <out dir>
"""
import base64, json, os, sys, zlib

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fixtures = os.path.join(root, "Tests", "Fixtures", "Shields")
out = sys.argv[1]
os.makedirs(out, exist_ok=True)

lists = []
for name in sorted(os.listdir(fixtures)):
    if name.endswith(".txt"):
        with open(os.path.join(fixtures, name), encoding="utf-8") as f:
            lists.append({"id": "fixture-" + name[:-4], "group": name[:-4], "title": "Fixture " + name[:-4], "licence": "MIT",
                          "homepage": "", "trusted": True, "text": f.read()})

def b64(text):
    return base64.b64encode(text.encode()).decode()

# Leaves a mark the scenario reads: that it ran, and whether the page had a body yet.
set_flag = "function setFlag(name) { window['__shields_' + name] = document.body ? 'late' : 'start'; }"
resources = {
    "scriptlets": [{"name": "set-flag.js", "aliases": [], "kind": {"mime": "application/javascript"}, "content": b64(set_flag)}],
    "redirects": [{"name": "noop.js", "aliases": [], "kind": {"mime": "application/javascript"}, "content": b64("window.__shields_stand_in = 1;")}],
}
pack = json.dumps({"format": 1, "built": "2026-11-17T00:00:00.000Z", "lists": lists, "resources": resources}).encode()
deflate = zlib.compressobj(9, zlib.DEFLATED, -15)
with open(os.path.join(out, "shields.pack"), "wb") as f:
    f.write(deflate.compress(pack) + deflate.flush())
