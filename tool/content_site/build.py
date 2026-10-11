#!/usr/bin/env python3
"""Build the content site served at text.amud.page (see content-site/README.md).

    python3 tool/content_site/build.py --interlinear ~/path/to/interlinear/out
    cd content-site && npx wrangler deploy

Two trees, both static:

  content/v1/manifest.json        the app's bundled content files, by asset path:
                                  {"format": 1, "version": ..., "files": {path: {sha256, size}}}
  content/v1/files/<sha256>       each file, named by its hash (never changes)

  interlinear/v1/index.json       {"version": ..., "works": {"<spine>/<work>": {path, sha256, units}}}
  interlinear/v1/<spine>/<slug>.<sha8>.json
                                  a whole tractate / masechta / book: {"spine", "work", "units": [...]}

The app checks the two small JSON files now and then, downloads only what
changed, and checks every file's hash before using it. A content fix ships by
rebuilding the asset (e.g. tool/corpus/build_assets.py), running this, and
deploying; no app release.

Format 1 is what apps today understand. A change old apps can't read gets a
new format directory (content/v2/...) beside the old one.
"""

import argparse
import datetime
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Asset paths the app reads through its content loader (lib/core/content.dart).
CONTENT = ["assets/corpus", "assets/sefaria", "assets/rules", "assets/tehillim", "assets/integrations/cards.json"]
FORMAT = 1


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def slug(work: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", work.lower()).strip("_")


def content_files():
    for entry in CONTENT:
        p = ROOT / entry
        files = [p] if p.is_file() else sorted(f for f in p.rglob("*") if f.is_file())
        for f in files:
            if f.name.startswith("."):
                continue
            yield f.relative_to(ROOT).as_posix(), f.read_bytes()


def build_content(out: Path, version: str):
    base = out / "content" / f"v{FORMAT}"
    (base / "files").mkdir(parents=True)
    files = {}
    for path, data in content_files():
        h = sha(data)
        (base / "files" / h).write_bytes(data)
        files[path] = {"sha256": h, "size": len(data)}
    (base / "manifest.json").write_text(json.dumps({"format": FORMAT, "version": version, "files": files}, indent=1))
    print(f"content: {len(files)} files, {sum(f['size'] for f in files.values()) / 1e6:.1f} MB")


def unit_order(unit: str):
    """2a < 2b < 10a; numbered chapters by number."""
    m = re.match(r"^(\d+)([ab]?)$", unit)
    return (int(m.group(1)), m.group(2)) if m else (10**9, unit)


def build_interlinear(src: Path, out: Path, version: str):
    base = out / "interlinear" / "v1"
    works = {}
    for spine_dir in sorted(p for p in src.iterdir() if p.is_dir() and not p.name.startswith(".")):
        by_work = {}
        for f in sorted(spine_dir.glob("*/*.en.json")):
            try:
                body = json.loads(f.read_text())["parsed"]
            except (ValueError, KeyError):
                print(f"  skipped unreadable {f}")
                continue
            # The reader needs the words, glosses, links and runs; the source
            # string is the words again.
            for s in body.get("segments", []):
                s.pop("source", None)
                s.pop("issues", None)
            by_work.setdefault(body["work"], []).append(body)
        for work, units in by_work.items():
            units.sort(key=lambda u: unit_order(u["unit"]))
            data = json.dumps({"spine": spine_dir.name, "work": work, "units": units}, ensure_ascii=False, separators=(",", ":")).encode()
            h = sha(data)
            rel = f"{spine_dir.name}/{slug(work)}.{h[:8]}.json"
            (base / rel).parent.mkdir(parents=True, exist_ok=True)
            (base / rel).write_bytes(data)
            works[f"{spine_dir.name}/{work}"] = {"path": rel, "sha256": h, "units": len(units), "size": len(data)}
    (base / "index.json").write_text(json.dumps({"version": version, "works": works}, ensure_ascii=False, indent=1))
    print(f"interlinear: {len(works)} works, {sum(w['units'] for w in works.values())} units, {sum(w['size'] for w in works.values()) / 1e6:.0f} MB before compression")


HEADERS = """\
/*
  Access-Control-Allow-Origin: *
/content/v1/manifest.json
  Cache-Control: no-cache
/interlinear/v1/index.json
  Cache-Control: no-cache
/content/v1/files/*
  Cache-Control: public, max-age=31536000, immutable
  Content-Type: application/octet-stream
/interlinear/v1/:spine/*
  Cache-Control: public, max-age=31536000, immutable
  Content-Type: application/json; charset=utf-8
"""

INDEX = """<!doctype html><meta charset="utf-8"><title>Amud content</title>
<p>Texts and updates for the <a href="https://amud.page">Amud</a> app.</p>
"""


def main():
    ap = argparse.ArgumentParser()
    # Required: a deploy replaces the whole site, so building without it would
    # take the interlinear texts down.
    ap.add_argument("--interlinear", type=Path, required=True, help="interlinear output folder (spine/work/unit.en.json)")
    ap.add_argument("--out", type=Path, default=ROOT / "content-site" / "dist")
    a = ap.parse_args()
    version = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    if a.out.exists():
        shutil.rmtree(a.out)
    a.out.mkdir(parents=True)
    build_content(a.out, version)
    build_interlinear(a.interlinear.expanduser(), a.out, version)
    (a.out / "_headers").write_text(HEADERS)
    (a.out / "index.html").write_text(INDEX)
    n = sum(1 for f in a.out.rglob("*") if f.is_file())
    print(f"{n} files in {a.out}")


if __name__ == "__main__":
    main()
