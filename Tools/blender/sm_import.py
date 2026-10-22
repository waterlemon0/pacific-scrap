# Loads vanilla Scrap Mechanic models into Blender as references or kitbash pieces.
# Reads only from the game folder; never changes anything there.
#
#   import sys; sys.path.append(r"<mod>/Tools/blender")
#   import sm_import
#   obj = sm_import.load("$SURVIVAL_DATA/Objects/Mesh/containers/obj_containers_gas.fbx",
#                        rend_path="$SURVIVAL_DATA/Objects/Renderable/Containers/obj_containers_gas.rend")
#
# The game is Y-up and measures in blocks (1 unit = 0.25 m); Blender is Z-up in metres.
# Every imported model is converted the same way, and sm_export applies the exact inverse.
import bpy, os, re, json
import xml.etree.ElementTree as ET
from mathutils import Matrix

GAME = r"D:\steam\steamapps\common\Scrap Mechanic"
MOD = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ROOTS = {
	"$GAME_DATA": os.path.join(GAME, "Data"),
	"$SURVIVAL_DATA": os.path.join(GAME, "Survival"),
	"$CHALLENGE_DATA": os.path.join(GAME, "ChallengeData"),
	"$CONTENT_DATA": MOD,
}
# Game (x, y-up, z) in blocks -> Blender (x, -z, y) in metres
TO_BLENDER = Matrix(((0.25, 0, 0, 0), (0, 0, -0.25, 0), (0, 0.25, 0, 0), (0, 0, 0, 1)))
# Paint colour used to preview paintable areas (Craftbot yellow, like the game's default)
PREVIEW_PAINT = (0.95, 0.62, 0.05, 1.0)


def resolve(path):
	"""Turns $GAME_DATA/..., $SURVIVAL_DATA/... (as written in .rend files) into a real path."""
	for key, root in ROOTS.items():
		if path.startswith(key):
			return os.path.normpath(os.path.join(root, path[len(key):].lstrip("/\\")))
	return os.path.normpath(path)


def read_json(path):
	"""Game JSON files allow trailing commas; strip them before parsing."""
	with open(resolve(path), "r", encoding="utf-8") as f:
		text = f.read()
	return json.loads(re.sub(r",(\s*[\]}])", r"\1", text))


# ---------------------------------------------------------------- materials

def rend_materials(rend_path, lod=0):
	"""subMeshMap of a .rend: {submesh name: {"diffuse","asg","normalMap","material","custom"}}"""
	data = read_json(rend_path)
	lods = data.get("lodList") or []
	if not lods:
		return {}
	out = {}
	for name, sub in (lods[min(lod, len(lods)-1)].get("subMeshMap") or {}).items():
		tex = {}
		if "textures" in sub:
			tex = dict(sub["textures"])
		elif "textureList" in sub:
			keys = ("diffuse", "asg", "normalMap", "ao")
			tex = {keys[i]: p for i, p in enumerate(sub["textureList"][:4])}
		out[name] = dict(tex, material=sub.get("material", "DifAsgNor"), custom=sub.get("custom", {}))
	return out


def game_material(name, info, paint=PREVIEW_PAINT):
	"""Preview material that looks like the game: the original diffuse texture, with the
	part's paint colour showing where the texture's alpha is 0. Keeps the .rend info on the
	material so sm_export can write it back out."""
	m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	m.use_nodes = True
	nt = m.node_tree
	for n in [n for n in nt.nodes if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL")]:
		nt.nodes.remove(n)
	bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
	dif = info.get("diffuse")
	if dif and os.path.exists(resolve(dif)):
		tex = nt.nodes.new("ShaderNodeTexImage")
		tex.image = bpy.data.images.load(resolve(dif), check_existing=True)
		tex.image.alpha_mode = "CHANNEL_PACKED"
		mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
		mix.inputs[6].default_value = paint                       # A: paint colour (alpha 0)
		nt.links.new(tex.outputs["Alpha"], mix.inputs["Factor"])
		nt.links.new(tex.outputs["Color"], mix.inputs[7])          # B: texture colour (alpha 1)
		nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
		m["sm_paint_node"] = mix.name
	bsdf.inputs["Roughness"].default_value = 0.55
	for k in ("diffuse", "asg", "normalMap", "ao"):
		if info.get(k):
			m["sm_" + k] = info[k]
	m["sm_material"] = info.get("material", "DifAsgNor")
	m["sm_custom"] = json.dumps(info.get("custom", {}))
	return m


def set_preview_paint(color):
	"""Changes the preview paint colour on every game material (e.g. a part's shapeset colour)."""
	for m in bpy.data.materials:
		node = m.get("sm_paint_node")
		if node and m.node_tree and node in m.node_tree.nodes:
			m.node_tree.nodes[node].inputs[6].default_value = color


def hex_color(h):
	c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
	return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c) + (1.0,)


