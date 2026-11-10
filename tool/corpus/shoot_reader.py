#!/usr/bin/env python3
"""Screenshots of the reader, to look at a section as the app draws it.

    flutter build web -o DIR            # in a scratch copy of the project
    python3 -m http.server 8777 --directory DIR &
    python3 tool/corpus/shoot_reader.py "Siddur Sefard" "Weekday Mincha/Amidah" OUT [screens] [click X,Y]

Writes OUT_0.png, OUT_1.png… (412 wide, one per screen, scrolling down).
`click X,Y` taps a point first (a "Show" button, a jump-bar chip). Needs
Playwright for Python and Google Chrome (/usr/bin/google-chrome). The app
shows the day it is run; the setup screens are skipped.
"""
import asyncio
import sys
import urllib.parse

from playwright.async_api import async_playwright

BASE = 'http://localhost:8777'
WIDTH, HEIGHT = 412, 2400


async def shoot(book, node, out, screens, click):
    url = f"{BASE}/#/siddur/book/{urllib.parse.quote(book)}/read?node={urllib.parse.quote(node, safe='')}"
    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path='/usr/bin/google-chrome',
                                          args=['--no-sandbox', '--use-gl=swiftshader', '--enable-unsafe-swiftshader'])
        page = await (await browser.new_context(viewport={'width': WIDTH, 'height': HEIGHT})).new_page()
        await page.goto(BASE + '/')
        await page.wait_for_timeout(12000)
        await page.mouse.click(375, 28)  # setup's "Skip"
        await page.wait_for_timeout(2500)
        await page.goto(url)
        await page.wait_for_timeout(12000)
        if click:
            await page.mouse.click(*click)
            await page.wait_for_timeout(2500)
        for k in range(screens):
            await page.screenshot(path=f'{out}_{k}.png')
            await page.mouse.move(WIDTH // 2, HEIGHT // 2)
            await page.mouse.wheel(0, HEIGHT - 250)
            await page.wait_for_timeout(1500)
        await browser.close()


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    book, node, out = argv[:3]
    screens = int(argv[3]) if len(argv) > 3 else 1
    click = tuple(int(v) for v in argv[5].split(',')) if len(argv) > 5 and argv[4] == 'click' else None
    asyncio.run(shoot(book, node, out, screens, click))


if __name__ == '__main__':
    main(sys.argv[1:])
