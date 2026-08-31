#!/usr/bin/env python3
"""Extract Chinese string literals from OPCCompany sources into a TSV work file.

Output: /tmp/en-extract/zh_literals.tsv  (columns: id, file, count, zh)
- Scans "..." and '''...''' style literals via a small state machine per line.
- Keeps only literals containing CJK characters.
- Deduplicates globally (count shows occurrences).
- Interpolated literals \\(...) are flagged with marker [[INTERP]] for manual review.
"""
import os, re, sys, json
from collections import OrderedDict

ROOT = os.path.expanduser("~/Desktop/OPCCompany/Sources")
OUT_DIR = "/tmp/en-extract"
os.makedirs(OUT_DIR, exist_ok=True)

FILES = []
for base, dirs, names in os.walk(ROOT):
    for n in sorted(names):
        if n.endswith(".swift"):
            FILES.append(os.path.join(base, n))
FILES.sort()

CJK = re.compile(r'[\u4e00-\u9fff]')
interp = re.compile(r'\\\(')

# state machine scanning one file's content for double-quoted literals
def extract_literals(text):
    literals = []
    i, n = 0, len(text)
    in_line_comment = in_block_comment = False
    buf = None  # current literal buffer
    while i < n:
        c = text[i]
        nxt = text[i+1] if i+1 < n else ""
        if buf is None:
            if in_line_comment:
                if c == "\n": in_line_comment = False
            elif in_block_comment:
                if c == "*" and nxt == "/": in_block_comment = False; i += 1
            elif c == "/" and nxt == "/": in_line_comment = True; i += 1
            elif c == "/" and nxt == "*": in_block_comment = True; i += 1
            elif c == '"':
                # raw string? #"..."# or ###"..."###
                j = i - 1; hashes = 0
                while j >= 0 and text[j] == "#": hashes += 1; j -= 1
                buf = {"s": "", "hashes": hashes, "interp": False}
            elif c == "'" or (c == "#" and nxt != '"'):
                pass
        else:
            if c == "\\" and buf["hashes"] == 0 and nxt == "\\":
                buf["s"] += "\\\\"; i += 1
            elif c == "\\" and buf["hashes"] == 0 and nxt == '"':
                buf["s"] += '\\"'; i += 1
            elif c == "\\" and buf["hashes"] == 0 and nxt == "(":
                buf["interp"] = True
                # capture the FULL interpolation expression (nested parens safe)
                depth = 1; j = i + 2; expr = []
                while j < n and depth:
                    ch = text[j]
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    expr.append(ch); j += 1
                i = j  # lands on ')'
                buf["s"] += "\\(" + "".join(expr) + ")"
                continue
            elif buf["hashes"] > 0 and c == '"' and text[i+1:i+1+buf["hashes"]] == "#"*buf["hashes"]:
                skip = buf["hashes"]
                literals.append(buf); buf = None
                i += skip
            elif c == '"' and buf["hashes"] == 0:
                literals.append(buf); buf = None
            else:
                buf["s"] += c
        i += 1
    return literals

table = OrderedDict()
per_file = OrderedDict()
fid = 0
for path in FILES:
    rel = os.path.relpath(path, ROOT)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    file_hits = []
    for lit in extract_literals(text):
        s = lit["s"]
        if not CJK.search(s):
            continue
        key = s
        if key not in table:
            fid += 1
            table[key] = {"id": fid, "zh": s, "interp": lit["interp"], "files": []}
        if rel not in table[key]["files"]:
            table[key]["files"].append(rel)
        file_hits.append(s)
    if file_hits:
        per_file[rel] = len(file_hits)

with open(os.path.join(OUT_DIR, "zh_literals.tsv"), "w", encoding="utf-8") as f:
    f.write("id\tfile\tinterp\tzh\n")
    for s, v in table.items():
        f.write(f'{v["id"]}\t{v["files"][0]}\t{"Y" if v["interp"] else "N"}\t{s}\t\n')

with open(os.path.join(OUT_DIR, "zh_literals.json"), "w", encoding="utf-8") as f:
    json.dump([{"id": v["id"], "files": v["files"], "interp": v["interp"], "zh": s}
               for s, v in table.items()], f, ensure_ascii=False, indent=1)

with open(os.path.join(OUT_DIR, "report.json"), "w", encoding="utf-8") as f:
    json.dump({"unique": len(table), "interp": sum(1 for v in table.values() if v["interp"]),
               "per_file": per_file}, f, ensure_ascii=False, indent=1)

print("unique literals:", len(table))
print("with interpolation:", sum(1 for v in table.values() if v["interp"]))
print("--- per file occurrences ---")
for k, v in sorted(per_file.items(), key=lambda x: -x[1]):
    print(f"{v:5d}  {k}")
