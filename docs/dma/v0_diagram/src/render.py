"""Rough preview: draw.io page -> SVG (rects, text, polylines, table cells). Usage: render.py IN.drawio OUT.svg"""
import sys, re, html, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
m = root.find("diagram/mxGraphModel")
cells = {c.get("id"): c for c in m.iter("mxCell")}
def absxy(c):
    g = c.find("mxGeometry"); x = float(g.get("x", 0)); y = float(g.get("y", 0))
    p = cells.get(c.get("parent"))
    if p is not None and p.get("id") not in ("0", "1") and p.find("mxGeometry") is not None:
        px, py = absxy(p); x += px; y += py
    return x, y
out = []; W = float(m.get("pageWidth")); H = float(m.get("pageHeight"))
maxy = 0
for c in m.iter("mxCell"):
    st = c.get("style") or ""; g = c.find("mxGeometry")
    if g is None: continue
    if c.get("vertex") == "1":
        x, y = absxy(c); w = float(g.get("width", 0)); h = float(g.get("height", 0)); maxy = max(maxy, y + h)
        if "tableRow" in st: continue
        if "text;" not in st and "group" not in st[:6] and not ("strokeColor=none" in st):
            dash = ' stroke-dasharray="6,4"' if "dashed=1" in st else ""
            sw = 1 if "partialRectangle" in st else 2
            out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none" stroke="black" stroke-width="{sw}"{dash}/>')
        v = c.get("value") or ""
        if v:
            v = re.sub(r"</?b>", "", v)
            lines = [html.unescape(re.sub("<[^>]+>", "", l)) for l in re.split(r"<br\s*/?>", v)]
            al = "left" if ("align=left" in st) else ("right" if "align=right" in st else "center")
            if "shape=table" in st:
                lines = lines; ty0 = y + 28; al = "center"; hh = 40
            else:
                hh = h
            # crude wrap
            wrapped = []
            maxc = max(4, int((w - 8) / 9.5))
            for l in lines:
                while len(l) > maxc:
                    k = l.rfind(" ", 0, maxc); k = k if k > 0 else maxc
                    wrapped.append(l[:k]); l = l[k:].lstrip()
                wrapped.append(l)
            n = len(wrapped); y0 = y + hh / 2 - (n - 1) * 11 + 6
            anchor = {"left": "start", "center": "middle", "right": "end"}[al]
            tx = {"left": x + 4, "center": x + w / 2, "right": x + w - 4}[al]
            fw = ' font-weight="bold"' if "fontStyle=1" in st else ""
            for i, l in enumerate(wrapped):
                out.append(f'<text x="{tx}" y="{y0 + i*22}" font-size="18" font-family="Helvetica" text-anchor="{anchor}"{fw}>{html.escape(l)}</text>')
    elif c.get("edge") == "1":
        pts = []
        sp = g.find("mxPoint[@as='sourcePoint']"); tp = g.find("mxPoint[@as='targetPoint']"); arr = g.find("Array")
        for q in ([sp] + (list(arr) if arr is not None else []) + [tp]):
            if q is not None: pts.append((float(q.get("x")), float(q.get("y"))))
        if len(pts) >= 2:
            out.append('<polyline points="%s" fill="none" stroke="black" stroke-width="2" marker-end="url(#a)"/>' % " ".join(f"{a},{b}" for a, b in pts))
H = min(H, maxy + 40)
svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><defs><marker id="a" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M0,0 L10,5 L0,10 z"/></marker></defs><rect width="100%" height="100%" fill="white"/>' + "".join(out) + "</svg>"
open(sys.argv[2], "w").write(svg)
