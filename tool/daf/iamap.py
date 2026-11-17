#!/usr/bin/env python3
"""Which leaf of archive.org's "Talmud Bavli, Shas Vilna" (item
Talmud_Bavli_Vilna_images, the Vilna "A" set, public domain) is each amud:
the same printing as Sefaria's scans, at about 2.4× the pixels.

    iamap.py map [BOOK ...]          # leaves.json: amud → volume, leaf, share
    iamap.py fetch --pages FILE      # their JPEGs into CACHE_IA/scan
    iamap.py verify --pages FILE     # the share of each scan's own page OCR

Mapping: archive.org's own OCR of every leaf (hocr_searchtext + its page
index, a few MB a volume) against each amud's Gemara word pairs, as
scanmatch.py counts them. Rashi script comes out of that OCR as noise, but
the Gemara's square type reads well enough. Leaves run in amud order with a
few plates and title pages between, so an amud whose own match is weak takes
the leaf its well-matched neighbours' offset gives. `verify` checks the
fetched scan with our heb_vilna page OCR (CACHE_IA/ocr), as scanmatch does:
its own Gemara's share against its two neighbours' either side.
"""

import argparse
import gzip
import json
import os
import statistics
import subprocess
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/daf/ia'
CACHE = ROOT / 'build/daf/cache'
CACHE_IA = Path(os.environ.get('DAF_CACHE', ROOT / 'build/daf/cache_ia'))
ITEM = 'https://archive.org/download/Talmud_Bavli_Vilna_images/'
VOLUMES = {
    'V01_Berakhot_Seder-Zera\'im_1884': ['Berakhot'],
    'V02_Shabbat_1883': ['Shabbat'],
    'V03_\'Eruvin_1887': ['Eruvin'],
    'V04_Pesahim_Beizah_1886': ['Pesachim', 'Beitzah'],
    'V05_Rosh-Hashanah_Yoma_Yerushalmi-Sheqalim_Sukkah_1887': ['Rosh Hashanah', 'Yoma', 'Sukkah'],
    'V06_Megillah_Mo\'ed-Qatan_Hagigah_Ta\'anit_1886': ['Megillah', 'Moed Katan', 'Chagigah', 'Taanit'],
    'V07_Yevamot_1883': ['Yevamot'],
    'V08_Ketubbot_1887': ['Ketubot'],
    'V09_Nedarim_Nazir_1884': ['Nedarim', 'Nazir'],
    'V10_Gittin_1886': ['Gittin'],
    'V11_Qiddushin_Sotah_1884': ['Kiddushin', 'Sotah'],
    'V12_Bava-Qamma_1882': ['Bava Kamma'],
    'V13_Bava-Mezi\'a_1882': ['Bava Metzia'],
    'V14_Bava-Batra_1886': ['Bava Batra'],
    'V15_Sanhedrin_Shevu\'ot_1887': ['Sanhedrin', 'Shevuot'],
    'V16_\'Avodah-Zarah_Horayot_\'Eduyyot_Makkot_Avot_Masekhtot-Qetanot_Makkot_1883': ['Avodah Zarah', 'Horayot', 'Makkot'],
    'V17_Zevahim_Menahot_1884': ['Zevachim', 'Menachot'],
    'V18_Hullin_1885': ['Chullin'],
    'V19_Bekhorot_\'Arakhin_Temurah_Keritot_Me\'ilah_Qinnim_Tamid_Middot_1885': ['Bekhorot', 'Arakhin', 'Temurah', 'Keritot', 'Meilah', 'Tamid'],
}
VOLUME_OF = {b: v for v, bs in VOLUMES.items() for b in bs}


def _name(v):
    return f'Talmud_Bavli_Vilna_A_{v}_images'


def _get(url, path):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + '.part')
        subprocess.run(['curl', '-sfL', '--retry', '5', '-o', str(tmp), url], check=True)
        tmp.rename(path)
    return path


def leaf_texts(v):
    """archive.org's OCR of each leaf of a volume, by leaf number."""
    n = _name(v)
    q = urllib.parse.quote(n)
    st = _get(ITEM + q + '_hocr_searchtext.txt.gz', OUT / 'ocr' / f'{v}_searchtext.txt.gz')
    pi = _get(ITEM + q + '_hocr_pageindex.json.gz', OUT / 'ocr' / f'{v}_pageindex.json.gz')
    text = gzip.open(st, 'rt', encoding='utf-8').read()
    index = json.loads(gzip.open(pi).read())
    return [text[a:b] for a, b, *_ in index]


