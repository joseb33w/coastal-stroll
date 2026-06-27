class_name WorldStreamer extends Node
## Seamless open-world chunk streaming: a 3x3 resident ring of cells around the player in a
## global coord space, AT MOST one cell built per frame, cells outside the ring evicted (the
## memory bound). Each cell renders ground + scatter + props + landmark + water + buildings +
## pedestrians from its world.json record. No fade between cells. Adapted from the verified
## rpg-template ChunkManager; combat/enemies removed, biome/buildings/pedestrians added.

const RING := 1
const PROP_CAP := 14
const SCATTER_MAX := 40
const PED := preload("res://scripts/pedestrian.gd")

signal cell_changed(zone: String, cell_id: String)

var assets: Assets
var interiors: Interiors
var player: Node3D
var world_main: Node
var env: Environment

var cell_size := 20.0
var grid := {}                       # "gx,gz" -> record
var start_cell := Vector2i.ZERO
var current_zone := "city"
var current_cell_id := "c0_0"

const PALETTE := {
	"tree": "props/q_unature/CommonTree_1.glb",
	"tree2": "props/q_unature/CommonTree_4.glb",
	"pine": "props/q_unature/PineTree_1.glb",
	"pine2": "props/q_unature/PineTree_3.glb",
	"birch": "props/q_unature/BirchTree_2.glb",
	"rock": "props/q_unature/Rock_1.glb",
	"rock2": "props/q_unature/Rock_5.glb",
	"rockmoss": "props/q_unature/Rock_Moss_3.glb",
	"bush": "props/q_unature/Bush_1.glb",
	"palm": "props/fs_terrain/beach_prop_tree_palm_1.glb",
	"palm2": "props/fs_terrain/beach_prop_tree_palm_2.glb",
}
const PED_MODELS := ["models/civ_woman.glb", "models/civ_man2.glb", "models/civ_walker.glb"]

var resident := {}
var _queue: Array = []
var _cur := Vector2i(2147483647, 0)
var _building := false
var _started := false
var _heading := Vector2i.ZERO
var _nav_root: Node3D
var _nav_region: NavigationRegion3D
var _ocean: Node3D

func setup(p: Node3D, a: Assets, main: Node, environment: Environment, inter: Interiors) -> void:
	player = p
	assets = a
	world_main = main
	env = environment
	interiors = inter

func start(world: Dictionary, has_resume := false, resume_pos := Vector3.ZERO, _resume_facing := 0.0) -> void:
	cell_size = float(world.get("grid", {}).get("cell_size", 20.0))
	if cell_size <= 0.0:
		cell_size = 20.0
	var sc: Array = world.get("start_cell", [0, 0])
	if sc.size() >= 2:
		start_cell = Vector2i(int(sc[0]), int(sc[1]))
	grid.clear()
	for c in world.get("cells", []):
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cc: Array = c.get("cell", [])
		if cc.size() < 2:
			continue
		grid[_key(int(cc[0]), int(cc[1]))] = c

	_nav_root = Node3D.new()
	world_main.add_child(_nav_root)

	# warm the shared character/furniture assets so the first cells pop in without a stall
	await assets.ensure(PED_MODELS)
	await assets.ensure(["models/npc_vendor.glb"])
	await interiors.preload_furniture()

	# resume position (only if it lands on an authored cell), else the world start cell
	var spawn_cell := start_cell
	var spawn_pos := _centre(start_cell.x, start_cell.y) + Vector3(0, 0.3, 0)
	if has_resume:
		var rc := Vector2i(floori(resume_pos.x / cell_size), floori(resume_pos.z / cell_size))
		if grid.has(_key(rc.x, rc.y)):
			spawn_cell = rc
			spawn_pos = resume_pos + Vector3(0, 0.3, 0)

	_build_ocean()
	_cur = spawn_cell
	await _build_at(spawn_cell.x, spawn_cell.y)   # _started=false here -> tick is inert, no spurious
	player.global_position = spawn_pos             # discovery from the player's temporary boot position
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	_started = true
	_rebuild_nav()
	_update_ring(spawn_cell)
	current_cell_id = _area_id(spawn_cell)
	current_zone = String(grid.get(_key(spawn_cell.x, spawn_cell.y), {}).get("zone", "city"))
	cell_changed.emit(current_zone, current_cell_id)

