#!/usr/bin/env python3
"""Pre-flight structural linter for Structurizr DSL workspaces.

Structurizr diagrams often can't be rendered on the spot (Java/CLI/Docker not always
available), and a 400-relationship workspace can't be eyeballed. This catches the
errors that otherwise only surface at render time — including the #1 silent trap
(a container's tag landing in the technology slot).

Usage:
    python lint_dsl.py path/to/workspace.dsl

It inlines !include files (relative to the including file), then checks:
  - brace balance
  - duplicate element identifiers
  - relationship endpoints that reference undefined identifiers
  - containers missing their tag slot (fewer than 4 quoted fields)
  - view targets (systemContext/container/component <id>) that aren't defined

Exit code 0 = clean, 1 = problems found.
"""
import os, re, sys

QS = r'"(?:[^"\\]|\\.)*"'          # a quoted string, honouring escapes
NODE_RE = re.compile(r'^\s*([A-Za-z_]\w*)\s*=\s*(softwareSystem|person|container|component)\b(.*)$', re.M)
VIEW_RE = re.compile(r'^\s*(systemContext|container|component|dynamic|deployment)\s+([A-Za-z_]\w*)\b', re.M)


def inline(path, seen=None):
    seen = seen or set()
    rp = os.path.realpath(path)
    if rp in seen:
        return f"# (skipped re-include {path})"
    seen.add(rp)
    out = []
    for ln in open(path).read().splitlines():
        m = re.match(r'\s*!include\s+(\S+)', ln)
        if m:
            inc = os.path.join(os.path.dirname(path), m.group(1))
            if os.path.exists(inc):
                out.append(inline(inc, seen))
            else:
                out.append(f"# !!! MISSING INCLUDE: {m.group(1)}")
        else:
            out.append(ln)
    return "\n".join(out)


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)   # block comments
    lines = []
    for l in text.splitlines():
        s = l.strip()
        if s.startswith('#') or s.startswith('//'):
            continue
        lines.append(l)
    return "\n".join(lines)


def quoted_count(line):
    return len(re.findall(QS, line))


def main(path):
    if not os.path.exists(path):
        print(f"ERROR: no such file: {path}");  return 1
    full = inline(path)
    body = strip_comments(full)
    errors, warnings = [], []

    # 1. missing includes surfaced during inlining
    for m in re.finditer(r'MISSING INCLUDE: (\S+)', full):
        errors.append(f"missing !include target: {m.group(1)}")

    # 2. brace balance
    o, c = body.count('{'), body.count('}')
    if o != c:
        errors.append(f"brace mismatch: {o} '{{' vs {c} '}}'")

    # 3. element ids + duplicates
    ids, dup = {}, []
    for m in NODE_RE.finditer(body):
        nid = m.group(1)
        if nid in ids:
            dup.append(nid)
        ids[nid] = m.group(2)
    for d in sorted(set(dup)):
        errors.append(f"duplicate identifier: {d}")

    # 4. relationship endpoints
    idset = set(ids)
    def unquote(l): return re.sub(QS, '""', l)
    undefined = set()
    for l in body.splitlines():
        if 'include' in l or 'exclude' in l:   # view expressions use -> too
            continue
        rm = re.match(r'\s*([A-Za-z_]\w*)\s*->\s*([A-Za-z_]\w*)', unquote(l))
        if rm:
            for e in rm.groups():
                if e not in idset:
                    undefined.add(e)
    for u in sorted(undefined):
        errors.append(f"relationship references undefined id: {u}")

    # 5. container tag-slot trap: container needs name+desc+technology+tags (4 quoted)
    tagless = []
    for l in body.splitlines():
        if re.match(r'\s*[A-Za-z_]\w*\s*=\s*container\b', l) and quoted_count(l) < 4:
            m = NODE_RE.match(l)
            tagless.append(m.group(1) if m else l.strip()[:50])
    for t in tagless:
        warnings.append(f"container '{t}' has <4 quoted fields — tag may be in the "
                        f"technology slot (element will be untagged, styles won't apply). "
                        f"Use: container \"name\" \"desc\" \"tech-or-empty\" \"Tags\"")

    # 6. view targets
    for m in VIEW_RE.finditer(body):
        kind, tgt = m.group(1), m.group(2)
        if kind in ('systemContext', 'container', 'component') and tgt not in idset:
            errors.append(f"{kind} view targets undefined id: {tgt}")

    # report
    print(f"lint: {path}")
    print(f"  elements: {len(ids)}  |  relationships checked, "
          f"undefined endpoints: {len(undefined)}")
    print(f"  braces: {o}/{c}")
    if warnings:
        print(f"\n  WARNINGS ({len(warnings)}):")
        for w in warnings: print("   ⚠ " + w)
    if errors:
        print(f"\n  ERRORS ({len(errors)}):")
        for e in errors: print("   ✗ " + e)
        print("\nRESULT: FAIL")
        return 1
    print("\nRESULT: PASS" + ("  (with warnings)" if warnings else "  ✓"))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python lint_dsl.py path/to/workspace.dsl"); sys.exit(2)
    sys.exit(main(sys.argv[1]))
