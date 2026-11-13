"""Hand-placed level-1 page for u_dma (dma_rd) using the skill generator's Page/emit/tables (library cells only).
Usage: python build.py SKILL_SCRIPTS_DIR SPEC.json OUT.drawio"""
import json, sys
sys.path.insert(0, sys.argv[1])
import vlsit_drawio_frame_diagram as g

spec = json.load(open(sys.argv[2]))
gen = g.Generator(spec, 100, 110, 0)
p = g.Page("01_LEVEL_1", 2600, 3000)
gen.p = p
FX, FY, FXR, FYB = 400, 300, 1180, 680
p.block("FRAME", (FX + FXR) / 2, (FY + FYB) / 2, FXR - FX, FYB - FY, "", kind="frame")
L = {b["key"]: "<br>".join(b["label"]) for b in spec["blocks"]}
B = {}
def blk(k, x0, y0, w):
    B[k] = p.block(k, x0 + w / 2, y0 + 30, w, 60, L[k])
blk("LEG", 460, 390, 180); blk("AR", 740, 390, 100); blk("INFO", 940, 390, 180)
blk("FSM", 470, 560, 160); blk("R", 740, 560, 100); blk("WR", 950, 560, 160)

def E(name, s, d, pts, kind="func"):
    p.edge(name, B.get(s), B.get(d), pts, kind=kind)
# internal interfaces (active -> passive)
E("LOAD", "FSM", "LEG", [(550, 560), (550, 450)])
E("BST", "LEG", "AR", [(640, 420), (740, 420)])
E("PUSH", "AR", "INFO", [(840, 420), (940, 420)])
E("ar_done", "AR", "FSM", [(765, 450), (765, 505), (600, 505), (600, 560)])
E("POP", "R", "INFO", [(815, 560), (815, 505), (1030, 505), (1030, 450)])
E("RST", "R", "FSM", [(740, 590), (630, 590)])
E("BEAT", "R", "WR", [(840, 590), (950, 590)])
E("WLD", "FSM", "WR", [(520, 620), (520, 650), (990, 650), (990, 620)])
# connector labels
for k, x, y, t in [("lBST", 665, 390, "BST"), ("lPUSH", 860, 390, "PUSH"), ("lLOAD", 482, 491, "LOAD"),
                   ("lar", 640, 474, "ar_done"), ("lPOP", 900, 474, "POP"), ("lRST", 655, 558, "RST"),
                   ("lBEAT", 865, 558, "BEAT"), ("lWLD", 655, 614, "WLD")]:
    p.label(k, x, y, [t], h=28)
# boundary stubs and labels
p.label("xREQ", 140, 555, ["REQ", "request from u_ctrl"], w=200, h=50)
E("REQ", None, "FSM", [(340, 580), (470, 580)])
p.label("xAXAR", 610, 190, ["AXAR", "ARADDR, ARLEN, ARSIZE,", "ARBURST, ARID, ARVALID, ARREADY"], w=330, h=72)
E("AXAR", "AR", None, [(775, 390), (775, 262)])
p.label("xAXR", 655, 760, ["AXR", "RDATA, RRESP, RLAST,", "RID, RVALID, RREADY"], w=240, h=72)
E("AXR", None, "R", [(775, 760), (775, 620)])
p.label("xBWR", 1240, 565, ["BWR", "to u_bram_pp"], w=160, h=50)
E("BWR", "WR", None, [(1110, 590), (1240, 590)])
p.label("xCLK", 362, 200, ["CLK", "clk, rst"], w=100, h=50)
for s, d, pts in [(None, "INFO", [(412, 250), (412, 312), (1030, 312), (1030, 390)]),
                  (None, "AR", [(412, 250), (412, 312), (815, 312), (815, 390)]),
                  (None, "LEG", [(412, 250), (412, 420), (460, 420)]),
                  (None, "FSM", [(412, 250), (412, 605), (470, 605)]),
                  (None, "R", [(412, 250), (412, 668), (815, 668), (815, 620)]),
                  (None, "WR", [(412, 250), (412, 668), (1070, 668), (1070, 620)])]:
    E("CLK", s, d, pts, kind="net")
# frame label (upper-right label zone, below the clock trunk)
p.label("frame", 1060, 322, spec["top"]["frame_label"], w=110, h=50, align="right")

conns = ["LOAD", "BST", "PUSH", "ar_done", "POP", "RST", "BEAT", "WLD"]
exts = ["REQ", "AXAR", "AXR", "BWR", "CLK"]
mn = {"FSM": ["REQ", "LOAD", "ar_done", "RST", "WLD", "CLK"], "LEG": ["LOAD", "BST", "CLK"],
      "AR": ["BST", "PUSH", "ar_done", "AXAR", "CLK"], "INFO": ["PUSH", "POP", "CLK"],
      "R": ["POP", "RST", "BEAT", "AXR", "CLK"], "WR": ["BEAT", "WLD", "BWR", "CLK"]}
rows = [[spec["frame_row"][0], spec["frame_row"][1], spec["frame_row"][2], ", ".join(exts)]]
for b in spec["blocks"]:
    rows.append([b["row_name"], b["function"], b["source"], ", ".join(mn[b["key"]])])
gen.tables_and_legend(p, 900, 1, conns + exts, rows)
p.w = 2600
open(sys.argv[3], "w", encoding="utf-8").write(gen.emit([p]))
print("written", sys.argv[3])