func tick(delta: float) -> void:
	if not _started:
		return
	var here := _player_cell()
	if here != _cur:
		var step := here - _cur
		if step != Vector2i.ZERO:
			_heading = Vector2i(signi(step.x), signi(step.y))
		_cur = here
		_update_ring(here)
		if grid.has(_key(here.x, here.y)):
			current_cell_id = _area_id(here)
			var z := String(grid[_key(here.x, here.y)].get("zone", current_zone))
			current_zone = z
			cell_changed.emit(current_zone, current_cell_id)
	# the player's OWN cell must exist NOW so they never stand over a hole (fast move / teleport)
	if not _building and grid.has(_key(_cur.x, _cur.y)) and not resident.has(_key(_cur.x, _cur.y)):
		_building = true
		await _build_at(_cur.x, _cur.y)
		_rebuild_nav()
		_building = false
	elif not _building and not _queue.is_empty():
		var nxt: Vector2i = _queue.pop_front()
		if not resident.has(_key(nxt.x, nxt.y)) and grid.has(_key(nxt.x, nxt.y)):
			_building = true
			await _build_at(nxt.x, nxt.y)
			_rebuild_nav()
			_building = false

# ---------------- ring ----------------

func _update_ring(centre: Vector2i) -> void:
	var wanted := {}
	for gx in range(centre.x - RING, centre.x + RING + 1):
		for gz in range(centre.y - RING, centre.y + RING + 1):
			var k := _key(gx, gz)
			if grid.has(k):
				wanted[k] = Vector2i(gx, gz)
	for rk: String in resident.keys():
		if not wanted.has(rk):
			_evict(rk)
	var order: Array = wanted.values()
	order.sort_custom(_priority.bind(centre))
	for cell: Vector2i in order:
		var k := _key(cell.x, cell.y)
		if resident.has(k) or cell in _queue:
			continue
		_queue.append(cell)

func _priority(a: Vector2i, b: Vector2i, centre: Vector2i) -> bool:
	# nearest-first so the player's OWN cell (Chebyshev 0) always builds before neighbours
	# (prevents floating over a hole on a fast move / teleport); heading breaks ties.
	var ca := _cheb(a, centre)
	var cb := _cheb(b, centre)
	if ca != cb:
		return ca < cb
	var ah := (a - centre).x * _heading.x + (a - centre).y * _heading.y
	var bh := (b - centre).x * _heading.x + (b - centre).y * _heading.y
	return ah > bh

func _evict(k: String) -> void:
	var rec = resident.get(k)
	if rec == null:
		resident.erase(k)
		return
	var root = rec.get("root")
	if root != null and is_instance_valid(root):
		(root as Node).queue_free()
	resident.erase(k)
	if interiors != null:
		interiors.remove_cell(k)

# ---------------- cell build ----------------

func _build_at(gx: int, gz: int) -> void:
	var k := _key(gx, gz)
	if resident.has(k) or not grid.has(k):
		return
	var rec: Dictionary = grid[k]
	await _build_cell(rec, gx, gz)   # registers `resident` itself once the floor exists

