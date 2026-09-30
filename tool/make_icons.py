#!/usr/bin/env python3
"""Renders every platform's app icon from the Amud mark (assets/brand/).

Needs ImageMagick with librsvg. Run from the repo root:  python3 tool/make_icons.py
"""
import os
import subprocess
import tempfile

INK = '#172a5c'
PAPER = '#f8f3ea'
FAN = '#a9c0ee'
FAN_DEEP = '#6f8cc0'

LEFT = 'M97 92 C84 80 62 75 44 76 L40 30 C62 29 84 36 97 50 Z'
RIGHT = 'M103 92 C116 80 138 75 156 76 L160 30 C138 29 116 36 103 50 Z'
LINES = [(50, 106, 150, 106), (64, 119, 136, 119), (82, 133, 82, 172), (100, 133, 100, 180), (118, 133, 118, 172)]


def mark(size, x, y, stroke=7.0, mono=None):
    """The mark (viewBox 16 20 168 168) drawn size×size at x,y."""
    deep, fan, paper = (mono, mono, mono) if mono else (FAN_DEEP, FAN, PAPER)
    lines = ''.join(f'<line x1="{a}" y1="{b}" x2="{c}" y2="{d}"/>' for a, b, c, d in LINES)
    return (
        f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="16 20 168 168">'
        f'<g fill="{deep}"><path transform="rotate(-14 97 92)" d="{LEFT}"/><path transform="rotate(14 103 92)" d="{RIGHT}"/></g>'
        f'<g fill="{fan}"><path transform="rotate(-7 97 92)" d="{LEFT}"/><path transform="rotate(7 103 92)" d="{RIGHT}"/></g>'
        f'<g fill="{paper}"><path d="{LEFT}"/><path d="{RIGHT}"/></g>'
        f'<g stroke="{paper}" stroke-width="{stroke}" stroke-linecap="round" fill="none">{lines}</g>'
        '</svg>'
    )


def svg(body, size=1024):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{body}</svg>'


def stroke_for(px):
    """Thicker lines at small sizes, as on the Sizes board."""
    return 7 if px >= 200 else 7.5 if px >= 120 else 9 if px >= 64 else 11


def square(px, radius=0.0, mark_frac=700 / 1024, inset=0.0):
    """Ink tile (optionally rounded and inset, for macOS) with the mark."""
    s = 1024
    tile = s * (1 - 2 * inset)
    o = s * inset
    m = tile * mark_frac
    r = tile * radius
    return svg(f'<rect x="{o}" y="{o}" width="{tile}" height="{tile}" rx="{r}" fill="{INK}"/>'
               + mark(m, o + (tile - m) / 2, o + (tile - m) / 2, stroke_for(px)))


def foreground(mono=None):
    """Android adaptive foreground: the mark inside the 66/108 safe zone."""
    s = 1024
    m = s * 0.56
    return svg(mark(m, (s - m) / 2, (s - m) / 2, 7, mono))


def render(svg_text, out, px, opaque=False):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with tempfile.NamedTemporaryFile('w', suffix='.svg', delete=False) as f:
        f.write(svg_text)
    subprocess.run(['magick', '-background', 'none', '-density', '144', f.name,
                    '-resize', f'{px}x{px}', *(['-alpha', 'remove', '-alpha', 'off'] if opaque else []), '-depth', '8', out], check=True)
    os.unlink(f.name)


def main():
    # Master artwork, kept for reference and other uses.
    os.makedirs('assets/brand', exist_ok=True)
    with open('assets/brand/amud_icon.svg', 'w') as f:
        f.write(square(1024))
    with open('assets/brand/amud_mark.svg', 'w') as f:
        f.write(svg(mark(1024, 0, 0)))

    # Android: legacy icons, plus adaptive (background color + foreground + monochrome).
    res = 'android/app/src/main/res'
    for d, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        render(square(px, radius=0.225), f'{res}/mipmap-{d}/ic_launcher.png', px)
        fg = px * 108 // 48
        render(foreground(), f'{res}/mipmap-{d}/ic_launcher_foreground.png', fg)
        render(foreground(mono='#ffffff'), f'{res}/mipmap-{d}/ic_launcher_monochrome.png', fg)

    # iOS: square, opaque; the system rounds it.
    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for name in os.listdir(ios):
        if name.endswith('.png'):
            size = name.split('-')[-1].rsplit('.', 1)[0]  # 20x20@2x
            base, scale = size.split('@')
            px = round(float(base.split('x')[0]) * int(scale.rstrip('x')))
            render(square(px), f'{ios}/{name}', px, opaque=True)

    # macOS: rounded tile inset on a transparent canvas (Big Sur grid).
    mac = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    for px in (16, 32, 64, 128, 256, 512, 1024):
        render(square(px, radius=0.225, inset=100 / 1024), f'{mac}/app_icon_{px}.png', px)

    # Web: rounded icons, full-bleed maskable ones with the mark in the safe zone.
    render(square(32, radius=0.225), 'web/favicon.png', 32)
    for px in (192, 512):
        render(square(px, radius=0.225), f'web/icons/Icon-{px}.png', px)
        render(square(px, mark_frac=0.55), f'web/icons/Icon-maskable-{px}.png', px)

    # Windows: multi-size .ico.
    with tempfile.TemporaryDirectory() as t:
        pngs = []
        for px in (16, 24, 32, 48, 64, 128, 256):
            p = f'{t}/{px}.png'
            render(square(px, radius=0.225), p, px)
            pngs.append(p)
        subprocess.run(['magick', *pngs, 'windows/runner/resources/app_icon.ico'], check=True)


if __name__ == '__main__':
    main()
