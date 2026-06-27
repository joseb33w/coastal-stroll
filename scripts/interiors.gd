class_name Interiors extends Node
## Builds the city's solid towers AND the enterable buildings (bodega / diner / apartment
## lobby) with real interiors + furniture. Enterable buildings register a footprint + their
## roof/ceiling nodes so main.gd can hide the roof while the player is inside (so the
## third-person camera sees in) and fire the discovery + door sound on entry.

var assets: Assets

# enterable building registry: list of dicts {center:Vector3, hx,hz, rot, place, name, roof:Array[Node], cellkey}
var buildings: Array = []

const WALL_T := 0.3
const DOOR_HALF := 1.0
const DOOR_H := 2.4

func setup(a: Assets) -> void:
	assets = a

# Ensure the few library props the interiors decorate with, before building.
func preload_furniture() -> void:
	await assets.ensure([
		"props/kk_furniture/couch.glb",
		"props/kk_furniture/shelf_B_large.glb",
		"props/kk_furniture/cactus_medium_A.glb",
		"props/kk_restaurant/food_burger.glb",
		"props/kk_restaurant/chair_stool.glb",
	])

# Build one building record at cell-world `centre`; root is the cell node; cellkey for eviction.
func build(b: Dictionary, centre: Vector3, root: Node, cellkey: String) -> void:
	var p := _xz(b.get("pos", [0, 0]))
	var wpos := centre + Vector3(p.x, 0.0, p.y)
	var rot := deg_to_rad(float(b.get("rot", 0.0)))
	var t := String(b.get("type", "tower"))
	match t:
		"tower":
			_tower(b, wpos, rot, root)
		"bodega":
			_bodega(b, wpos, rot, root, cellkey)
		"diner":
			_diner(b, wpos, rot, root, cellkey)
		"lobby":
			_lobby(b, wpos, rot, root, cellkey)
		"cab":
			_cab(b, wpos, rot, root)

# ---------------- yellow cab (procedural — reliable shape/orientation) ----------------

func _wheel(node: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.36
	cy.bottom_radius = 0.36
	cy.height = 0.26
	mi.mesh = cy
	mi.material_override = assets.mat(Color(0.06, 0.06, 0.07), 0.6)
	mi.rotation.z = PI * 0.5   # lay the wheel on its side (axle along X)
	mi.position = pos
	node.add_child(mi)

func _cab(b: Dictionary, wpos: Vector3, rot: float, root: Node) -> void:
	var node := Node3D.new()
	root.add_child(node)
	node.position = wpos
	node.rotation.y = rot
	var yellow := Color(0.96, 0.78, 0.08)
	var blackmat := assets.mat(Color(0.08, 0.08, 0.10), 0.3, 0.2)
	# chassis + cabin
	assets.visual_box(node, Vector3(0, 0.62, 0), Vector3(1.9, 0.7, 4.4), assets.mat(yellow, 0.4, 0.2))
	assets.visual_box(node, Vector3(0, 1.18, -0.1), Vector3(1.7, 0.66, 2.1), assets.mat(yellow, 0.4, 0.2))
	# window band (dark glass)
	assets.visual_box(node, Vector3(0, 1.2, -0.1), Vector3(1.74, 0.42, 2.14), blackmat)
	# checker stripe
	assets.visual_box(node, Vector3(0.96, 0.62, 0), Vector3(0.03, 0.22, 4.0), assets.mat(Color(0.1, 0.1, 0.1), 0.5))
	assets.visual_box(node, Vector3(-0.96, 0.62, 0), Vector3(0.03, 0.22, 4.0), assets.mat(Color(0.1, 0.1, 0.1), 0.5))
	# roof TAXI light
	assets.visual_box(node, Vector3(0, 1.62, -0.1), Vector3(0.5, 0.26, 0.9), assets.mat(Color(0.1, 0.1, 0.1), 0.5))
	var lbl := Label3D.new()
	lbl.text = "TAXI"
	lbl.font_size = 64
	lbl.pixel_size = 0.004
	lbl.modulate = Color(1.0, 0.85, 0.2)
	lbl.position = Vector3(0, 1.62, -0.1)
	node.add_child(lbl)
	var lbl2 := Label3D.new()
	lbl2.text = "TAXI"
	lbl2.font_size = 64
	lbl2.pixel_size = 0.004
	lbl2.modulate = Color(1.0, 0.85, 0.2)
	lbl2.rotation.y = PI
	lbl2.position = Vector3(0, 1.62, -0.1)
	node.add_child(lbl2)
	# wheels
	_wheel(node, Vector3(0.92, 0.36, 1.4))
	_wheel(node, Vector3(-0.92, 0.36, 1.4))
	_wheel(node, Vector3(0.92, 0.36, -1.4))
	_wheel(node, Vector3(-0.92, 0.36, -1.4))
	# headlights (emissive)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(1.0, 0.95, 0.8)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.95, 0.8)
	hm.emission_energy_multiplier = 2.0
	assets.visual_box(node, Vector3(0.6, 0.62, 2.2), Vector3(0.3, 0.2, 0.06), hm)
	assets.visual_box(node, Vector3(-0.6, 0.62, 2.2), Vector3(0.3, 0.2, 0.06), hm)
	# solid collider
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.5, 4.4)
	cs.shape = box
	cs.position = Vector3(0, 0.75, 0)
	body.add_child(cs)
	node.add_child(body)