def map_book(book, leaves, scanmatch):
    import shas
    amudim = [a for _, a in shas.pages({book})]
    lp = [scanmatch.pairs([scanmatch.norm(w) for w in t.split() if scanmatch.norm(w)]) for t in leaves]
    best = []
    for k, amud in enumerate(amudim):
        g = scanmatch.gemara(CACHE, book, amud)
        if not g or len(g) < 20:
            best.append(None)
            continue
        gp = scanmatch.pairs(g)
        shares = sorted(((len(gp & p) / len(gp), i) for i, p in enumerate(lp)), reverse=True)
        (s1, l1), (s2, _) = shares[0], shares[1]
        best.append((l1 - k, s1, s2))
    out = {}
    for k, amud in enumerate(amudim):
        near = [b[0] for b in best[max(0, k - 6):k + 7] if b and b[1] >= 0.15 and b[1] > 1.5 * b[2]]
        mine = best[k]
        # (Its own best leaf, unless it breaks the order its neighbours
        # keep: the commentaries printed at the back of a volume quote the
        # Gemara too, and Nedarim 45b's own best was one of them.)
        mid = int(statistics.median(near)) if near else None
        if mine and mine[1] >= 0.15 and mine[1] > 1.5 * mine[2] and (mid is None or abs(mine[0] - mid) <= 2):
            off, how = mine[0], 'own'
        elif near:
            off, how = int(statistics.median(near)), 'neighbours'
        else:
            continue
        g = scanmatch.gemara(CACHE, book, amud) or []
        gp = scanmatch.pairs(g)
        s = len(gp & lp[k + off]) / len(gp) if gp and 0 <= k + off < len(lp) else 0
        out[f'{book} {amud}'] = dict(volume=_name(VOLUME_OF[book]), leaf=k + off, ia_share=round(s, 3), by=how)
    return out


def jp2_url(volume, leaf):
    q = urllib.parse.quote(volume, safe='')
    return f'{ITEM}{q}_jp2.zip/{q}_jp2%2F{q}_{leaf:04d}.jp2'


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('stage', choices=('map', 'fetch', 'verify'))
    p.add_argument('books', nargs='*')
    p.add_argument('--pages', type=Path)
    a = p.parse_args()
    leaves_path = OUT / 'leaves.json'
    mapping = json.loads(leaves_path.read_text()) if leaves_path.exists() else {}
    pages = [s for s in a.pages.read_text().splitlines() if s.strip()] if a.pages else []
    if a.stage == 'map':
        import scanmatch
        books = a.books or sorted({s.rsplit(' ', 1)[0] for s in pages})
        for v in sorted({VOLUME_OF[b] for b in books}):
            leaves = leaf_texts(v)
            for b in [b for b in VOLUMES[v] if b in books]:
                m = map_book(b, leaves, scanmatch)
                mapping.update(m)
                weak = [k for k, e in m.items() if e['ia_share'] < 0.15]
                print(f'{b}: {len(m)} amudim mapped, {len(weak)} weak {weak[:6]}', flush=True)
        leaves_path.write_text(json.dumps(mapping, ensure_ascii=False, indent=0))
    elif a.stage == 'fetch':
        from PIL import Image
        from concurrent.futures import ThreadPoolExecutor

        def one(page):
            e = mapping.get(page)
            if not e:
                return page, 'unmapped'
            book, amud = page.rsplit(' ', 1)
            dest = CACHE_IA / 'scan' / f'{book}_{amud}.jpg'
            if dest.exists():
                return page, None
            jp2 = OUT / 'jp2' / f'{book}_{amud}.jp2'
            _get(jp2_url(e['volume'], e['leaf']), jp2)
            dest.parent.mkdir(parents=True, exist_ok=True)
            Image.open(jp2).convert('RGB').save(dest, quality=95)
            return page, None
        with ThreadPoolExecutor(4) as ex:
            for page, err in ex.map(one, pages):
                if err:
                    print(page, err, flush=True)
    else:
        import scanmatch
        bad = 0
        for page in pages:
            book, amud = page.rsplit(' ', 1)
            o = scanmatch.ocr_words(CACHE_IA, book, amud, 'heb_vilna')
            g = scanmatch.gemara(CACHE, book, amud)
            if not o or not g:
                print(page, 'no OCR' if not o else 'no text')
                continue
            po = scanmatch.pairs(o)
            own = len(scanmatch.pairs(g) & po) / len(scanmatch.pairs(g))
            other = 0.0
            for step in (-2, -1, 1, 2):
                x = amud
                for _ in range(abs(step)):
                    x = scanmatch.linemap.neighbor(x, 1 if step > 0 else -1) if x else None
                gn = scanmatch.gemara(CACHE, book, x) if x else None
                if gn and len(gn) >= 20:
                    other = max(other, len(scanmatch.pairs(gn) & po) / len(scanmatch.pairs(gn)))
            ok = own > 0.4 and own > other or len(g) < 40 and own > other
            if page in mapping:
                mapping[page].update(own=round(own, 3), neighbour=round(other, 3), verified=ok)
            if not ok:
                bad += 1
                print(f'{page:22} own {own:.2f} neighbour {other:.2f} ({len(g)} words)')
        leaves_path.write_text(json.dumps(mapping, ensure_ascii=False, indent=0))
        print(f'{bad} of {len(pages)} not verified')


if __name__ == '__main__':
    main()