func _build_cell(rec: Dictionary, gx: int, gz: int) -> Node3D:
	var half := cell_size * 0.5
	var centre := Vector3(float(gx) * cell_size + half, 0.0, float(gz) * cell_size + half)

	var root := Node3D.new()
	world_main.add_child(root)

	# --- BUILD THE GROUND + WALLS + BUILDINGS FIRST (no downloads) so the player never
	# floats over a hole while the cell's streamed scenery is still downloading. ---
	var gcol := assets.col(rec.get("ground", [0.3, 0.32, 0.35]))
	assets.make_box(root, centre + Vector3(0, -0.5, 0), Vector3(cell_size, 1.0, cell_size), gcol, false)
	var apron := half * 0.25
	_edge(root, gx, gz, 0, -1, centre + Vector3(0, -0.5, -half - apron * 0.5), Vector3(cell_size, 1.0, apron), centre + Vector3(0, 2.0, -half), Vector3(cell_size, 5.0, 0.4))
	_edge(root, gx, gz, 0, 1, centre + Vector3(0, -0.5, half + apron * 0.5), Vector3(cell_size, 1.0, apron), centre + Vector3(0, 2.0, half), Vector3(cell_size, 5.0, 0.4))
	_edge(root, gx, gz, -1, 0, centre + Vector3(-half - apron * 0.5, -0.5, 0), Vector3(apron, 1.0, cell_size), centre + Vector3(-half, 2.0, 0), Vector3(0.4, 5.0, cell_size))
	_edge(root, gx, gz, 1, 0, centre + Vector3(half + apron * 0.5, -0.5, 0), Vector3(apron, 1.0, cell_size), centre + Vector3(half, 2.0, 0), Vector3(0.4, 5.0, cell_size))
	# procedural buildings (towers/cabs/enterable; their furniture is pre-cached in start()) — instant
	for b in rec.get("buildings", []):
		if typeof(b) == TYPE_DICTIONARY:
			interiors.build(b, centre, root, _key(gx, gz))
	# register NOW (floor exists) so eviction can free it if the player leaves mid-download
	resident[_key(gx, gz)] = {"root": root}

	# --- now stream the scenery assets in parallel, then place them (they pop in) ---
	var urls: Array = []
	_collect_urls(rec.get("scatter", []), urls)
	_collect_urls(rec.get("props", []), urls)
	var lm = rec.get("landmark", null)
	if typeof(lm) == TYPE_DICTIONARY:
		var lu := _ref_url(lm)
		if lu != "" and not urls.has(lu):
			urls.append(lu)
	if not urls.is_empty():
		await assets.ensure(urls)
	if not is_instance_valid(root):
		return root   # cell was evicted while its assets downloaded

	var lmark = rec.get("landmark", null)
	if typeof(lmark) == TYPE_DICTIONARY:
		_place_one(root, lmark, centre, half)
	var placed := 0
	for p in rec.get("props", []):
		if placed >= PROP_CAP:
			break
		if _place_one(root, p, centre, half):
			placed += 1
	for s in rec.get("scatter", []):
		_place_scatter(root, s, centre, half)

	# pedestrians (their models are pre-cached in start())
	_spawn_peds(rec, centre, half, root)

	return root

func _edge(root: Node, gx: int, gz: int, dx: int, dz: int, apron_pos: Vector3, apron_sz: Vector3, wall_pos: Vector3, wall_sz: Vector3) -> void:
	if grid.has(_key(gx + dx, gz + dz)):
		assets.collider_box(root, apron_pos, apron_sz)   # shared edge: thin anti-fall apron
	else:
		assets.collider_box(root, wall_pos, wall_sz)      # world border: invisible barrier (open-world look)

func _place_one(root: Node, ref, centre: Vector3, half: float) -> bool:
	if typeof(ref) != TYPE_DICTIONARY:
		return false
	# primitive colored box (sidewalks, plaza paving, road lines, boardwalk planks)
	if String(ref.get("prim", "")) == "box":
		var bxz := _xz(ref.get("pos", [0, 0]))
		var sz := _xyz(ref.get("size", [1, 1, 1]))
		var c := assets.col(ref.get("color", [0.5, 0.5, 0.5]))
		var py := sz.y * 0.5 + float(ref.get("y", 0.0))
		var pos := centre + Vector3(clampf(bxz.x, -half + 0.2, half - 0.2), py, clampf(bxz.y, -half + 0.2, half - 0.2))
		var m := assets.mat(c, float(ref.get("rough", 0.85)), float(ref.get("metal", 0.0)))
		if String(ref.get("collider", "none")) == "solid":
			var sb := assets.make_box(root, pos, sz, c, true, m)
			if ref.has("rot"):
				sb.rotation.y = deg_to_rad(float(ref.get("rot", 0.0)))
		else:
			var mi := assets.visual_box(root, pos, sz, m, bool(ref.get("shadow", false)))
			if ref.has("rot"):
				mi.rotation.y = deg_to_rad(float(ref.get("rot", 0.0)))
		return true
	var url := _ref_url(ref)
	if url == "":
		return false
	var n := assets.get_instance(url)
	if n == null:
		return false
	root.add_child(n)
	var xz := _xz(ref.get("pos", [0, 0]))
	n.position = centre + Vector3(clampf(xz.x, -half + 0.5, half - 0.5), 0.0, clampf(xz.y, -half + 0.5, half - 0.5))
	if ref.has("rot"):
		n.rotation.y = deg_to_rad(float(ref.get("rot", 0.0)))
	var sc := float(ref.get("scale", 1.0))
	if sc > 0.0 and sc != 1.0:
		n.scale = Vector3(sc, sc, sc)
	assets.ground(n)
	if String(ref.get("collider", "box")) == "mesh":
		assets.add_mesh_collision(n)
	elif ref.get("collider", "box") != "none":
		assets.add_prop_collision(n, root, float(ref.get("col_max", 3.5)))
	return true

