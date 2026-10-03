"""Step 3: download the REAL thumbnails shown in the proof (video cards and
next-step options) so the Flutter render shows exactly those images."""
import hashlib
import json
import sys
from pathlib import Path

import httpx

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "out")
proof = json.loads((OUT / "proof.json").read_text())
urls = []
for case in proof["cases"]:
    urls += [v.get("image_url") for v in case.get("videos") or []]
    urls += [o.get("image_url") for o in (case.get("next") or {}).get("options") or []]
thumbs = {}
(OUT / "thumbs").mkdir(exist_ok=True)
client = httpx.Client(timeout=15, follow_redirects=True, headers={"User-Agent": "Mozilla/5.0 ASKODOX-video-proof"})
for url in dict.fromkeys(u for u in urls if u and u.startswith("https://")):
    try:
        r = client.get(url)
    except httpx.HTTPError:
        continue
    if r.status_code == 200 and r.headers.get("content-type", "").startswith("image/"):
        name = hashlib.sha1(url.encode()).hexdigest()[:16] + ".img"
        (OUT / "thumbs" / name).write_bytes(r.content)
        thumbs[url] = name
(OUT / "thumbs.json").write_text(json.dumps(thumbs, indent=1))
print(f"thumbnails downloaded: {len(thumbs)} of {len(set(u for u in urls if u))}")
