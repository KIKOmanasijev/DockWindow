#!/usr/bin/env python3
"""Static check that the app template and the landing page agree with Config/commercial.json.

Reads files only. Run it before deploying the website or building a release.
"""
import fnmatch
import json
from pathlib import Path
import plistlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Scripts'))
import license_packaging as packaging  # noqa: E402

LANDING = ROOT / 'landing'
TEXT = {'.html', '.js', '.json', '.txt', '.xml', '.css'}


def deployed(path):
    """Landing files Vercel uploads: everything not matched by .vercelignore."""
    patterns = [line.strip() for line in (LANDING / '.vercelignore').read_text().splitlines()
                if line.strip() and not line.startswith('#')]
    rel = path.relative_to(LANDING).as_posix()
    return not any(fnmatch.fnmatch(rel, p.rstrip('/') + ('/*' if p.endswith('/') else '')) or fnmatch.fnmatch(path.name, p)
                   for p in patterns)


def check():
    problems = []
    policy = packaging.load_policy()
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    leaked = [k for k in packaging.LICENSE_KEYS + ('DogBarCommercialMode',) if k in info]
    if leaked:
        problems.append(f'Resources/Info.plist must not set {", ".join(leaked)}; packaging adds them')
    if policy['mode'] == 'paid':
        problems.append('The landing page only has a free presentation. Build and verify the paid page, '
                        'with a live checkout, before switching Config/commercial.json to paid')
        return problems

    future = f"{policy['paid']['priceCents'] / 100:.2f}"
    future_re = re.compile(rf'(?<![\d.]){re.escape(future)}(?!\d)|priceCents')
    for path in sorted(LANDING.rglob('*')):
        if path.suffix not in TEXT or not path.is_file() or not deployed(path):
            continue
        text = path.read_text(errors='replace')
        if future_re.search(text):
            problems.append(f'{path.relative_to(ROOT)} mentions an internal paid price')
        if path.suffix in ('.html', '.txt') and re.search(r'\$\s?\d|lifetime licen|one-time payment|data-checkout|data-launch-signup', text, re.I):
            problems.append(f'{path.relative_to(ROOT)} contains purchase or signup copy')

    html = (LANDING / 'index.html').read_text()
    graph = json.loads(re.search(r'<script type="application/ld\+json">(.*?)</script>', html, re.S).group(1))['@graph']
    app = next(entry for entry in graph if entry.get('@type') == 'SoftwareApplication')
    offer = app.get('offers') or {}
    if offer.get('price') != '0' or offer.get('priceCurrency') != 'USD':
        problems.append('index.html structured data must offer DogBar at price "0" USD')
    if len(re.findall(r'<a class="btn btn-download" data-download\b', html)) != 2:
        problems.append('index.html needs the hero and banner Download buttons')
    if json.loads((LANDING / 'checkout.json').read_text()).get('enabled') is not False:
        problems.append('landing/checkout.json must stay disabled in free mode')
    return problems


if __name__ == '__main__':
    found = check()
    for problem in found:
        print('commercial policy:', problem, file=sys.stderr)
    if not found:
        print('commercial policy: free; app template and landing agree')
    sys.exit(1 if found else 0)