# ---------------- towers (solid, procedural facade) ----------------

var _facade_shader: Shader = preload("res://shaders/facade.gdshader")

func _facade_mat(tint: Color, fseed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _facade_shader
	m.set_shader_parameter("wall_color", tint)
	m.set_shader_parameter("seed", fseed)
	return m

func _tower(b: Dictionary, wpos: Vector3, rot: float, root: Node) -> void:
	var w := float(b.get("w", 6.0))
	var d := float(b.get("d", 6.0))
	var h := float(b.get("h", 18.0))
	var node := Node3D.new()
	root.add_child(node)
	node.position = wpos
	node.rotation.y = rot
	var tint := assets.col(b.get("color", [0.46, 0.47, 0.5]))
	var tseed := float(b.get("seed", randf() * 10.0))
	var fac := _facade_mat(tint, tseed)
	# main shaft
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, d)
	mi.mesh = bm
	mi.material_override = fac
	mi.position = Vector3(0, h * 0.5, 0)
	node.add_child(mi)
	# a smaller setback crown for skyline variety
	if b.get("crown", true):
		var ch := h * 0.18
		var cmi := MeshInstance3D.new()
		var cbm := BoxMesh.new()
		cbm.size = Vector3(w * 0.6, ch, d * 0.6)
		cmi.mesh = cbm
		cmi.material_override = fac
		cmi.position = Vector3(0, h + ch * 0.5, 0)
		node.add_child(cmi)
	# solid collider for the shaft
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, d)
	cs.shape = box
	cs.position = Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	node.add_child(body)

# ---------------- enterable buildings ----------------

func _wall(parent: Node, pos: Vector3, sz: Vector3, c: Color) -> StaticBody3D:
	return assets.make_box(parent, pos, sz, c)

# build the 4 walls with a doorway gap on the +Z (front) face; returns nothing.
func _shell(node: Node3D, w: float, d: float, h: float, wall_c: Color) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	# back wall (-Z)
	_wall(node, Vector3(0, h * 0.5, -hd), Vector3(w, h, WALL_T), wall_c)
	# side walls (±X)
	_wall(node, Vector3(-hw, h * 0.5, 0), Vector3(WALL_T, h, d), wall_c)
	_wall(node, Vector3(hw, h * 0.5, 0), Vector3(WALL_T, h, d), wall_c)
	# front wall (+Z) with a doorway gap centered at x=0
	var seg := (w - 2.0 * DOOR_HALF) * 0.5
	if seg > 0.05:
		var cx := DOOR_HALF + seg * 0.5
		_wall(node, Vector3(-cx, h * 0.5, hd), Vector3(seg, h, WALL_T), wall_c)
		_wall(node, Vector3(cx, h * 0.5, hd), Vector3(seg, h, WALL_T), wall_c)
	# lintel above the doorway
	var lint := h - DOOR_H
	if lint > 0.05:
		_wall(node, Vector3(0, DOOR_H + lint * 0.5, hd), Vector3(2.0 * DOOR_HALF, lint, WALL_T), wall_c)

