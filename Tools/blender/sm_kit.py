# Kitbashing helpers: reuse pieces of vanilla models and put vanilla texture trims on new
# geometry, so new parts use the game's own textures (nothing is copied into the mod).
#
#   import sm_import, sm_kit
#   gas = sm_kit.texture_material("gas", "$SURVIVAL_DATA/Objects/Renderable/Containers/obj_containers_gas.rend", "containergas")
#   sm_kit.trim(obj, gas, (40, 30, 300, 200), faces=sm_kit.faces_facing(obj, (0, -1, 0)))
import bpy, bmesh, math
from mathutils import Vector, Matrix
import sm_import


# ---------------------------------------------------------------- materials

def texture_material(name, rend_path, submesh, paint=sm_import.PREVIEW_PAINT):
	"""A material that uses one submesh's textures from a vanilla .rend (diffuse/asg/nor),
	with the game's paint behaviour. sm_export writes these texture paths into our .rend."""
	info = sm_import.rend_materials(rend_path).get(submesh)
	if not info:
		raise KeyError("%s has no submesh '%s' (has: %s)" % (rend_path, submesh, ", ".join(sm_import.rend_materials(rend_path))))
	m = sm_import.game_material(name, info, paint)
	m["sm_submesh"] = name
	return m


def custom_material(name, diffuse, asg, normal=None, material=None, custom=None, paint=sm_import.PREVIEW_PAINT):
	"""A material from vanilla texture files that aren't one model's submesh (blocks, trim
	sheets, screens). Without a normal map it uses the game's DifAsg material."""
	info = {"diffuse": diffuse, "asg": asg, "material": material or ("DifAsgNor" if normal else "DifAsg"), "custom": custom or {}}
	if normal:
		info["normalMap"] = normal
	m = sm_import.game_material(name, info, paint)
	m["sm_submesh"] = name
	return m


def texture_size(m):
	img = next((n.image for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image), None)
	return tuple(img.size) if img else (1024, 1024)


# ---------------------------------------------------------------- face selection

def faces_facing(obj, direction, min_dot=0.7):
	"""Indices of faces whose normal points roughly along direction (object space)."""
	d = Vector(direction).normalized()
	return [p.index for p in obj.data.polygons if p.normal.dot(d) >= min_dot]


def faces_by_material(obj, mat_name):
	idx = [i for i, s in enumerate(obj.material_slots) if s.material and s.material.name == mat_name]
	return [p.index for p in obj.data.polygons if p.material_index in idx]


def all_faces(obj):
	return [p.index for p in obj.data.polygons]


# ---------------------------------------------------------------- trims

def _slot(obj, mat):
	for i, s in enumerate(obj.material_slots):
		if s.material == mat:
			return i
	obj.data.materials.append(mat)
	return len(obj.data.materials) - 1


def texel_density(obj):
	"""Texture pixels per metre on a (vanilla) model: how big the game draws its textures."""
	me = obj.data
	uvl = me.uv_layers.active
	if not uvl:
		return None
	tot_w = tot_t = 0.0
	for p in me.polygons:
		m = obj.material_slots[p.material_index].material if obj.material_slots else None
		W, H = texture_size(m) if m and m.node_tree else (1024, 1024)
		uv = [uvl.data[li].uv for li in p.loop_indices]
		a = 0.0
		for i in range(1, len(uv) - 1):
			a += abs((uv[i].x - uv[0].x) * (uv[i+1].y - uv[0].y) - (uv[i+1].x - uv[0].x) * (uv[i].y - uv[0].y)) / 2
		tot_t += a * W * H
		tot_w += p.area * (obj.matrix_world.to_scale()[0] ** 2)
	return math.sqrt(tot_t / tot_w) if tot_w else None


# Survival props draw their textures at about this many pixels per metre (measured with
# texel_density: gas 474, battery 513, water 532, chemical 363, refinery 388, beacon 261);
# trims never go bigger than this, so they match the containers they sit next to
DENSITY = 480.0


