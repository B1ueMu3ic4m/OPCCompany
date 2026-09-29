#!/usr/bin/env python3
r"""l10n_audit.py — every .L() call site's key must resolve.

The runtime lookup is the zh -> en reverse map generated from
Resources/l10n/en.json; a .L() key that is missing there silently shows
Chinese to English users. This audit is the anti-regression net:
exit 1 if any literal (non-interpolation) key is missing.
Interpolation-shaped keys ("\(x) ...") use the Localizable.strings
format machinery and are audited by generate_l10n.py itself.
"""
import json, re, glob, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
en = set(json.load(open(os.path.join(ROOT, 'Resources/l10n/en.json')))['map'].keys())

def decode_swift(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i+1]
            simple = {'n': chr(10), 't': chr(9), '"': '"', '\\': '\\', 'r': chr(13)}
            if n in simple:
                out.append(simple[n]); i += 2; continue
            if n == 'u' and i + 2 < len(s) and s[i+2] == '{':
                j = s.index('}', i + 3)
                out.append(chr(int(s[i+3:j], 16))); i = j + 1; continue
        out.append(c); i += 1
    return ''.join(out)

missing, checked, interp = {}, 0, 0
for f in glob.glob(os.path.join(ROOT, 'Sources', '**', '*.swift'), recursive=True):
    src = open(f, encoding='utf-8').read()
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*\.\s*L\(\)', src):
        raw = m.group(1)
        checked += 1
        if '\\(' in raw:
            interp += 1
            continue
        key = decode_swift(raw)
        if key not in en:
            missing.setdefault(key, os.path.relpath(f, ROOT))

print(f"checked {checked} .L() sites ({interp} interpolation-shaped), missing: {len(missing)}")
for k, f in sorted(missing.items()):
    print(f"  MISSING {k!r} @ {f}")
sys.exit(1 if missing else 0)

