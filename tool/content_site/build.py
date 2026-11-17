#!/usr/bin/env python3
"""Build the content site served at text.amud.page (see content-site/README.md).

    python3 tool/content_site/build.py --interlinear ~/path/to/interlinear/out [--daf-print build/daf/place]
    cd content-site && npx wrangler deploy

Two trees, both static:

  content/v1/manifest.json        the app's bundled content files, by asset path:
                                  {"format": 1, "version": ..., "files": {path: {sha256, size, replaces}}}
                                  replaces: the sha256 of every earlier committed version of
                                  the file; an app takes the file only if its own copy is
                                  one of them (apps after 0.14 — 0.14 and before take
                                  whatever differs from their copy)
  content/v1/files/<sha256>       each file, named by its hash (never changes)

  interlinear/v1/index.json       {"version": ..., "works": {"<spine>/<work>": {path, sha256, units}}}
  interlinear/v1/<spine>/<slug>.<sha8>.json
                                  a whole tractate / masechta / book: {"spine", "work", "units": [...]}

  daf/v2/index.json               {"version": ..., "works": {"<tractate>": {path, sha256, units}}}
  daf/v2/<slug>.<sha8>.json       a tractate's printed pages, every word where the Vilna page
                                  prints it (tool/daf/svg.py placement(), tool/daf/shas.py):
                                  {"book", "amudim": {"2a": page, ...}}

The app checks the two small JSON files now and then, downloads only what
changed, and checks every file's hash before using it. A content fix ships by
rebuilding the asset (e.g. tool/corpus/build_assets.py), running this, and
deploying; no app release.

Format 1 is what apps today understand. A change old apps can't read gets a
new format directory (content/v2/...) beside the old one.
"""

import argparse
import datetime
import functools
import hashlib
import json
import re
import shutil
import subprocess
import sys
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


def git(*args) -> bytes:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, check=True).stdout


@functools.cache
def blob_sha(blob: str) -> str:
    return sha(git("cat-file", "blob", blob))


def tree_blobs(rev: str) -> dict[str, str]:
    """Each content file at REV: path -> git blob id."""
    out = {}
    for line in git("ls-tree", "-r", rev, "--", *CONTENT).decode().splitlines():
        meta, path = line.split("\t", 1)
        out[path] = meta.split()[2]
    return out


def latest_release() -> str:
    tags = git("tag", "--list", "v*", "--merged", "HEAD").decode().split()
    return max(tags, key=lambda t: tuple(int(n) for n in re.findall(r"\d+", t)))


def earlier_versions(rev: str = "HEAD") -> dict[str, set[str]]:
    """The sha256 of every version of each content file committed in REV's
    history. A file on the site lists those before it as `replaces`, so an
    app takes it only when its own bundled copy is older
    (lib/core/content.dart). A site published before a release then can't
    put older text back into the release."""
    if git("rev-parse", "--is-shallow-repository").strip() != b"false":
        sys.exit("a shallow clone: `replaces` needs the whole history (git fetch --unshallow)")
    # Every blob each path has had: one walk, merges included (-m).
    log = git("log", "--full-history", "-m", "--raw", "--no-abbrev", "--no-renames", "--format=", rev, "--", *CONTENT).decode()
    blobs: dict[str, set[str]] = {}
    for line in log.splitlines():
        if not line.startswith(":"):
            continue
        meta, path = line.split("\t", 1)
        for b in meta.split()[2:4]:
            if b.strip("0"):
                blobs.setdefault(path, set()).add(b)
    # Every release's copy must be among them, or that release would never
    # take a fix.
    for tag in git("tag", "--list", "v*", "--merged", rev).decode().split():
        for path, b in tree_blobs(tag).items():
            if b not in blobs.get(path, ()):
                sys.exit(f"{tag}:{path} is missing from the history walk")
    return {path: {blob_sha(b) for b in bs} for path, bs in blobs.items()}


def build_content(out: Path, version: str):
    base = out / "content" / f"v{FORMAT}"
    (base / "files").mkdir(parents=True)
    earlier = earlier_versions()
    files = {}
    for path, data in content_files():
        h = sha(data)
        (base / "files" / h).write_bytes(data)
        files[path] = {"sha256": h, "size": len(data), "replaces": sorted(earlier.get(path, set()) - {h})}
    (base / "manifest.json").write_text(json.dumps({"format": FORMAT, "version": version, "files": files}, indent=1))
    print(f"content: {len(files)} files, {sum(f['size'] for f in files.values()) / 1e6:.1f} MB")


def stale_live_content(files: dict) -> dict[str, str]:
    """Files the live content/v1 lists that are older than the newest
    release's copies, or that neither it nor this checkout has: apps up to
    0.14 take any file that differs from their own, so these put older text
    back into them (path -> why)."""
    tag = latest_release()
    shipped = {path: blob_sha(b) for path, b in tree_blobs(tag).items()}
    before = earlier_versions(tag)
    here = {path for path, _ in content_files()}
    stale = {}
    for path, info in files.items():
        if path in shipped:
            if info["sha256"] != shipped[path] and info["sha256"] in before.get(path, ()):
                stale[path] = f"older than {tag}'s"
        elif path not in here:
            stale[path] = f"in neither {tag} nor this checkout"
    return stale


