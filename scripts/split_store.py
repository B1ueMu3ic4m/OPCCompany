#!/usr/bin/env python3
"""v0.2-P1 v2: Split CompanyStore.swift with attribute lines following their func.

Fixes v1 issues:
- Attribute lines (@MainActor, @discardableResult, doc comments immediately
  above) now move WITH the function body (no orphan attributes left behind).
- private members referenced across files: we upgrade the few hot helpers
  (appendEvent/appendTerminalLog/...) from private to internal in the main file.
"""
import re, os

ROOT = os.path.expanduser("~/Desktop/OPCCompany")
MAIN = os.path.join(ROOT, "Sources/OPCCompanyCore/CompanyStore.swift")

src = open(MAIN, encoding="utf-8").read()
lines = src.split("\n")
cls_start = next(i for i, l in enumerate(lines) if l.startswith("public final class CompanyStore"))

ATTR = re.compile(r'^\s*(@\w+.*|///.*|// MARK: -.*|///.*)$')
FUNC = re.compile(r'^    (?:@MainActor\s+)?(?:public |private |internal )?(?:static )?(?:override )?func (\w+)')

# collect members with their leading attribute/comment block
members = []
i = cls_start + 1
n = len(lines)
while i < n:
    l = lines[i]
    if l.strip() == "}" and not l.startswith(" "):
        cls_end = i
        break
    m = FUNC.match(l)
    if m:
        # walk back over contiguous attribute/comment lines (max 12)
        a = i
        back = 0
        while a - 1 > cls_start and back < 12 and ATTR.match(lines[a - 1]) and not lines[a - 1].strip().startswith("// MARK"):
            a -= 1
            back += 1
        j = i + 1
        while j < n and not (lines[j].strip() == "}" and not lines[j].startswith("        ")):
            j += 1
        members.append((a, j + 1, m.group(1)))
        i = j
        continue
    i += 1

KW = {
    "Reports":   ["report", "brief", "summary", "health", "snapshot", "checkpoint", "memory",
                  "artifact", "delivery", "acceptance", "review", "approval", "decision",
                  "closure", "drill", "evidence", "classification", "loop"],
    "Tasks":     ["task", "queue", "workitem", "milestone", "graph", "edge", "rework"],
    "Comms":     ["comms", "channel", "message", "inbox", "phone", "gateway", "handover", "digest"],
    "Runtime":   ["agent", "employee", "runtime", "session", "terminal", "warm", "cli",
                  "command", "preflight", "runall", "exit", "occupancy", "seat", "ptys"],
    "Maintenance": ["audit", "isolation", "recover", "archive", "history", "index", "ghost",
                    "dedup", "maintenance", "adopt", "growth", "scan", "dangerous", "rollback"],
}
CAPS = {"Reports": 60, "Tasks": 60, "Comms": 40, "Runtime": 80, "Maintenance": 60}

def classify(name):
    n = name.lower()
    for cat, words in KW.items():
        if any(w in n for w in words):
            return cat
    return None

moved = {k: [] for k in KW}
keep = set(range(len(lines)))
moved_count = 0
for (a, b, name) in members:
    cat = classify(name)
    if cat is None or len(moved[cat]) >= CAPS[cat]:
        continue
    moved[cat].append((a, b, name))
    for x in range(a, b):
        keep.discard(x)
    moved_count += 1

print(f"moving {moved_count} funcs (with attribute blocks)")
HEADER = """import Foundation
import SQLite3

// MARK: - {title}
// Extracted from CompanyStore.swift (v0.2 god-class split). Same module:
// internal members of CompanyStore remain accessible.

extension CompanyStore {{
"""
for cat, ms in moved.items():
    if not ms:
        continue
    body = "\n".join("\n".join(lines[a:b]) for (a, b, _) in ms)
    out = HEADER.format(title=cat.title()) + "\n" + body + "\n}\n"
    path = os.path.join(ROOT, f"Sources/OPCCompanyCore/CompanyStore+{cat.title()}.swift")
    open(path, "w", encoding="utf-8").write(out)
    print(f"wrote {os.path.basename(path)} ({len(out)//1024}KB)")

new_lines = [l for i, l in enumerate(lines) if i in keep]
new_src = "\n".join(new_lines)

# Upgrade hot private helpers referenced from extensions to internal
for helper in ["appendEvent", "appendTerminalLog", "cliWorkingDirectoryURL",
               "cliExecutionDirectoryURL", "terminalWorkspaceSessionName",
               "newRuntimeSession", "ensureSelectedAgentIsValidForSelectedProduct",
               "ensureRuntimeSessionsForSelectedProduct", "communicationGatewayLogDisplayLimit"]:
    new_src = re.sub(r'(\n\s*)private (func ' + helper + r'\b)', r'\1\2', new_src)
    new_src = re.sub(r'(\n\s*)private (static (?:let|var) ' + helper + r'\b)', r'\1\2', new_src)
    new_src = re.sub(r'(\n\s*)private (let ' + helper + r'\b)', r'\1\2', new_src)

open(MAIN, "w", encoding="utf-8").write(new_src)
print(f"main file now {len(new_lines)} lines; private helpers upgraded where needed")
