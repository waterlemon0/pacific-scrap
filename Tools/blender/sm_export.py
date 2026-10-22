# Writes a finished model for the game: the mesh (in game units, Y up) and a .rend next
# to it. Each material slot becomes one submesh; materials made with sm_import/sm_kit keep
# the vanilla texture paths they came from, so the .rend points at the game's own files.
#
#   import sm_export
#   sm_export.export(obj, "obj_pacificscrap_fuelpump", center=(0, 0), floor=0.0, half_height=4)
import bpy, os, json, math
from mathutils import Matrix, Vector
import sm_import

MOD = sm_import.MOD


def _submesh_entry(m):
	tex = {}
	for key in ("diffuse", "asg", "normalMap", "ao"):
		if m.get("sm_" + key):
			tex[key] = m["sm_" + key]
	if not tex:
		raise ValueError("material %s has no game textures (make it with sm_kit.texture_material)" % m.name)
	# "Pose..." materials need the pose meshes of the model they came from (e.g. the beacon's
	# moving dish); our models have none and the game crashes on load, so use the plain version
	mat = m.get("sm_material", "DifAsgNor")
	# PoseAnimDifAsgNor_Metal -> DifAsgNor_Metal, PoseUVAnimDifAsg -> UVAnimDifAsg
	if mat.startswith("PoseAnim"):
		mat = mat[len("PoseAnim"):]
	elif mat.startswith("Pose"):
		mat = mat[len("Pose"):]
	entry = {"material": mat}
	custom = json.loads(m.get("sm_custom", "{}") or "{}")
	if custom:
		entry["custom"] = custom
	entry["textures"] = tex
	return entry


def export(obj, name, center=(0.0, 0.0), floor=0.0, half_height=1.5, rot_z=0.0):
	"""center: the part's centre on the ground plane (metres); floor: height of the bottom of
	the shapeset box; half_height: half the box's height in blocks (box y / 2).
	rot_z turns the model before export (radians), to face it the way the part should."""
	dg = bpy.context.evaluated_depsgraph_get()
	src = obj.evaluated_get(dg)
	me = bpy.data.meshes.new_from_object(src, depsgraph=dg)
	me.transform(obj.matrix_world)
	me.transform(Matrix.Translation(Vector((-center[0], -center[1], -floor - half_height * 0.25))))
	if rot_z:
		me.transform(Matrix.Rotation(rot_z, 4, "Z"))
	# The file's material names are the .rend's submesh names: give each slot a plain
	# material named after its submesh (prefixed with the part name so it can't clash)
	mats = list(obj.data.materials)
	tmp_mats = []
	face_slots = [p.material_index for p in me.polygons]   # clearing the materials resets these
	me.materials.clear()
	# Submesh names: part name, slot number, source submesh (e.g. arcdevice_m00_containerbattery)
	used = set()
	prefix = name.replace("obj_pacificscrap_", "")
	for i, m in enumerate(mats):
		sub = (m.get("sm_submesh") or m.name).split(".")[0].replace(":", "_")
		if sub.startswith(prefix + "_"):
			sub = sub[len(prefix) + 1:]
		while sub[:1] == "m" and sub[1:3].isdigit() and sub[3:4] == "_":
			sub = sub[4:]
		while sub.startswith(prefix + "_"):
			sub = sub[len(prefix) + 1:]
		sub = "%s_m%02d_%s" % (prefix, i, sub)
		# two vanilla models can both have e.g. a "connectionpoint" submesh: number the repeats
		base, k = sub, 2
		while sub in used:
			sub = "%s%d" % (base, k); k += 1
		used.add(sub)
		old = bpy.data.materials.get(sub)
		if old:
			bpy.data.materials.remove(old)
		t = bpy.data.materials.new(sub)
		# IMPORTANT: every material gets its own colour. The game merges materials that are
		# identical (Blender's blank ones all were), and then every submesh got the first
		# material's name and texture (confirmed in game on the ARC Device and Fuel Pump)
		col = ((i * 37 % 255) / 255.0, (i * 91 % 255) / 255.0, (i * 151 % 255) / 255.0, 1.0)
		t.diffuse_color = col
		if t.node_tree:
			bsdf = next((n for n in t.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
			if bsdf:
				bsdf.inputs["Base Color"].default_value = col
		tmp_mats.append(t); me.materials.append(t)
	for p, i in zip(me.polygons, face_slots):
		p.material_index = i
	me.transform(Matrix.Scale(4.0, 4))        # metres -> blocks
	# One mesh object per submesh, each with a single material (a layout vanilla files use too)
	import bmesh
	parts = []
	for i, t in enumerate(tmp_mats):
		part = me.copy()
		bm = bmesh.new(); bm.from_mesh(part)
		bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != i], context="FACES")
		bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
		for f in bm.faces:
			f.material_index = 0
		bm.to_mesh(part); bm.free()
		if not part.polygons:
			bpy.data.meshes.remove(part)
			continue
		part.materials.clear(); part.materials.append(t)
		part.name = t.name                     # the file's mesh name = its submesh name
		o = bpy.data.objects.new(t.name, part)
		bpy.context.scene.collection.objects.link(o)
		parts.append(o)
	vl = bpy.context.view_layer
	for o in vl.objects:
		o.select_set(False)
	for o in parts:
		o.select_set(True)
	vl.objects.active = parts[0]
	fbx = os.path.join(MOD, "Objects", "Mesh", name + ".fbx")
	bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, object_types={"MESH"}, global_scale=0.01,
		apply_unit_scale=True, apply_scale_options="FBX_SCALE_NONE", bake_space_transform=True,
		# triangles only, with tangents, like the vanilla files
		use_triangles=True, use_tspace=True,
		axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE", add_leaf_bones=False,
		path_mode="STRIP", embed_textures=False)
	# Shading model written as "phong" like Maya (vanilla) files, not Blender's "Phong"
	# (same length, so the binary file's layout is unchanged)
	with open(fbx, "rb") as f:
		data = f.read()
	data = data.replace(b"S\x05\x00\x00\x00Phong", b"S\x05\x00\x00\x00phong")
	with open(fbx, "wb") as f:
		f.write(data)
	names = [o.data.materials[0].name for o in parts]
	mats = [mats[tmp_mats.index(o.data.materials[0])] for o in parts]
	for o in parts:
		m = o.data
		bpy.data.objects.remove(o, do_unlink=True)
		bpy.data.meshes.remove(m)
	bpy.data.meshes.remove(me)
	rend = {"lodList": [{"mesh": "$CONTENT_DATA/Objects/Mesh/%s.fbx" % name,
		"subMeshMap": {n: _submesh_entry(m) for n, m in zip(names, mats)}}]}
	path = os.path.join(MOD, "Objects", "Renderable", name + ".rend")
	with open(path, "w", encoding="utf-8") as f:
		json.dump(rend, f, indent="\t")
	for t in tmp_mats:
		bpy.data.materials.remove(t)
	return fbx, path, names