def finish_live_content(out: Path, version: str, stale: dict[str, str]):
    """The live content/v1 copied into OUT, without the STALE files (their
    files deleted: apps go back to their own copies). The files left that
    match the assets here get `replaces`."""
    base = out / "content" / f"v{FORMAT}"
    manifest = json.loads((base / "manifest.json").read_text())
    files = manifest["files"]
    for path, why in stale.items():
        print(f"  dropped {path}: {why}")
        gone = files.pop(path)["sha256"]
        if not any(f["sha256"] == gone for f in files.values()):
            (base / "files" / gone).unlink(missing_ok=True)
    here = {path: sha(data) for path, data in content_files()}
    earlier = earlier_versions()
    for path, info in files.items():
        if info["sha256"] == here.get(path):
            info["replaces"] = sorted(earlier.get(path, set()) - {info["sha256"]})
        else:
            print(f"  kept {path} as it is live: not the copy in this checkout")
    manifest["version"] = version
    (base / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(f"content: {len(files)} files listed, {len(stale)} dropped")


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


def build_daf_print(src: Path, out: Path, version: str):
    """tool/daf/shas.py's printed pages (<Book>_<amud>.json) as one bundle
    per tractate."""
    base = out / "daf" / "v2"
    base.mkdir(parents=True)
    by_book = {}
    for f in sorted(src.glob("*.json")):
        m = json.loads(f.read_text())
        by_book.setdefault(m["book"], {})[m["amud"]] = {k: m[k] for k in ("frame", "words", "weight", "placed")}
    works = {}
    for book, amudim in by_book.items():
        amudim = dict(sorted(amudim.items(), key=lambda kv: unit_order(kv[0])))
        data = json.dumps({"book": book, "amudim": amudim}, ensure_ascii=False, separators=(",", ":")).encode()
        h = sha(data)
        rel = f"{slug(book)}.{h[:8]}.json"
        (base / rel).write_bytes(data)
        works[book] = {"path": rel, "sha256": h, "units": len(amudim), "size": len(data)}
    (base / "index.json").write_text(json.dumps({"version": version, "works": works}, ensure_ascii=False, indent=1))
    print(f"daf print: {len(works)} tractates, {sum(w['units'] for w in works.values())} amudim, {sum(w['size'] for w in works.values()) / 1e6:.1f} MB")


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
/daf/v2/index.json
  Cache-Control: no-cache
/daf/v2/*
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
    ap.add_argument("--interlinear", type=Path, help="interlinear output folder (spine/work/unit.en.json)")
    # Ships only the printed pages: content/ and interlinear/ go up exactly
    # as they are live (a copy fetched from the site), so nothing else changes.
    ap.add_argument("--live", type=Path, help="a copy of the live site (content/v1, interlinear/v1 and daf/v2), deployed as is")
    ap.add_argument("--drop-stale", action="store_true", help="with --live: take files older than the latest release's off the content list")
    ap.add_argument("--daf-print", type=Path, help="tool/daf/shas.py's printed pages (build/daf/place)")
    ap.add_argument("--out", type=Path, default=ROOT / "content-site" / "dist")
    a = ap.parse_args()
    if not a.interlinear and not a.live:
        ap.error("--interlinear or --live is required: a deploy replaces the whole site")
    out = a.out.expanduser().resolve()
    live = a.live.expanduser().resolve() if a.live else None
    # OUT is emptied first: a live copy inside it would be deleted.
    if live and (live == out or out in live.parents or live in out.parents):
        ap.error(f"--live {a.live} and --out {a.out} overlap: copy the live site somewhere else first")
    version = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    stale = {}
    if live:
        stale = stale_live_content(json.loads((live / "content" / f"v{FORMAT}" / "manifest.json").read_text())["files"])
        if stale and not a.drop_stale:
            sys.exit(
                "the live content/v1 is behind the latest release:\n"
                + "".join(f"  {p}: {why}\n" for p, why in stale.items())
                + "rebuild it (--interlinear instead of --live), or pass --drop-stale to take these off the list"
            )
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    if live:
        trees = ["content/v1", "interlinear/v1"] + ([] if a.daf_print else ["daf/v2"])
        for tree in trees:
            if (live / tree).exists():
                shutil.copytree(live / tree, out / tree)
        finish_live_content(out, version, stale)
    else:
        build_content(out, version)
        build_interlinear(a.interlinear.expanduser(), out, version)
    if a.daf_print:
        build_daf_print(a.daf_print.expanduser(), out, version)
    elif not (out / "daf" / "v2").exists():
        print("no --daf-print: deploying this takes the printed pages down")
    (out / "_headers").write_text(HEADERS)
    (out / "index.html").write_text(INDEX)
    n = sum(1 for f in out.rglob("*") if f.is_file())
    print(f"{n} files in {out}")


if __name__ == "__main__":
    main()