func _place_scatter(root: Node, ref, centre: Vector3, half: float) -> void:
	if typeof(ref) != TYPE_DICTIONARY:
		return
	var url := _ref_url(ref)
	if url == "":
		return
	var src := assets.get_instance(url)
	if src == null:
		return
	var cnt := clampi(int(ref.get("count", 8)), 1, SCATTER_MAX)
	var base := float(ref.get("scale", 1.0))
	var mesh := _extract_mesh(src)
	src.queue_free()
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = cnt
	var amin := mesh.get_aabb().position.y
	for i in range(cnt):
		var sj := base * randf_range(0.82, 1.18)
		var b := Basis().rotated(Vector3.UP, randf() * TAU).scaled(Vector3(sj, sj, sj))
		var spot := Vector2(randf_range(-half + 1.0, half - 1.0), randf_range(-half + 1.0, half - 1.0))
		mm.set_instance_transform(i, Transform3D(b, Vector3(spot.x, -amin * sj, spot.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = centre
	root.add_child(mmi)

func _spawn_peds(rec: Dictionary, centre: Vector3, half: float, root: Node) -> void:
	var peds = rec.get("pedestrians", null)
	if peds == null:
		return
	if typeof(peds) == TYPE_INT or typeof(peds) == TYPE_FLOAT:
		var n := int(peds)
		for i in range(n):
			var url: String = PED_MODELS[randi() % PED_MODELS.size()]
			var pos := centre + Vector3(randf_range(-half + 2.0, half - 2.0), 0.0, randf_range(-half + 2.0, half - 2.0))
			_make_ped(root, url, pos, 5.0)
	elif typeof(peds) == TYPE_ARRAY:
		for pd in peds:
			if typeof(pd) != TYPE_DICTIONARY:
				continue
			var url := String(pd.get("model", PED_MODELS[randi() % PED_MODELS.size()]))
			var xz := _xz(pd.get("pos", [0, 0]))
			var pos := centre + Vector3(clampf(xz.x, -half + 2.0, half - 2.0), 0.0, clampf(xz.y, -half + 2.0, half - 2.0))
			_make_ped(root, url, pos, float(pd.get("radius", 4.0)))

func _make_ped(root: Node, url: String, pos: Vector3, radius: float) -> void:
	var model := assets.get_instance(url)
	if model == null:
		return
	var ped = Node3D.new()
	ped.set_script(PED)
	root.add_child(ped)
	ped.init(model, pos, radius)

# ---------------- ocean (persistent) ----------------

func _build_ocean() -> void:
	var max_gx := -2147483648
	var min_gz := 2147483647
	var min_gx := 2147483647
	for k: String in grid.keys():
		var parts := k.split(",")
		min_gx = mini(min_gx, int(parts[0]))
		max_gx = maxi(max_gx, int(parts[0]))
		min_gz = mini(min_gz, int(parts[1]))
	var north := float(min_gz) * cell_size   # the beach's north edge (z=0 for gz=0)
	var x0 := float(min_gx) * cell_size - 40.0
	var x1 := float(max_gx + 1) * cell_size + 40.0
	var width := x1 - x0
	_ocean = Node3D.new()
	world_main.add_child(_ocean)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, 260.0)
	pm.subdivide_width = 36
	pm.subdivide_depth = 36
	mi.mesh = pm
	var sh := ShaderMaterial.new()
	sh.shader = preload("res://shaders/water.gdshader")
	mi.material_override = sh
	mi.position = Vector3((x0 + x1) * 0.5, -0.25, north - 124.0)   # ocean stretches NORTH of the shore
	_ocean.add_child(mi)

# ---------------- shared flat nav (best-effort for peds; players don't need it) ----------------

func _rebuild_nav() -> void:
	if _nav_root == null:
		return
	if _nav_region != null and is_instance_valid(_nav_region):
		_nav_region.queue_free()
	var min_gx := start_cell.x
	var max_gx := start_cell.x
	var min_gz := start_cell.y
	var max_gz := start_cell.y
	for k: String in resident.keys():
		var parts := k.split(",")
		min_gx = mini(min_gx, int(parts[0]))
		max_gx = maxi(max_gx, int(parts[0]))
		min_gz = mini(min_gz, int(parts[1]))
		max_gz = maxi(max_gz, int(parts[1]))
	var x0 := float(min_gx) * cell_size - 1.0
	var x1 := float(max_gx + 1) * cell_size + 1.0
	var z0 := float(min_gz) * cell_size - 1.0
	var z1 := float(max_gz + 1) * cell_size + 1.0
	var nav := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.set_vertices(PackedVector3Array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]))
	nm.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	nav.navigation_mesh = nm
	_nav_root.add_child(nav)
	_nav_region = nav

