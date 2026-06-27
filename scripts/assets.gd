class_name Assets extends Node
## Streams .glb assets from R2 (parallel HTTPRequest -> GLTFDocument), caches the parsed
## scene by URL (re-use is free), and supplies the geometry/material/collider helpers the
## world streamer needs. The .pck holds scripts+shaders only; meshes stream at runtime.

var origin := "https://preview.myapping.com"   # CDN base for /godot-assets/...
var build_dir := "https://preview.myapping.com/"   # dir holding index.html (loose Meshy models live here)
var cache := {}                                  # url -> parsed scene Node (persists)
var _pending := 0

# Resolve a world.json asset ref to an absolute URL.
#  http...            -> as-is
#  /path              -> origin + path  (leading-slash R2 path)
#  props/.. chars/..  -> origin + /godot-assets/ + path  (library)
#  models/foo.glb     -> build_dir + path  (Meshy assets, loose next to index.html)
func resolve(u: String) -> String:
	if u.begins_with("http"):
		return u
	if u.begins_with("/"):
		return origin + u
	if u.begins_with("props/") or u.begins_with("characters/") or u.begins_with("realistic_characters/") \
			or u.begins_with("enemies/") or u.begins_with("animals/") or u.begins_with("skies/") \
			or u.begins_with("audio/") or u.begins_with("godot-assets/"):
		return origin + "/godot-assets/" + u
	return build_dir + u

# Download every missing url in PARALLEL, then await until all are cached (or time out).
func ensure(urls: Array) -> void:
	_pending = 0
	for u in urls:
		var full := resolve(String(u))
		if cache.has(full):
			continue
		_pending += 1
		var req := HTTPRequest.new()
		add_child(req)
		req.request_completed.connect(_on_dl.bind(full, req))
		var err := req.request(full)
		if err != OK:
			req.queue_free()
			_pending -= 1
	var guard := 0
	while _pending > 0 and guard < 1800:
		await get_tree().process_frame
		guard += 1

func _on_dl(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, url: String, req: HTTPRequest) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 0:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_buffer(body, "", st) == OK:
			cache[url] = doc.generate_scene(st)
	req.queue_free()
	_pending -= 1

# A fresh instance of a cached asset (already ensured). Returns null if not loaded.
func get_instance(ref: String) -> Node3D:
	var full := resolve(ref)
	if not cache.has(full) or cache[full] == null:
		return null
	var n := (cache[full] as Node).duplicate() as Node3D
	return n

# ---- geometry helpers ----

func col(a) -> Color:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 3:
		return Color(a[0], a[1], a[2])
	return Color(0.5, 0.5, 0.5)

func mat(c: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

# A visible + solid box (StaticBody3D on layer 1). cast_shadow=false for big flat floors.
func make_box(parent: Node, pos: Vector3, sz: Vector3, c: Color, cast_shadow := true, material: Material = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = material if material != null else mat(c)
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)
	return body

# A purely visual box (no collider) — interior floors, signage, decals.
func visual_box(parent: Node, pos: Vector3, sz: Vector3, material: Material, cast_shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# A collision-only box (no mesh) — edge aprons, invisible blockers.
func collider_box(parent: Node, pos: Vector3, sz: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)

# Union AABB of every MeshInstance3D under root, in world space.
func world_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var wa: AABB = mi.global_transform * mi.get_aabb()
			if first:
				merged = wa
				first = false
			else:
				merged = merged.merge(wa)
	return merged

# Ground a placed model: seat its lowest point on y=0 (handles base-at-origin AND
# pivot-at-top/centre models, which several library packs use).
func ground(node: Node3D) -> void:
	var ab := world_aabb(node)
	node.position.y -= ab.position.y

# Derived solid box collider from a placed+scaled prop's mesh bounds.
func add_prop_collision(prop: Node3D, parent: Node, max_xz := 3.5) -> void:
	var aabb := world_aabb(prop)
	if aabb.size.x < 0.15 and aabb.size.z < 0.15:
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		clampf(aabb.size.x, 0.2, max_xz),
		maxf(aabb.size.y, 0.4),
		clampf(aabb.size.z, 0.2, max_xz))
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)
	body.global_position = aabb.position + aabb.size * 0.5

# Trimesh collider over every mesh in a model -> walk INTO arches / interiors.
func add_mesh_collision(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var nn = stack.pop_back()
		for c in nn.get_children():
			stack.append(c)
		if nn is MeshInstance3D and (nn as MeshInstance3D).mesh != null:
			(nn as MeshInstance3D).create_trimesh_collision()