# interior floor (visual, no collider — the cell slab is the physical floor), plus a fade roof.
func _floor_and_roof(node: Node3D, w: float, d: float, h: float, floor_c: Color, roof_c: Color) -> Array:
	assets.visual_box(node, Vector3(0, 0.03, 0), Vector3(w - WALL_T, 0.06, d - WALL_T), assets.mat(floor_c, 0.6), false)
	var roof := assets.visual_box(node, Vector3(0, h, 0), Vector3(w + 0.3, WALL_T, d + 0.3), assets.mat(roof_c, 0.85))
	return [roof]

func _sign(node: Node3D, w: float, h: float, text: String, c: Color) -> void:
	# emissive sign panel + 3D label above the doorway, facing +Z (outward)
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(minf(w * 0.9, 4.5), 0.9, 0.15)
	panel.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = c
	sm.emission_enabled = true
	sm.emission = c
	sm.emission_energy_multiplier = 1.8
	panel.material_override = sm
	panel.position = Vector3(0, h + 0.6, w * 0.0 + 0.0)
	node.add_child(panel)
	panel.position.z = node_front_z(node)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.pixel_size = 0.006
	lbl.modulate = Color(0.05, 0.05, 0.06)
	lbl.outline_size = 0
	lbl.rotation.y = PI
	lbl.position = Vector3(0, h + 0.6, node_front_z(node) + 0.09)
	node.add_child(lbl)

# helper: front face z used for signage (set per building via meta)
func node_front_z(node: Node3D) -> float:
	return float(node.get_meta("front_z", 3.0))

func _register(node: Node3D, w: float, d: float, rot: float, place: String, disp_name: String, roofs: Array, cellkey: String) -> void:
	buildings.append({
		"center": node.position,
		"hx": w * 0.5,
		"hz": d * 0.5,
		"rot": rot,
		"place": place,
		"name": disp_name,
		"roof": roofs,
		"cellkey": cellkey,
	})

# a furniture box with a material (reliable, cohesive)
func _furn(node: Node3D, pos: Vector3, sz: Vector3, c: Color, rough := 0.7, metal := 0.0) -> void:
	assets.make_box(node, pos, sz, c, true, assets.mat(c, rough, metal))

func _prop(node: Node3D, ref: String, pos: Vector3, sc: float, ry := 0.0) -> void:
	var n := assets.get_instance(ref)
	if n == null:
		return
	node.add_child(n)
	n.position = pos
	n.rotation.y = ry
	if sc != 1.0:
		n.scale = Vector3(sc, sc, sc)
	assets.ground(n)

func _ceiling_light(node: Node3D, h: float, c: Color) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 1.6
	l.omni_range = 9.0
	l.shadow_enabled = false
	l.position = Vector3(0, h - 0.4, 0)
	node.add_child(l)

