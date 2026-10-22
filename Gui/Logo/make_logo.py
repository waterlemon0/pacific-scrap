"""Pacific Scrap logo as plain vector paths (logo.svg)."""
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

OUT = sys.argv[1]
BLACK = "#111111"
ORANGE = "#F7931E"

bahn = instancer.instantiateVariableFont(TTFont(r"C:\Windows\Fonts\bahnschrift.ttf"), {"wght": 700, "wdth": 75})
goth = TTFont(r"C:\Windows\Fonts\GOTHICB.TTF")


def word(font, text, x, baseline, cap_height, tracking):
	"""Paths for `text` with its caps `cap_height` tall, starting at x. Returns (svg paths, letter boxes, width)."""
	gs = font.getGlyphSet()
	cmap = font.getBestCmap()
	upm = font["head"].unitsPerEm
	# (scale from the font's own capital height: the H)
	b = BoundsPen(gs); gs[cmap[ord("H")]].draw(b)
	scale = cap_height / (b.bounds[3] - b.bounds[1])
	paths, boxes = [], []
	pen_x = x
	for i, ch in enumerate(text):
		name = cmap[ord(ch)]
		glyph = gs[name]
		lsb = font["hmtx"][name][1]
		bp = BoundsPen(gs); glyph.draw(bp)
		x0, y0, x1, y1 = bp.bounds
		# (letters placed by their ink, so the tracking is even)
		ox = pen_x - x0 * scale
		svg = SVGPathPen(gs)
		glyph.draw(TransformPen(svg, (scale, 0, 0, -scale, ox, baseline)))
		paths.append(svg.getCommands())
		boxes.append((pen_x, baseline - y1 * scale, pen_x + (x1 - x0) * scale, baseline - y0 * scale))
		pen_x += (x1 - x0) * scale + (tracking if i < len(text) - 1 else 0)
	return paths, boxes, pen_x - x


W, H = 1200, 600
# Frame (two rounded rectangles, like Pacific Drive's)
fx0, fy0, fx1, fy1 = 70, 70, W - 70, 470
gap_in = 22          # between the two lines
line = 12            # line thickness

# PACIFIC: tall condensed, centred in the frame
cap = 214
p_paths, p_boxes, p_w = word(bahn, "PACIFIC", 0, 0, cap, 42)
px = (W - p_w) / 2
py = 116 + cap
p_paths, p_boxes, _ = word(bahn, "PACIFIC", px, py, cap, 42)

# SCRAP: round and heavy, sitting on the bottom of the frame
s_cap = 112
s_paths, s_boxes, s_w = word(goth, "SCRAP", 0, 0, s_cap, 12)
sx = (W - s_w) / 2
sy = fy1 + s_cap / 2 - gap_in / 2
s_paths, s_boxes, _ = word(goth, "SCRAP", sx, sy, s_cap, 12)
gap_pad = 26
g0, g1 = sx - gap_pad, sx + s_w + gap_pad

def frame_path(inset, r):
	x0, y0, x1, y1 = fx0 + inset, fy0 + inset, fx1 - inset, fy1 - inset
	# (open at the bottom where SCRAP sits)
	return (f"M{g0:.1f},{y1} L{x0 + r},{y1} A{r},{r} 0 0 1 {x0},{y1 - r} L{x0},{y0 + r} A{r},{r} 0 0 1 {x0 + r},{y0} "
		f"L{x1 - r},{y0} A{r},{r} 0 0 1 {x1},{y0 + r} L{x1},{y1 - r} A{r},{r} 0 0 1 {x1 - r},{y1} L{g1:.1f},{y1}")

# Connector (Scrap Mechanic's orange line): from SCRAP's C to both C's of PACIFIC,
# each dot sitting in a C's mouth
def mouth(box, inward):
	x0, y0, x1, y1 = box
	return (x1 - (x1 - x0) * inward, (y0 + y1) / 2)
c_scrap = mouth(s_boxes[1], 0.36)
c_first = mouth(p_boxes[2], 0.30)
c_last = mouth(p_boxes[6], 0.30)
dot_big, dot_small = 22, 20
lw = 11

svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">']
svg.append(f'<g fill="none" stroke="{BLACK}" stroke-width="{line}" stroke-linecap="butt">')
svg.append(f'<path d="{frame_path(0, 46)}"/>')
svg.append(f'<path d="{frame_path(gap_in, 46 - gap_in)}"/>')
svg.append('</g>')
svg.append(f'<g fill="{BLACK}">' + "".join(f'<path d="{d}"/>' for d in p_paths + s_paths) + '</g>')
# (a thin cut-out around the line where it crosses letters, so it reads cleanly)
for colour, width, extra in (("#FFFFFF", lw + 10, 5), (ORANGE, lw, 0)):
	svg.append(f'<g stroke="{colour}" stroke-width="{width}" stroke-linecap="round" fill="none">')
	svg.append(f'<path d="M{c_first[0]:.1f},{c_first[1]:.1f} L{c_scrap[0]:.1f},{c_scrap[1]:.1f} L{c_last[0]:.1f},{c_last[1]:.1f}" stroke-linejoin="round"/>')
	svg.append('</g>')
	for (cx, cy), r in ((c_scrap, dot_big), (c_first, dot_small), (c_last, dot_small)):
		svg.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r + extra}" fill="{colour}"/>')
svg.append('</svg>')
open(OUT, "w", encoding="utf-8").write("\n".join(svg))
print("ok", OUT, "PACIFIC", round(p_w), "SCRAP", round(s_w))
