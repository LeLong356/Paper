"""Merge single-page generator outputs into one multi-page .drawio, fix stray connector labels, mark dashed blocks.

Usage: python merge_pages.py OUT.drawio SPECDIR GENDIR PAGE1 [PAGE2 ...]
For every page NAME it reads SPECDIR/NAME.json and GENDIR/NAME/vlsit_rtl_hierarchy.drawio.
Spec extension: block field "dashed": true adds dashed=1 to that block (RHD-047, permitted property).
"""
import json, re, sys, xml.etree.ElementTree as ET

out, specdir, gendir, names = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]


def seg_hits_rect(a, b, r, m=2):
    x0, y0, x1, y1 = r[0] - m, r[1] - m, r[0] + r[2] + m, r[1] + r[3] + m
    if a[0] == b[0]:
        return x0 < a[0] < x1 and min(a[1], b[1]) < y1 and max(a[1], b[1]) > y0
    return y0 < a[1] < y1 and min(a[0], b[0]) < x1 and max(a[0], b[0]) > x0


def dist_rect_seg(r, a, b):
    dx = max(r[0] - max(a[0], b[0]), min(a[0], b[0]) - (r[0] + r[2]), 0)
    dy = max(r[1] - max(a[1], b[1]), min(a[1], b[1]) - (r[1] + r[3]), 0)
    return (dx * dx + dy * dy) ** 0.5


def overlap(r, q, m=4):
    return not (r[0] + r[2] + m <= q[0] or q[0] + q[2] + m <= r[0] or r[1] + r[3] + m <= q[1] or q[1] + q[3] + m <= r[1])


diagrams, report = [], []
for name in names:
    spec = json.load(open(f"{specdir}/{name}.json"))
    root = ET.parse(f"{gendir}/{name}/vlsit_rtl_hierarchy.drawio").getroot()
    d = root.find("diagram")
    d.set("id", name); d.set("name", name)
    m = d.find("mxGraphModel")
    cells = list(m.iter("mxCell"))
    byval = {c.get("value"): c for c in cells if c.get("vertex") == "1"}
    geo = lambda c: tuple(float(c.find("mxGeometry").get(k, 0)) for k in ("x", "y", "width", "height"))
    # dashed outline for undecided blocks
    for b in spec["blocks"]:
        if b.get("dashed"):
            c = byval["<br>".join(b["label"])]
            c.set("style", c.get("style") + "dashed=1;")
    # connector edges in spec order
    keyid = {b["key"]: byval["<br>".join(b["label"])].get("id") for b in spec["blocks"]}
    edges = [c for c in cells if c.get("edge") == "1" and c.get("parent") == "1"]
    def pts(c):
        g = c.find("mxGeometry")
        p = [g.find("mxPoint[@as='sourcePoint']")]
        arr = g.find("Array")
        p += list(arr) if arr is not None else []
        p.append(g.find("mxPoint[@as='targetPoint']"))
        return [(float(q.get("x")), float(q.get("y"))) for q in p if q is not None]
    used, conn_edge = set(), {}
    for cn in spec["connectors"]:
        for e in edges:
            if e.get("source") == keyid[cn["src"]] and e.get("target") == keyid[cn["dst"]] and id(e) not in used:
                used.add(id(e)); conn_edge[cn["id"]] = e; break
    blocks = [geo(c) for c in cells if c.get("vertex") == "1" and "text;" not in (c.get("style") or "")
              and "vlsit_native_table" not in c.attrib and "group" not in (c.get("style") or "")[:6]]
    frame = max(blocks, key=lambda r: r[2] * r[3])
    blocks = [r for r in blocks if r != frame]
    labels = {c.get("value"): c for c in cells if "text;" in (c.get("style") or "")}
    allsegs = [(p[i], p[i + 1]) for e in edges for p in [pts(e)] for i in range(len(p) - 1)]
    for cid, e in conn_edge.items():
        lab = labels.get(cid)
        if lab is None:
            continue
        r = geo(lab); p = pts(e)
        segs = [(p[i], p[i + 1]) for i in range(len(p) - 1)]
        if min(dist_rect_seg(r, a, b) for a, b in segs) <= 30:
            continue
        others = [geo(c) for k, c in labels.items() if c is not lab]
        w, h = r[2], r[3]
        best = None
        for a, b in sorted(segs, key=lambda s: -abs(s[0][0] - s[1][0]) - abs(s[0][1] - s[1][1])):
            mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            if a[1] == b[1]:
                cands = [(mx - w / 2, my - h - 2), (mx - w / 2, my + 2), (min(a[0], b[0]) + 6, my - h - 2), (max(a[0], b[0]) - w - 6, my - h - 2)]
            else:
                cands = [(mx + 4, my - h / 2), (mx - w - 4, my - h / 2), (mx + 4, min(a[1], b[1]) + 4), (mx + 4, max(a[1], b[1]) - h - 4)]
            for cx, cy in cands:
                q = (cx, cy, w, h)
                inside = frame[0] < cx and cx + w < frame[0] + frame[2] and frame[1] < cy and cy + h < frame[1] + frame[3]
                if inside and not any(overlap(q, bl, 2) for bl in blocks) and not any(overlap(q, o) for o in others) \
                        and not any(seg_hits_rect(s0, s1, q, 1) for s0, s1 in allsegs):
                    best = q; break
            if best:
                break
        if best:
            g = lab.find("mxGeometry"); g.set("x", f"{best[0]:g}"); g.set("y", f"{best[1]:g}")
            report.append(f"{name}: moved label {cid} next to its connector")
        else:
            report.append(f"{name}: LABEL {cid} could not be moved")
    # page size covers all content (tables are 2400 px wide)
    xs = [geo(c)[0] + geo(c)[2] for c in cells if c.get("vertex") == "1" and c.get("parent") == "1"]
    m.set("pageWidth", str(int(max(xs) + 100)))
    diagrams.append(d)

mx = ET.Element("mxfile", {"host": "app.diagrams.net", "agent": "VLSIT RTL hierarchy analysis", "version": "24.7.17", "compressed": "false"})
mx.extend(diagrams)
ET.indent(mx)
open(out, "w", encoding="utf-8").write('<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(mx, encoding="unicode") + "\n")
print("\n".join(report) or "no label moved")