# ---------------------------------------------------------------- .dae (Collada)

def _ns(tag):
	return "{http://www.collada.org/2005/11/COLLADASchema}" + tag


def _floats(el):
	return [float(x) for x in el.text.split()] if el is not None and el.text else []


def _ints(el):
	return [int(x) for x in el.text.split()] if el is not None and el.text else []


def _source(mesh, sid):
	src = mesh.find(".//" + _ns("source") + "[@id='%s']" % sid.lstrip("#"))
	acc = src.find(".//" + _ns("accessor"))
	stride = int(acc.get("stride", "1"))
	vals = _floats(src.find(_ns("float_array")))
	return [vals[i:i+stride] for i in range(0, len(vals), stride)]


def _load_dae(path, name):
	root = ET.parse(resolve(path)).getroot()
	geom = root.find(".//" + _ns("geometry"))
	mesh = geom.find(_ns("mesh"))
	vin = mesh.find(_ns("vertices"))
	pos_id = vin.find(_ns("input") + "[@semantic='POSITION']").get("source")
	positions = _source(mesh, pos_id)

	faces, face_mats, corner_uvs, mat_names = [], [], [], []
	for prim in list(mesh.findall(_ns("triangles"))) + list(mesh.findall(_ns("polylist"))):
		mat = prim.get("material") or "default"
		if mat not in mat_names:
			mat_names.append(mat)
		inputs = prim.findall(_ns("input"))
		stride = max(int(i.get("offset", "0")) for i in inputs) + 1
		v_off = next(int(i.get("offset")) for i in inputs if i.get("semantic") == "VERTEX")
		uv_in = next((i for i in inputs if i.get("semantic") == "TEXCOORD" and i.get("set", "0") == "0"), None) \
			or next((i for i in inputs if i.get("semantic") == "TEXCOORD"), None)
		uvs = _source(mesh, uv_in.get("source")) if uv_in is not None else None
		uv_off = int(uv_in.get("offset")) if uv_in is not None else None
		p = _ints(prim.find(_ns("p")))
		counts = _ints(prim.find(_ns("vcount"))) if prim.tag == _ns("polylist") else [3] * (len(p) // (3 * stride))
		k = 0
		for n in counts:
			corners = [p[(k + c) * stride:(k + c + 1) * stride] for c in range(n)]
			k += n
			faces.append([c[v_off] for c in corners])
			face_mats.append(mat_names.index(mat))
			corner_uvs.append([uvs[c[uv_off]][:2] if uvs else (0.0, 0.0) for c in corners])

	# Placement of the geometry in the scene (and the skin's bind shape), if any
	place = Matrix.Identity(4)
	skin = root.find(".//" + _ns("skin"))
	if skin is not None and skin.find(_ns("bind_shape_matrix")) is not None:
		vals = _floats(skin.find(_ns("bind_shape_matrix")))
		place = Matrix([vals[0:4], vals[4:8], vals[8:12], vals[12:16]])

	me = bpy.data.meshes.new(name)
	conv = TO_BLENDER @ place
	me.from_pydata([tuple(conv @ __import__("mathutils").Vector(v[:3])) for v in positions], [], faces)
	uvl = me.uv_layers.new(name="UVMap")
	li = 0
	for poly, cuv in zip(me.polygons, corner_uvs):
		for c, loop in enumerate(poly.loop_indices):
			uvl.data[loop].uv = cuv[c]
	me.update()
	for poly, mi in zip(me.polygons, face_mats):
		poly.material_index = mi
	obj = bpy.data.objects.new(name, me)

	# Skin weights -> one vertex group per joint (lets sm_kit cut a model apart by joint)
	if skin is not None:
		joints_src = skin.find(_ns("joints")).find(_ns("input") + "[@semantic='JOINT']").get("source")
		jsrc = skin.find(".//" + _ns("source") + "[@id='%s']" % joints_src.lstrip("#"))
		joint_names = (jsrc.find(_ns("Name_array")) if jsrc.find(_ns("Name_array")) is not None else jsrc.find(_ns("IDREF_array"))).text.split()
		vw = skin.find(_ns("vertex_weights"))
		w_src = vw.find(_ns("input") + "[@semantic='WEIGHT']").get("source")
		weights = [w[0] for w in _source(skin, w_src)]
		vcount, v = _ints(vw.find(_ns("vcount"))), _ints(vw.find(_ns("v")))
		groups = [obj.vertex_groups.new(name=j) for j in joint_names]
		k = 0
		for vi, n in enumerate(vcount):
			for _ in range(n):
				j, w = v[k], v[k+1]; k += 2
				groups[j].add([vi], weights[w], "REPLACE")
	return obj, mat_names


# ---------------------------------------------------------------- .fbx

def _load_fbx(path, name):
	before = set(bpy.data.objects)
	bpy.ops.import_scene.fbx(filepath=resolve(path))
	new = [o for o in bpy.data.objects if o not in before]
	meshes = [o for o in new if o.type == "MESH"]
	bpy.context.view_layer.update()
	# Bake each object's import transform in, then join, so the result has the same
	# convention as .dae imports: raw game units * 0.25, Z up, identity transform.
	# Blender's FBX importer already turns Y-up into Z-up; it reads the game's units as
	# centimetres, so rescale whatever it applied to exactly 0.25 m per unit.
	for o in meshes:
		mw = o.matrix_world.copy()
		unit = mw.to_scale()[0] or 1.0
		o.data = o.data.copy()
		o.data.transform(mw)
		o.data.transform(Matrix.Scale(0.25 / unit, 4))
		o.parent = None
		o.matrix_world = Matrix.Identity(4)
	for o in new:
		if o not in meshes:
			bpy.data.objects.remove(o, do_unlink=True)
	if len(meshes) > 1:
		bpy.ops.object.select_all(action="DESELECT")
		for o in meshes:
			o.select_set(True)
		bpy.context.view_layer.objects.active = meshes[0]
		bpy.ops.object.join()
	obj = meshes[0]
	obj.name = name
	# FBX material names can carry a namespace ("barrack_support:blinn2"); keep the full name
	mat_names = [m.name if m else "default" for m in obj.data.materials]
	for c in obj.users_collection:
		c.objects.unlink(obj)
	return obj, mat_names


# ---------------------------------------------------------------- finding models

_REND_INDEX = None


def rend_index():
	"""{mesh file name (lower case): (mesh path, rend path)} for every vanilla .rend's first LOD."""
	global _REND_INDEX
	if _REND_INDEX is not None:
		return _REND_INDEX
	_REND_INDEX = {}
	for key in ("$SURVIVAL_DATA", "$GAME_DATA"):
		base = ROOTS[key]
		for folder, _, files in os.walk(base):
			for fn in files:
				if not fn.endswith(".rend"):
					continue
				full = os.path.join(folder, fn)
				try:
					lods = read_json(full).get("lodList") or []
				except Exception:
					continue
				if not lods or "mesh" not in lods[0]:
					continue
				mesh = lods[0]["mesh"]
				rend = key + "/" + os.path.relpath(full, base).replace("\\", "/")
				_REND_INDEX.setdefault(os.path.basename(mesh).lower(), (mesh, rend))
	return _REND_INDEX


def find(name_part):
	"""All indexed models whose mesh file name contains name_part: [(mesh, rend)]."""
	return [v for k, v in sorted(rend_index().items()) if name_part.lower() in k]


# ---------------------------------------------------------------- entry point

def load(mesh_path, rend_path=None, name=None, collection=None, paint=PREVIEW_PAINT):
	"""Imports a vanilla .dae or .fbx model. With rend_path, every submesh gets a preview
	material with the game's own textures and paint behaviour. Returns the object."""
	name = name or os.path.splitext(os.path.basename(mesh_path))[0]
	if mesh_path.lower().endswith(".dae"):
		obj, subs = _load_dae(mesh_path, name)
	else:
		obj, subs = _load_fbx(mesh_path, name)
	col = collection or bpy.context.scene.collection
	col.objects.link(obj)
	mats = rend_materials(rend_path) if rend_path else {}
	face_slots = [p.material_index for p in obj.data.polygons]   # clearing the materials resets these
	obj.data.materials.clear()
	# Material names include the .rend's name: many models have a submesh called "screen" or
	# "glass" with different textures, and sharing one material would mix them up
	model = os.path.splitext(os.path.basename(rend_path))[0] if rend_path else name
	for sub in subs:
		key = sub if sub in mats else sub.split(".")[0]
		info = mats.get(key) or mats.get(key.split(":")[-1]) or {}
		m = game_material("sm_%s_%s" % (model, key), info, paint) if info else (bpy.data.materials.get(sub) or bpy.data.materials.new(sub))
		m["sm_submesh"] = key
		obj.data.materials.append(m)
	for p, i in zip(obj.data.polygons, face_slots):
		p.material_index = i
		p.use_smooth = True
	return obj