# ---------------- helpers ----------------

func _collect_urls(arr, out: Array) -> void:
	if typeof(arr) != TYPE_ARRAY:
		return
	for e in arr:
		var u := _ref_url(e)
		if u != "" and not out.has(u):
			out.append(u)

func _ref_url(ref) -> String:
	if typeof(ref) != TYPE_DICTIONARY:
		return ""
	var u := String(ref.get("url", ref.get("model", "")))
	if u != "":
		return u
	var kind := String(ref.get("kind", ""))
	if PALETTE.has(kind):
		return PALETTE[kind]
	return ""

func _extract_mesh(scene: Node) -> Mesh:
	var stack: Array = [scene]
	while not stack.is_empty():
		var nn = stack.pop_back()
		if nn is MeshInstance3D and (nn as MeshInstance3D).mesh != null:
			return (nn as MeshInstance3D).mesh
		if nn is ImporterMeshInstance3D and (nn as ImporterMeshInstance3D).mesh != null:
			return (nn as ImporterMeshInstance3D).mesh.get_mesh()
		for c in nn.get_children():
			stack.append(c)
	return null

func _key(gx: int, gz: int) -> String:
	return str(gx) + "," + str(gz)

func _area_id(c: Vector2i) -> String:
	return "c" + str(c.x) + "_" + str(c.y)

func _player_cell() -> Vector2i:
	var p := player.global_position
	return Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))

func _centre(gx: int, gz: int) -> Vector3:
	return Vector3(float(gx) * cell_size + cell_size * 0.5, 0.0, float(gz) * cell_size + cell_size * 0.5)

func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func _xz(p) -> Vector2:
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO

func _xyz(p) -> Vector3:
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector3.ONE

func grid_world_rect() -> Rect2:
	var min_gx := 2147483647
	var max_gx := -2147483648
	var min_gz := 2147483647
	var max_gz := -2147483648
	for k: String in grid.keys():
		var parts := k.split(",")
		min_gx = mini(min_gx, int(parts[0]))
		max_gx = maxi(max_gx, int(parts[0]))
		min_gz = mini(min_gz, int(parts[1]))
		max_gz = maxi(max_gz, int(parts[1]))
	if min_gx > max_gx:
		return Rect2(cell_size * 0.5, cell_size * 0.5, cell_size, cell_size)
	var x0 := float(min_gx) * cell_size + cell_size * 0.5
	var z0 := float(min_gz) * cell_size + cell_size * 0.5
	return Rect2(x0, z0, float(max_gx - min_gx) * cell_size, float(max_gz - min_gz) * cell_size)