func _bodega(b: Dictionary, wpos: Vector3, rot: float, root: Node, cellkey: String) -> void:
	var w := 7.0
	var d := 6.0
	var h := 3.4
	var node := _new_building(wpos, rot, root, d)
	_shell(node, w, d, h, Color(0.62, 0.30, 0.26))
	var roofs := _floor_and_roof(node, w, d, h, Color(0.74, 0.70, 0.62), Color(0.34, 0.18, 0.16))
	_ceiling_light(node, h, Color(1.0, 0.95, 0.8))
	# shelves along the back & left wall, a counter near the door, a fridge, produce crates
	_furn(node, Vector3(-w * 0.5 + 0.5, 0.9, -0.5), Vector3(0.7, 1.8, d - 1.4), Color(0.55, 0.4, 0.25))
	_furn(node, Vector3(0.0, 0.9, -d * 0.5 + 0.5), Vector3(w - 1.6, 1.8, 0.7), Color(0.55, 0.4, 0.25))
	# stocked goods (colorful boxes on the shelves)
	for i in range(6):
		var gx := -w * 0.4 + float(i) * (w * 0.8 / 5.0)
		_furn(node, Vector3(gx, 1.55, -d * 0.5 + 0.5), Vector3(0.45, 0.4, 0.45), Color(randf() * 0.6 + 0.3, randf() * 0.6 + 0.2, randf() * 0.5 + 0.2), 0.6)
	# checkout counter near the doorway (right side)
	_furn(node, Vector3(w * 0.5 - 1.6, 0.55, d * 0.5 - 1.8), Vector3(2.4, 1.1, 0.9), Color(0.30, 0.28, 0.30), 0.5, 0.3)
	# a fridge
	_furn(node, Vector3(w * 0.5 - 0.7, 1.0, -1.5), Vector3(0.8, 2.0, 1.0), Color(0.85, 0.88, 0.9), 0.3, 0.4)
	_prop(node, "props/kk_furniture/shelf_B_large.glb", Vector3(0.0, 0.0, 0.6), 1.2)
	_sign(node, w, h, "BODEGA", Color(0.95, 0.78, 0.2))
	_register(node, w, d, rot, String(b.get("place", "bodega")), String(b.get("name", "Corner Bodega")), roofs, cellkey)

func _diner(b: Dictionary, wpos: Vector3, rot: float, root: Node, cellkey: String) -> void:
	var w := 9.0
	var d := 7.0
	var h := 3.4
	var node := _new_building(wpos, rot, root, d)
	_shell(node, w, d, h, Color(0.78, 0.78, 0.80))
	var roofs := _floor_and_roof(node, w, d, h, Color(0.86, 0.86, 0.84), Color(0.30, 0.32, 0.36))
	_ceiling_light(node, h, Color(1.0, 0.96, 0.88))
	# long service counter with stools, two booths
	_furn(node, Vector3(-w * 0.5 + 2.0, 0.55, -d * 0.5 + 1.3), Vector3(5.0, 1.1, 0.9), Color(0.75, 0.2, 0.18), 0.4, 0.2)
	for i in range(4):
		_prop(node, "props/kk_restaurant/chair_stool.glb", Vector3(-w * 0.5 + 0.6 + float(i) * 1.4, 0.0, -d * 0.5 + 2.4), 1.0)
	# booths (table + bench seats)
	for j in range(2):
		var bz := d * 0.5 - 1.6 - float(j) * 2.3
		_furn(node, Vector3(w * 0.5 - 2.2, 0.5, bz), Vector3(1.4, 0.15, 1.4), Color(0.55, 0.42, 0.28))
		_furn(node, Vector3(w * 0.5 - 2.2, 0.7, bz), Vector3(0.18, 0.6, 0.18), Color(0.4, 0.3, 0.2))
		_furn(node, Vector3(w * 0.5 - 1.1, 0.45, bz), Vector3(0.5, 0.9, 1.3), Color(0.75, 0.25, 0.22))
		_furn(node, Vector3(w * 0.5 - 3.3, 0.45, bz), Vector3(0.5, 0.9, 1.3), Color(0.75, 0.25, 0.22))
	_prop(node, "props/kk_restaurant/food_burger.glb", Vector3(-w * 0.5 + 2.0, 1.12, -d * 0.5 + 1.3), 1.4)
	_sign(node, w, h, "DINER", Color(0.95, 0.30, 0.30))
	_register(node, w, d, rot, String(b.get("place", "diner")), String(b.get("name", "The Diner")), roofs, cellkey)

