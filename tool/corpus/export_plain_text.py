#!/usr/bin/env python3
"""Export siddur chunks as reviewable plain text, keeping editorial content.

Example:
    python3 tool/corpus/export_plain_text.py --out-dir /tmp/siddur-review
    python3 tool/corpus/export_plain_text.py --nusach ashkenaz --out-dir /tmp/siddur-review
    python3 tool/corpus/export_plain_text.py --chunk mincha --out-dir /tmp/siddur-review

Each source chunk becomes a .txt file. The export removes HTML and Hebrew
vowel/cantillation marks, while retaining prayers, translations, notes,
instructions, headings, and compact annotation labels.
"""
import argparse
import html
import json
import re
import unicodedata
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SIDDUR = ROOT / "corpus" / "siddur"
FIELDS = ("kind", "when", "alt", "node", "role", "voice", "amidah", "minyan",
          "gestures", "repeat", "forgot", "select", "fold", "cite", "gloss",
          "comment")


def clean(value):
    class PlainText(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.out = []
            self.italics = []
            self.footnotes = 0

        def handle_starttag(self, tag, attrs):
            attrs = dict(attrs)
            if tag == "br":
                self.out.append("\n")
            elif tag == "sup" and "footnote-marker" in attrs.get("class", ""):
                self.out.append("[")
            elif tag == "i":
                footnote = "footnote" in attrs.get("class", "")
                self.italics.append(footnote)
                if footnote:
                    self.footnotes += 1
                    self.out.append("\n  ↳ ")

        def handle_endtag(self, tag):
            if tag == "sup":
                self.out.append("]")
            elif tag == "i" and self.italics:
                if self.italics.pop():
                    self.footnotes -= 1
                    if not self.footnotes:
                        self.out.append("\n")

        def handle_data(self, data):
            self.out.append(data)

    parser = PlainText()
    parser.feed(value)
    value = "".join(parser.out)
    value = html.unescape(value)
    # Hebrew combining marks cover both niqqud and cantillation marks.
    value = "".join(c for c in value if not ("\u0591" <= c <= "\u05c7" and unicodedata.category(c) == "Mn"))
    return re.sub(r"[ \t]+", " ", value).strip()


def render_part(part, lang, ref, translates=(), include_ref=True, show_labels=True):
    def value(v):
        if isinstance(v, list):
            return ",".join(str(x) for x in v)
        if isinstance(v, bool):
            return "yes" if v else "no"
        return clean(str(v)) if isinstance(v, str) and v else str(v)

    labels = [f"{key}={value(part[key])}" for key in FIELDS if key in part and part[key] not in (False, None, "", [])]
    label = f" [{'; '.join(labels)}]" if labels and show_labels else ""
    text = clean(part.get("text", ""))
    prefix = f"{lang} {ref}{label}: " if include_ref else f"  [{label[2:-1]}]: " if label else "  "
    lines = [prefix + text] if text else []
    if lang == "HE" and part.get("en"):
        lines.append(f"EN note: {clean(part['en'])}")
    if lang == "EN" and part.get("he"):
        lines.append(f"HE note: {clean(part['he'])}")
    if lang == "EN" and translates and include_ref:
        lines[0] = lines[0].replace(": ", f" (for {','.join(translates)}): ", 1)
    return lines


def export_chunk(path):
    book = json.loads(path.read_text())
    lines = [f"{path.parent.name.upper()} | {book['chunk']}"]
    for leaf in book.get("leaves", []):
        lines += ["", f"## {leaf.get('path', '')} — {leaf.get('title', '')}"]
        leaf_meta = [f"{k}={leaf[k]}" for k in ("node", "service", "when") if leaf.get(k)]
        if leaf.get("comment"):
            leaf_meta.append(f"comment={clean(leaf['comment'])}")
        if leaf_meta:
            lines.append("[" + "; ".join(leaf_meta) + "]")
        for lang, label in (("he", "HE"), ("en", "EN")):
            text = leaf.get(lang)
            if not text:
                lines.append(f"-- {label} MISSING --")
                continue
            lines.append(f"-- {label} --")
            if not text.get("segs"):
                lines.append("[no segments]")
            for seg in text.get("segs", []):
                parts = seg.get("parts", [seg])
                translates = seg.get("translates", [])
                previous_labels = None
                for part in parts:
                    current_labels = tuple(
                        (key, str(part[key])) for key in FIELDS
                        if key in part and part[key] not in (False, None, "", [])
                    )
                    include_ref = previous_labels is None
                    lines.extend(render_part(
                        part, label, seg.get("ref", "?"), translates,
                        include_ref=include_ref,
                        show_labels=include_ref or current_labels != previous_labels,
                    ))
                    previous_labels = current_labels
    return "\n".join(lines).rstrip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nusach", choices=sorted(p.name for p in SIDDUR.iterdir() if p.is_dir()))
    parser.add_argument("--chunk", help="export only chunks whose filename or title contains this text")
    parser.add_argument("--out-dir", type=Path, help="write one plain-text file per chunk here; otherwise write to stdout")
    args = parser.parse_args()
    dirs = [SIDDUR / args.nusach] if args.nusach else sorted(p for p in SIDDUR.iterdir() if p.is_dir())
    files = [f for d in dirs for f in sorted(d.glob("*.json")) if f.name != "book.json"]
    if args.chunk:
        needle = args.chunk.casefold()
        files = [f for f in files if needle in f.stem.casefold() or needle in json.loads(f.read_text()).get("chunk", "").casefold()]
        if not files:
            parser.error(f"no corpus chunks match {args.chunk!r}")
    if args.out_dir:
        for path in files:
            target = args.out_dir / path.parent.name / f"{path.stem}.txt"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(export_chunk(path))
        print(f"Wrote {len(files)} plain-text chunk files to {args.out_dir}")
    else:
        print("\n".join(export_chunk(path) for path in files), end="")


if __name__ == "__main__":
    main()