def trim(obj, mat, rect, faces=None, mode="contain", density=DENSITY, rotate=0, flip_u=False, flip_v=False):
	"""Maps faces of obj onto a rectangle of mat's texture and assigns mat to them.
	rect = (x0, y0, x1, y1) in texture pixels, top-left origin (as seen in an image viewer).
	Faces are projected along their dominant axis (box projection).
	mode "contain" (default, never stretches): same scale on both axes, at most `density`
	pixels per metre, shrunk only as much as needed to stay inside rect, centred in it.
	mode "fit": stretches each projection group to fill rect (only for areas that are
	already the right shape, e.g. a screen frame onto a screen).
	mode "tile": real size at `density`, from the rect's corner.
	rotate: 0/90/180/270 degrees for the texture on these faces."""
	faces = all_faces(obj) if faces is None else faces
	if not faces:
		return
	W, H = texture_size(mat)
	slot = _slot(obj, mat)
	me = obj.data
	bm = bmesh.new(); bm.from_mesh(me)
	bm.faces.ensure_lookup_table()
	uv = bm.loops.layers.uv.verify()
	groups = {}
	for fi in faces:
		f = bm.faces[fi]
		n = f.normal
		ax = max(range(3), key=lambda i: abs(n[i]))
		sign = 1 if n[ax] >= 0 else -1
		groups.setdefault((ax, sign), []).append(f)
	x0, y0, x1, y1 = rect
	u0, u1 = x0 / W, x1 / W
	v0, v1 = 1 - y1 / H, 1 - y0 / H          # Blender UVs are bottom-up
	for (ax, sign), fs in groups.items():
		# 2D axes on the projection plane, picked so textures read upright on side faces
		if ax == 2:
			a, b = (0, 1)
			sa = sign
		else:
			a, b = ((1 if ax == 0 else 0), 2)
			sa = -sign if ax == 0 else sign
		pts = {}
		for f in fs:
			for l in f.loops:
				co = l.vert.co
				s, t = co[a] * sa, co[b]
				r = math.radians(rotate)
				s, t = s * math.cos(r) - t * math.sin(r), s * math.sin(r) + t * math.cos(r)
				pts[l] = (s, t)
		ss = [p[0] for p in pts.values()]; ts = [p[1] for p in pts.values()]
		smin, smax, tmin, tmax = min(ss), max(ss), min(ts), max(ts)
		# contain: one scale (pixels per metre) for both axes
		sw, sh = max(smax - smin, 1e-6), max(tmax - tmin, 1e-6)
		rw, rh = (x1 - x0), (y1 - y0)
		ppm = min(density or DENSITY, rw / sw, rh / sh)
		cu = (x0 + x1) / 2 / W; cv = 1 - (y0 + y1) / 2 / H
		for l, (s, t) in pts.items():
			if mode == "contain":
				uu = cu + (s - (smin + smax) / 2) * ppm / W
				vv = cv + (t - (tmin + tmax) / 2) * ppm / H
			elif mode == "fit":
				fu = (s - smin) / max(smax - smin, 1e-6)
				fv = (t - tmin) / max(tmax - tmin, 1e-6)
				uu, vv = u0 + fu * (u1 - u0), v0 + fv * (v1 - v0)
			else:
				dens = density or 512.0
				uu = u0 + (s - smin) * dens / W
				vv = v0 + (t - tmin) * dens / H
			if flip_u: uu = u0 + u1 - uu
			if flip_v: vv = v0 + v1 - vv
			l[uv].uv = (uu, vv)
		for f in fs:
			f.material_index = slot
	bm.to_mesh(me); bm.free()
	me.update()


def trim_auto(obj, mat, rect, faces=None, density=DENSITY):
	"""trim() in "contain" mode, one call per face direction, turning the texture 90 degrees
	where that lets a tall face use a wide area (or the other way round) at a higher density.
	Never stretches."""
	faces = all_faces(obj) if faces is None else faces
	me = obj.data
	groups = {}
	for fi in faces:
		n = me.polygons[fi].normal
		ax = max(range(3), key=lambda i: abs(n[i]))
		groups.setdefault((ax, n[ax] >= 0), []).append(fi)
	rw, rh = rect[2] - rect[0], rect[3] - rect[1]
	for (ax, _), fs in groups.items():
		a, b = ((0, 1) if ax == 2 else ((1 if ax == 0 else 0), 2))
		vs = [me.vertices[v].co for fi in fs for v in me.polygons[fi].vertices]
		sw = max(v[a] for v in vs) - min(v[a] for v in vs)
		sh = max(v[b] for v in vs) - min(v[b] for v in vs)
		turn = (sh > sw) != (rh > rw)
		trim(obj, mat, rect, faces=fs, mode="contain", density=density, rotate=90 if turn else 0)


def trim_cylinder(obj, mat, side_rect, cap_rect=None, faces=None):
	"""Wraps a cylinder's side around a strip of the texture and fits its caps to cap_rect.
	The cylinder's axis must be the object's local Z."""
	faces = all_faces(obj) if faces is None else faces
	W, H = texture_size(mat)
	slot = _slot(obj, mat)
	me = obj.data
	bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
	uv = bm.loops.layers.uv.verify()
	zs = [v.co.z for v in bm.verts]; zmin, zmax = min(zs), max(zs)
	rs = [math.hypot(v.co.x, v.co.y) for v in bm.verts]; rmax = max(rs) or 1
	for fi in faces:
		f = bm.faces[fi]
		if abs(f.normal.z) > 0.7 and cap_rect:
			x0, y0, x1, y1 = cap_rect
			for l in f.loops:
				fu = 0.5 + l.vert.co.x / (2 * rmax); fv = 0.5 + l.vert.co.y / (2 * rmax)
				l[uv].uv = ((x0 + fu * (x1 - x0)) / W, 1 - (y1 - fv * (y1 - y0)) / H)
		else:
			x0, y0, x1, y1 = side_rect
			angs = [math.atan2(l.vert.co.y, l.vert.co.x) for l in f.loops]
			# keep the seam from wrapping backwards across one face
			if max(angs) - min(angs) > math.pi:
				angs = [a + 2 * math.pi if a < 0 else a for a in angs]
			for l, a in zip(f.loops, angs):
				fu = (a + math.pi) / (2 * math.pi)
				fv = (l.vert.co.z - zmin) / max(zmax - zmin, 1e-6)
				l[uv].uv = ((x0 + fu * (x1 - x0)) / W, 1 - (y1 - fv * (y1 - y0)) / H)
		f.material_index = slot
	bm.to_mesh(me); bm.free(); me.update()


# ---------------------------------------------------------------- pieces

def pieces(src, prefix=None, collection=None, min_faces=1):
	"""Splits a vanilla model into its loose pieces (each connected group of faces becomes
	its own object, origin at its centre, UVs and materials untouched). Returns the objects
	sorted by size, biggest first; each has a "src" property naming the model it came from."""
	prefix = prefix or src.name
	col = collection or bpy.context.scene.collection
	bm = bmesh.new(); bm.from_mesh(src.data)
	bm.faces.ensure_lookup_table()
	seen = set(); groups = []
	for f in bm.faces:
		if f.index in seen:
			continue
		stack = [f]; group = []; seen.add(f.index)
		while stack:
			g = stack.pop(); group.append(g.index)
			for e in g.edges:
				for h in e.link_faces:
					if h.index not in seen:
						seen.add(h.index); stack.append(h)
		if len(group) >= min_faces:
			groups.append(group)
	bm.free()
	out = []
	for i, group in enumerate(groups):
		me = src.data.copy()
		b2 = bmesh.new(); b2.from_mesh(me); b2.faces.ensure_lookup_table()
		keep = set(group)
		bmesh.ops.delete(b2, geom=[f for f in b2.faces if f.index not in keep], context="FACES")
		bmesh.ops.delete(b2, geom=[v for v in b2.verts if not v.link_faces], context="VERTS")
		b2.to_mesh(me); b2.free()
		o = bpy.data.objects.new("%s_p%02d" % (prefix, i), me)
		col.objects.link(o)
		# origin at the piece's centre, placed where it was in the source model
		vs = [v.co for v in me.vertices]
		c = Vector((sum(v.x for v in vs), sum(v.y for v in vs), sum(v.z for v in vs))) / max(len(vs), 1)
		me.transform(Matrix.Translation(-c))
		o.matrix_world = src.matrix_world @ Matrix.Translation(c)
		o["src"] = src.name
		out.append(o)
	bpy.context.view_layer.update()
	out.sort(key=lambda o: -max(o.dimensions))
	return out


def extract(src, name, material=None, vertex_group=None, min_weight=0.5, collection=None):
	"""Copies part of a vanilla model into a new object: the faces using `material`
	(a submesh), or the faces whose vertices all belong to `vertex_group` (a joint)."""
	me = src.data.copy()
	obj = bpy.data.objects.new(name, me)
	(collection or bpy.context.scene.collection).objects.link(obj)
	obj.matrix_world = src.matrix_world.copy()
	bm = bmesh.new(); bm.from_mesh(me)
	keep = set()
	if material is not None:
		idx = {i for i, m in enumerate(me.materials) if m and (m.name == material or m.get("sm_submesh") == material)}
		keep = {f.index for f in bm.faces if f.material_index in idx}
	elif vertex_group is not None:
		gi = src.vertex_groups[vertex_group].index
		dl = bm.verts.layers.deform.verify()
		inside = {v.index for v in bm.verts if v[dl].get(gi, 0.0) >= min_weight}
		keep = {f.index for f in bm.faces if all(v.index in inside for v in f.verts)}
	bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
	bm.to_mesh(me); bm.free()
	return obj