func _lobby(b: Dictionary, wpos: Vector3, rot: float, root: Node, cellkey: String) -> void:
	var w := 8.0
	var d := 7.0
	var h := 3.6
	var node := _new_building(wpos, rot, root, d)
	# solid tower rising above the lobby
	var th := float(b.get("h", 20.0))
	var tower := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = Vector3(w, th, d)
	tower.mesh = tbm
	tower.material_override = _facade_mat(Color(0.5, 0.5, 0.54), float(b.get("seed", 3.0)))
	tower.position = Vector3(0, h + th * 0.5, 0)
	node.add_child(tower)
	var tbody := StaticBody3D.new()
	tbody.collision_layer = 1
	tbody.collision_mask = 0
	var tcs := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(w, th, d)
	tcs.shape = tbox
	tcs.position = Vector3(0, h + th * 0.5, 0)
	tbody.add_child(tcs)
	node.add_child(tbody)
	# the enterable ground-floor lobby
	_shell(node, w, d, h, Color(0.40, 0.42, 0.48))
	var roofs := _floor_and_roof(node, w, d, h, Color(0.55, 0.50, 0.46), Color(0.28, 0.28, 0.30))
	_ceiling_light(node, h, Color(0.95, 0.92, 0.95))
	# front desk, a couch, a potted plant, elevator doors on the back wall, a rug
	_furn(node, Vector3(-w * 0.5 + 2.2, 0.55, -d * 0.5 + 1.4), Vector3(3.2, 1.1, 0.9), Color(0.25, 0.22, 0.20), 0.4)
	_furn(node, Vector3(0.0, 0.02, 0.4), Vector3(3.0, 0.04, 2.4), Color(0.45, 0.18, 0.20), 0.7)
	_furn(node, Vector3(w * 0.5 - 1.4, 1.3, -d * 0.5 + 0.6), Vector3(1.2, 2.6, 0.15), Color(0.7, 0.72, 0.75), 0.3, 0.7)
	_furn(node, Vector3(w * 0.5 - 1.4, 1.3, -d * 0.5 + 0.6), Vector3(0.06, 2.4, 0.18), Color(0.1, 0.1, 0.12), 0.3, 0.6)
	_prop(node, "props/kk_furniture/couch.glb", Vector3(w * 0.4, 0.0, d * 0.4), 1.3, PI)
	_prop(node, "props/kk_furniture/cactus_medium_A.glb", Vector3(-w * 0.4, 0.0, d * 0.4), 1.4)
	_sign(node, w, h, "APARTMENTS", Color(0.55, 0.78, 0.95))
	_register(node, w, d, rot, String(b.get("place", "lobby")), String(b.get("name", "Apartment Lobby")), roofs, cellkey)

func _new_building(wpos: Vector3, rot: float, root: Node, d: float) -> Node3D:
	var node := Node3D.new()
	root.add_child(node)
	node.position = wpos
	node.rotation.y = rot
	node.set_meta("front_z", d * 0.5 + 0.05)
	return node

# ---------------- queries / eviction ----------------

# Which enterable building (if any) contains world position p? (rotated-rect test)
func building_at(p: Vector3) -> Dictionary:
	for b in buildings:
		var c: Vector3 = b["center"]
		var dx := p.x - c.x
		var dz := p.z - c.z
		var ca := cos(-float(b["rot"]))
		var sa := sin(-float(b["rot"]))
		var lx := dx * ca - dz * sa
		var lz := dx * sa + dz * ca
		if absf(lx) <= float(b["hx"]) - 0.3 and absf(lz) <= float(b["hz"]) - 0.3:
			return b
	return {}

func set_roof_visible(b: Dictionary, vis: bool) -> void:
	for r in b.get("roof", []):
		if is_instance_valid(r):
			(r as Node3D).visible = vis

func remove_cell(cellkey: String) -> void:
	var keep: Array = []
	for b in buildings:
		if String(b.get("cellkey", "")) != cellkey:
			keep.append(b)
	buildings = keep

func _xz(p) -> Vector2:
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO
