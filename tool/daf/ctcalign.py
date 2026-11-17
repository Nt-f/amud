#!/usr/bin/env python3
"""Known text against a line's ink, with the line reader trained on these
pages (nn_data.py, ketos train): how well a span of a text's words fits a
printed line (the reader's loss for it, per letter). Reading a line freely
fails where print is small or worn; scoring words we already know only
needs the reader to prefer the right ones.

Runs in kraken's venv (build/daf/kraken-venv/bin/python).

    ctcalign.py MODEL SCAN x0,x1,base,h "words..." ["other candidate" ...]
"""

import sys

import torch
import torch.nn.functional as F
from kraken.configs import RecognitionInferenceConfig
from kraken.containers import BaselineLine, Segmentation
from kraken.lib.bidi import get_display
from kraken.models import load_models
from PIL import Image


def _line(l, i=0):
    x0, x1, b, h = (int(round(l[k])) for k in ('x0', 'x1', 'base', 'h'))
    return BaselineLine(id=f'l{i}', baseline=[(x0, b), (x1, b)],
                        boundary=[(x0, int(b - 1.2 * h)), (x1, int(b - 1.2 * h)), (x1, int(b + 0.45 * h)), (x0, int(b + 0.45 * h))])


class Reader:
    def __init__(self, model, device='cuda:0' if torch.cuda.is_available() else 'cpu'):
        self.net = [m for m in load_models(model) if 'recognition' in m.model_type][0]
        self.net.to(device)
        self.net.eval()
        self.config = RecognitionInferenceConfig(return_logits=True, return_line_image=True, bidi_reordering='R')
        self.net.prepare_for_inference(self.config)

    @torch.inference_mode()
    def emissions(self, im, lines):
        """Per line (dicts of x0, x1, base, h in the scan's pixels), the
        reader's log-probabilities along it: (frames, classes)."""
        seg = Segmentation(type='baselines', imagename='', text_direction='horizontal-rl', script_detection=False,
                           lines=[_line(l, i) for i, l in enumerate(lines)])
        out = []
        self.geometry = []
        for l, rec in zip(lines, self.net.predict(im=im, segmentation=seg)):
            lg = getattr(rec, 'logits', None)
            # (kraken returns the softmax already: probabilities, classes × frames.)
            out.append(None if lg is None else lg.squeeze().float().clamp_min(1e-12).log().T.cpu())
            # Frame t's page x: the line image starts at the line's x0; the
            # network sees it scaled to its height and padded each side.
            T = out[-1].shape[0] if out[-1] is not None else 0
            img = getattr(rec, 'image', None)
            if T and img is not None:
                ns = (img.width / self.config.padding if False else None)
                net_in = img.width * (120 / img.height) + 2 * self.config.padding
                k, s = net_in / T, img.height / 120
                self.geometry.append((l['x0'], k, s, self.config.padding))
            else:
                self.geometry.append(None)
        return out

    def align(self, em, geo, words):
        """Each of `words` (in the text's order) as (x0, x1) on the page,
        and the loss per letter of them all on the line: a best path of
        their letters through the line's frames. None where it can't be
        done (a word with no letter the reader knows)."""
        import unicodedata
        if em is None or geo is None:
            return None, float('inf')
        text = ' '.join(words)
        vis = get_display(unicodedata.normalize('NFC', text), base_dir='R')
        labs, owner = [], []
        # The visual string's words are the text's, last first.
        wi = len(words) - 1
        for c in vis:
            if c == ' ':
                wi -= 1
            try:
                v = [int(x) for x in self.net.codec.encode(c)]
            except Exception:  # noqa: BLE001
                continue
            labs += v
            owner += [wi] * len(v)
        if wi != 0 or not labs:
            return None, float('inf')
        T, S = em.shape[0], len(labs)
        if 2 * S + 1 > 2 * T:
            return None, float('inf')
        # Viterbi over the CTC states (blank, l1, blank, l2, ...).
        ext = [0] + [x for v in labs for x in (v, 0)]
        n = len(ext)
        e = em[:, ext]  # T × n
        NEG = -1e9
        dp = torch.full((n,), NEG)
        dp[0], dp[1] = e[0, 0], e[0, 1]
        back = torch.zeros((T, n), dtype=torch.int8)
        skip = torch.tensor([i >= 2 and ext[i] != 0 and ext[i] != ext[i - 2] for i in range(n)])
        for t in range(1, T):
            a = dp
            b = torch.cat([torch.tensor([NEG]), dp[:-1]])
            c = torch.where(skip, torch.cat([torch.tensor([NEG, NEG]), dp[:-2]]), torch.tensor(NEG))
            stack = torch.stack([a, b, c])
            best, arg = stack.max(0)
            dp = best + e[t]
            back[t] = arg.to(torch.int8)
        end = n - 1 if dp[n - 1] >= dp[n - 2] else n - 2
        score = float(dp[end])
        state, frames = end, [[] for _ in range(S)]
        for t in range(T - 1, -1, -1):
            if state % 2 == 1:
                frames[state // 2].append(t)
            state -= int(back[t, state]) if t > 0 else 0
        x0, k, s, pad = geo
        xs = {}
        for i, fr in enumerate(frames):
            if not fr:
                continue
            w = owner[i]
            lo, hi = min(fr), max(fr) + 1
            px0, px1 = x0 + (lo * k - pad) * s, x0 + (hi * k - pad) * s
            a_, b_ = xs.get(w, (px0, px1))
            xs[w] = (min(a_, px0), max(b_, px1))
        if len(xs) != len(words):
            return None, float('inf')
        return [xs[w] for w in range(len(words))], -score / S

    def labels(self, text):
        """The text as the reader's labels, in display order as ketos
        trained it (-u NFC --base-dir R); letters it never saw dropped."""
        import unicodedata
        vis = get_display(unicodedata.normalize('NFC', text), base_dir='R')
        out = []
        for c in vis:
            try:
                out += [int(v) for v in self.net.codec.encode(c)]
            except Exception:  # noqa: BLE001
                pass
        return out

    def score(self, em, text):
        """Loss per letter of the text on a line's emissions (lower is
        better); inf where it can't fit."""
        y = self.labels(text)
        if em is None or not y or 2 * len(y) > em.shape[0]:
            return float('inf')
        loss = F.ctc_loss(em.unsqueeze(1), torch.tensor([y]), torch.tensor([em.shape[0]]), torch.tensor([len(y)]),
                          blank=0, reduction='sum', zero_infinity=True)
        return float(loss) / len(y)

    def read(self, em):
        """The reader's own greedy reading of a line, in logical order."""
        best = em.argmax(1).tolist()
        labs, prev = [], 0
        for b in best:
            if b != prev and b != 0:
                labs.append(b)
            prev = b
        s = ''.join(d[0] for d in self.net.codec.decode([(l, 0, 0, 0) for l in labs]))
        return get_display(s, base_dir='R')


def main():
    model, scan, box, *texts = sys.argv[1:]
    x0, x1, b, h = (float(v) for v in box.split(','))
    r = Reader(model)
    em = r.emissions(Image.open(scan), [dict(x0=x0, x1=x1, base=b, h=h)])[0]
    print('read:', r.read(em))
    for t in texts:
        print(f'{r.score(em, t):7.3f}  {t}')


if __name__ == '__main__':
    main()
