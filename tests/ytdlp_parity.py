#!/usr/bin/env python3
"""Checks the C++ helpers of the native yt-dlp extension against extensions/ytdlp/main.py.
usage: ytdlp_parity.py /path/to/ytdlp_parity"""
import json, os, subprocess, sys, tempfile

here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "..", "extensions", "ytdlp", "main.py")).read()
ns = {}
exec(compile(src.split("METHODS =")[0], "main.py", "exec"), ns)     # everything before the stdin loop

cookie_file = tempfile.NamedTemporaryFile(delete=False); cookie_file.close()
msgs = ["Sign in to confirm you're not a bot", "ERROR: This video is age-restricted", "Video unavailable", "Private video",
        "could not find chrome cookies database", "HTTP Error 429", "The uploader has not made this video available in your country", "something else"]
urls = ["https://www.youtube.com/watch?v=abc123&list=RDabc123", "https://youtu.be/xyz789?si=1", "https://soundcloud.com/a/b", "https://www.youtube.com/watch?feature=x&v=q1"]
entries = [
    {"title": "Skyline (Slowed + Reverb)", "uploader": "Nova Drift", "url": "https://www.youtube.com/watch?v=bad1"},
    {"title": "Nova Drift - Skyline (Official Audio)", "uploader": "Nova Drift", "url": "https://www.youtube.com/watch?v=good1"},
    {"title": "Skyline cover by someone", "channel": "Other", "url": "https://youtu.be/cov1"},
]
cases = []
for m in msgs:
    for s in (False, True): cases.append({"kind": "friendly", "msg": m, "signed": s})
for u in urls: cases.append({"kind": "video_id", "url": u})
for params in ({"title": "Skyline", "artist": "Nova Drift"}, {"title": "Skyline", "artist": ""}, {"title": "Skyline (Slowed + Reverb)", "artist": "Nova Drift"},
               {"title": "Missing Song", "artist": "Nova Drift"}, {"title": "", "artist": "x"}):
    cases.append({"kind": "seed_video", "entries": entries, "params": params})
for opts in ({}, {"cookiesBrowser": "Firefox"}, {"cookiesBrowser": "netscape"}, {"cookiesFile": cookie_file.name, "cookiesBrowser": "chrome"},
             {"cookiesFile": "/nonexistent/file.txt", "cookiesBrowser": "brave"}):
    cases.append({"kind": "auth", "params": {"_options": opts}})

expect = []
for c in cases:
    k = c["kind"]
    if k == "friendly": expect.append(ns["friendly"](c["msg"], c["signed"]))
    elif k == "video_id": expect.append(ns["_video_id"](c["url"]))
    elif k == "seed_video": expect.append(ns["_seed_video"](c["entries"], c["params"]))
    elif k == "auth": expect.append(ns["auth_args"](c["params"]))
got = json.loads(subprocess.run([sys.argv[1]], input=json.dumps(cases), capture_output=True, text=True, check=True).stdout)
bad = 0
for c, e, g in zip(cases, expect, got):
    if e != g:
        bad += 1; print("MISMATCH", json.dumps(c)[:160], "\n  python:", e, "\n  c++   :", g)
print("%d cases, %d mismatches" % (len(cases), bad))
os.unlink(cookie_file.name)
sys.exit(1 if bad else 0)
