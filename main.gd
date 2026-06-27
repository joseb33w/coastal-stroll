extends Node3D
## COASTAL STROLL — a small open-world coastal area (NYC downtown -> forest -> beach),
## chunk-streamed for mobile web. Third-person walk (touch joystick + WASD), enterable
## buildings with interiors, wandering pedestrians, per-biome ambient audio, and Supabase
## persistence (resume position + an explorer log of discovered places).

const L_WORLD := 1
const L_PLAYER := 2
const WALK_SPEED := 4.2
const GRAVITY := 22.0
const STEP_DIST := 2.1
const SAVE_INTERVAL := 3.0
const PLAYER_MODEL := "models/civ_walker.glb"

const ZONE_NAMES := {"city": "Downtown", "forest": "Forest", "beach": "Beach"}
const TOTAL_PLACES := 6

var origin := "https://preview.myapping.com"
var world_url := "https://preview.myapping.com/world.json"

var env: Environment
var sun: DirectionalLight3D
var player: CharacterBody3D
var avatar: Node3D
var anim: AnimationPlayer
var cam: Camera3D
var assets: Assets
var interiors: Interiors
var streamer: WorldStreamer

var yaw := 0.0
var step_accum := 0.0
var anim_cur := ""
var cam_inside := 0.0          # 0 outside .. 1 inside (smoothed)

# input
var move_idx := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO

# HUD
var hud: CanvasLayer
var counter_lbl: Label
var zone_lbl: Label
var hint_lbl: Label
var joy

# persistence
var discovered := {}           # place_id -> true
var save_t := 0.0
var last_saved := Vector3(99999, 0, 0)
var inside_place := ""
var prev_building := {}
var sb_ready := false
var world_ready := false
var _dbg_on := false
var _dbg_t := 0.0


func _ready() -> void:
	_force_fill()
	if OS.has_feature("web"):
		var o = JavaScriptBridge.eval("window.location.origin", true)
		if typeof(o) == TYPE_STRING and String(o) != "":
			origin = String(o)
		var dir = JavaScriptBridge.eval("window.location.href.replace(/[^/]*$/, '')", true)
		if typeof(dir) == TYPE_STRING and String(dir) != "":
			world_url = String(dir) + "world.json"
		var h = JavaScriptBridge.eval("location.hash||''", true)
		if typeof(h) == TYPE_STRING and "dbg" in String(h):
			_dbg_on = true

	_build_environment()
	_build_player()
	_build_hud()
	_show_loading()
	AudioManager.show_tap_overlay()
	_setup_audio()

	assets = Assets.new()
	assets.origin = origin
	assets.build_dir = world_url.replace("world.json", "")
	add_child(assets)

	interiors = Interiors.new()
	interiors.setup(assets)
	add_child(interiors)

	streamer = WorldStreamer.new()
	streamer.setup(player, assets, self, env, interiors)
	streamer.cell_changed.connect(_on_cell_changed)
	add_child(streamer)

	_boot()


func _force_fill() -> void:
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.size_changed.connect(_relayout)


# ---------------- boot ----------------

func _boot() -> void:
	var wq := HTTPRequest.new()
	add_child(wq)
	wq.request(world_url)
	var wr = await wq.request_completed
	wq.queue_free()
	if int(wr[1]) != 200:
		if hint_lbl:
			hint_lbl.text = "world.json fetch failed (%s)" % str(wr[1])
		return
	var raw := (wr[3] as PackedByteArray).get_string_from_utf8()
	var world = JSON.parse_string(raw)
	if not (world is Dictionary):
		if hint_lbl:
			hint_lbl.text = "world.json parse error"
		return

	# load the player avatar model
	await assets.ensure([PLAYER_MODEL])
	avatar = assets.get_instance(PLAYER_MODEL)
	if avatar != null:
		avatar.visible = false   # hidden until the world is ready (no falling-avatar on boot)
		player.add_child(avatar)
		anim = _find_anim(avatar)
		_loop_clips(anim)

	# wait briefly for the Supabase bridge (auth + load), then resume
	var resume := await _wait_supabase()
	for pid in resume.get("places", []):
		discovered[String(pid)] = true
	_refresh_counter()
	var has_resume := false
	var rpos := Vector3.ZERO
	var rface := 0.0
	var st = resume.get("state", null)
	if typeof(st) == TYPE_DICTIONARY:
		rpos = Vector3(float(st.get("pos_x", 0)), maxf(0.0, float(st.get("pos_y", 0))), float(st.get("pos_z", 0)))
		rface = float(st.get("facing", 0))
		has_resume = true
		yaw = rface

	await streamer.start(world, has_resume, rpos, rface)
	if has_resume and avatar != null:
		avatar.rotation.y = rface
	if avatar != null:
		avatar.visible = true
	world_ready = true
	_hide_loading()


func _wait_supabase() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var t := 0.0
	while t < 3.2:
		var raw = JavaScriptBridge.eval("(window.__gogi&&window.__gogi.ready)?JSON.stringify(window.__gogi):''", true)
		if typeof(raw) == TYPE_STRING and String(raw) != "":
			var d = JSON.parse_string(String(raw))
			if d is Dictionary:
				sb_ready = true
				return d
		await get_tree().create_timer(0.15).timeout
		t += 0.15
	return {}


# ---------------- movement ----------------

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if not world_ready:
		# the world is still streaming the spawn cell in — keep the body frozen so it can't
		# free-fall through the not-yet-built ground (a loading veil hides this on web).
		player.velocity = Vector3.ZERO
		return
	var v := _keyboard_vec() + move_vec
	if v.length() > 1.0:
		v = v.normalized()
	var dir := Vector3(v.x, 0.0, v.y)
	var speed := dir.length() * WALK_SPEED
	if speed > 0.1:
		player.velocity.x = dir.normalized().x * speed
		player.velocity.z = dir.normalized().z * speed
		var want := atan2(dir.x, dir.z)
		yaw = lerp_angle(yaw, want, clampf(delta * 9.0, 0.0, 1.0))
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, WALK_SPEED * 2.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, WALK_SPEED * 2.0 * delta)
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	else:
		player.velocity.y = -1.0
	player.move_and_slide()
	if avatar != null:
		avatar.rotation.y = yaw

	# locomotion anim + footsteps
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	_play_anim("walk" if hspeed > 0.6 else "idle")
	if hspeed > 0.6 and player.is_on_floor():
		step_accum += hspeed * delta
		if step_accum >= STEP_DIST:
			step_accum = 0.0
			var p := 1.0
			match streamer.current_zone:
				"beach": p = 1.18
				"forest": p = 0.92
				_: p = 1.0
			AudioManager.play_sfx("foot", -5.0, p * randf_range(0.94, 1.06))


func _process(delta: float) -> void:
	if streamer != null:
		streamer.tick(delta)
	_update_building_state()
	_update_camera(delta)
	# debounced save
	save_t += delta
	if save_t >= SAVE_INTERVAL:
		save_t = 0.0
		_save_now()
	if _dbg_on:
		_dbg(delta)


# ---------------- verification hooks (URL #dbg only) ----------------

func _dbg(delta: float) -> void:
	_dbg_t += delta
	if _dbg_t < 0.15:
		return
	_dbg_t = 0.0
	var cmd = JavaScriptBridge.eval("window.__dbg_cmd||''", true)
	if typeof(cmd) == TYPE_STRING and String(cmd) != "":
		JavaScriptBridge.eval("window.__dbg_cmd=''", true)
		_dbg_cmd(String(cmd))
	var p := player.global_position
	var z := streamer.current_zone if streamer != null else ""
	var nb := 0
	var bat := ""
	if interiors != null:
		nb = interiors.buildings.size()
		bat = String(interiors.building_at(p).get("place", ""))
	var js := "window.__dbg={booted:1,ready:%d,px:%f,py:%f,pz:%f,oy:%d,cy:%f,yaw:%f,zone:'%s',inside:'%s',bat:'%s',disc:%d,buildings:%d}" % [
		1 if world_ready else 0, p.x, p.y, p.z, (1 if player.is_on_floor() else 0), cam.global_position.y, yaw, z, inside_place, bat, discovered.size(), nb]
	JavaScriptBridge.eval(js, true)


func _dbg_cmd(c: String) -> void:
	if c == "enter_building" and interiors != null and interiors.buildings.size() > 0:
		var b: Dictionary = interiors.buildings[0]
		var ctr: Vector3 = b["center"]
		player.global_position = Vector3(ctr.x, 0.6, ctr.z)
		player.velocity = Vector3.ZERO
		_update_building_state()
	elif c.begins_with("goto:"):
		var parts := c.substr(5).split(",")
		if parts.size() >= 2:
			player.global_position = Vector3(int(parts[0]) * 20.0 + 10.0, 0.6, int(parts[1]) * 20.0 + 10.0)
			player.velocity = Vector3.ZERO


func _keyboard_vec() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1.0
	return v


# ---------------- camera (third person, wall-aware) ----------------

func _update_camera(delta: float) -> void:
	if cam == null or player == null:
		return
	var inside_target := 1.0 if inside_place != "" else 0.0
	cam_inside = move_toward(cam_inside, inside_target, delta * 3.0)
	var look := player.global_position + Vector3(0, 1.3, 0)
	var off_out := Vector3(0, 6.2, 8.4)
	var off_in := Vector3(0, 3.6, 5.0)
	var off := off_out.lerp(off_in, cam_inside)
	var desired := player.global_position + off
	# pull the camera in if a wall/building is between the look point and the desired cam pos
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(look, desired, L_WORLD)
	q.exclude = [player]
	var hit := space.intersect_ray(q)
	if hit.has("position"):
		var pulled := (hit["position"] as Vector3) + (look - desired).normalized() * 0.4
		# don't yank to an extreme close-up: keep a minimum distance from the look point
		if pulled.distance_to(look) < 3.0:
			pulled = look + (pulled - look).normalized() * 3.0
		desired = pulled
	cam.global_position = cam.global_position.lerp(desired, clampf(delta * 8.0, 0.0, 1.0))
	cam.look_at(look, Vector3.UP)


# ---------------- buildings (enter / exit) ----------------

func _update_building_state() -> void:
	if interiors == null or player == null:
		return
	var b := interiors.building_at(player.global_position)
	var place := String(b.get("place", "")) if not b.is_empty() else ""
	if place == inside_place:
		return
	# left previous building
	if inside_place != "" and not prev_building.is_empty():
		interiors.set_roof_visible(prev_building, true)
		AudioManager.play_sfx("door_close", -3.0)
	# entered new building
	if place != "":
		interiors.set_roof_visible(b, false)
		AudioManager.play_sfx("door_open", -3.0)
		_discover(place, String(b.get("name", "Building")))
	inside_place = place
	prev_building = b
	_refresh_zone_label()


# ---------------- zones / discovery ----------------

func _on_cell_changed(zone: String, _cell_id: String) -> void:
	_refresh_zone_label()
	if ZONE_NAMES.has(zone):
		_discover(zone, String(ZONE_NAMES[zone]))
	_swap_ambient(zone)


func _discover(place_id: String, place_name: String) -> void:
	if place_id == "" or discovered.has(place_id):
		return
	discovered[place_id] = true
	_refresh_counter()
	_flash_discovery(place_name)
	if OS.has_feature("web"):
		var js := "window.gogiDiscover && window.gogiDiscover(%s,%s)" % [JSON.stringify(place_id), JSON.stringify(place_name)]
		JavaScriptBridge.eval(js, true)


func _save_now() -> void:
	if player == null or not OS.has_feature("web") or not sb_ready:
		return
	if player.global_position.distance_to(last_saved) < 0.6:
		return
	last_saved = player.global_position
	var p := player.global_position
	var js := "window.gogiSave && window.gogiSave(%f,%f,%f,%f,%s)" % [p.x, p.y, p.z, yaw, JSON.stringify(streamer.current_zone)]
	JavaScriptBridge.eval(js, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_save_now()


# ---------------- input ----------------

func _input(event: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		var et := event as InputEventScreenTouch
		if et.pressed and et.position.x < half and move_idx == -1:
			move_idx = et.index
			move_origin = et.position
			move_vec = Vector2.ZERO
			_joy_show(true, et.position, et.position)
		elif not et.pressed and et.index == move_idx:
			move_idx = -1
			move_vec = Vector2.ZERO
			_joy_show(false, Vector2.ZERO, Vector2.ZERO)
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == move_idx:
		var ed := event as InputEventScreenDrag
		move_vec = ((ed.position - move_origin) / 90.0).limit_length(1.0)
		_joy_show(true, move_origin, move_origin + move_vec * 70.0)


# ---------------- environment ----------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.02
	env.fog_enabled = true
	env.fog_light_color = Color(0.80, 0.84, 0.88)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.15
	var sky := Sky.new()
	var sky_tex = load("res://skies/coast_sky.hdr")
	if sky_tex != null:
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/hdri_sky.gdshader")
		sm.set_shader_parameter("panorama", sky_tex)
		sm.set_shader_parameter("exposure", 0.72)
		sky.sky_material = sm
	else:
		var pm := ProceduralSkyMaterial.new()
		pm.sky_top_color = Color(0.34, 0.54, 0.84)
		pm.sky_horizon_color = Color(0.78, 0.83, 0.86)
		pm.ground_horizon_color = Color(0.70, 0.72, 0.72)
		pm.ground_bottom_color = Color(0.42, 0.44, 0.44)
		sky.sky_material = pm
	env.sky = sky
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -50.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.shadow_enabled = true
	sun.shadow_normal_bias = 2.0
	sun.directional_shadow_max_distance = 55.0
	add_child(sun)
	get_viewport().msaa_3d = Viewport.MSAA_2X


# ---------------- player ----------------

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.collision_layer = L_PLAYER
	player.collision_mask = L_WORLD
	add_child(player)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.9
	player.add_child(cs)
	cam = Camera3D.new()
	cam.current = true
	cam.fov = 62.0
	add_child(cam)
	cam.global_position = Vector3(0, 6, 8)


# ---------------- HUD ----------------

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	joy = preload("res://scripts/joystick.gd").new()
	joy.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(joy)
	counter_lbl = _mk_label(28, Color(0.96, 0.98, 1.0))
	hud.add_child(counter_lbl)
	zone_lbl = _mk_label(40, Color(1.0, 0.97, 0.86))
	zone_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(zone_lbl)
	hint_lbl = _mk_label(22, Color(0.85, 0.9, 0.95))
	hud.add_child(hint_lbl)
	hint_lbl.text = "Drag the left side to walk  (or WASD)"
	_refresh_counter()
	_relayout()


func _mk_label(sz: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _relayout() -> void:
	var ins := _safe_insets()
	var vp := get_viewport().get_visible_rect().size
	if counter_lbl:
		counter_lbl.position = Vector2(maxf(16, ins.get("left", 0) + 8), maxf(14, ins.get("top", 0) + 8))
	if zone_lbl:
		zone_lbl.size = Vector2(vp.x, 56)
		zone_lbl.position = Vector2(0, maxf(16, ins.get("top", 0) + 10))
	if hint_lbl:
		hint_lbl.position = Vector2(maxf(16, ins.get("left", 0) + 8), vp.y - maxf(34, ins.get("bottom", 0)) - 30)
	if joy:
		joy.size = vp


func _refresh_counter() -> void:
	if counter_lbl:
		counter_lbl.text = "Discovered: %d / %d" % [discovered.size(), TOTAL_PLACES]


func _refresh_zone_label() -> void:
	if zone_lbl == null:
		return
	if inside_place != "" and not prev_building.is_empty():
		zone_lbl.text = String(prev_building.get("name", ""))
	else:
		zone_lbl.text = String(ZONE_NAMES.get(streamer.current_zone, "")) if streamer != null else ""


func _flash_discovery(place_name: String) -> void:
	if hint_lbl == null:
		return
	hint_lbl.text = "Discovered: " + place_name + "!"
	var tw := hint_lbl.create_tween()
	hint_lbl.modulate = Color(1, 1, 0.7, 1)
	tw.tween_property(hint_lbl, "modulate", Color(0.85, 0.9, 0.95, 1.0), 2.2)


func _safe_insets() -> Dictionary:
	if not OS.has_feature("web"):
		return {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}
	var js := """(() => { const d = document.createElement('div');
	  d.style.cssText='position:fixed;top:env(safe-area-inset-top);bottom:env(safe-area-inset-bottom);left:env(safe-area-inset-left);right:env(safe-area-inset-right)';
	  document.body.appendChild(d); const r=getComputedStyle(d);
	  const o={top:parseFloat(r.top)||0,bottom:parseFloat(r.bottom)||0,left:parseFloat(r.left)||0,right:parseFloat(r.right)||0};
	  d.remove(); return JSON.stringify(o); })()"""
	var raw = JavaScriptBridge.eval(js, true)
	if typeof(raw) != TYPE_STRING or String(raw) == "":
		return {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}
	var d = JSON.parse_string(String(raw))
	return d if d is Dictionary else {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}


# ---------------- audio ----------------

func _setup_audio() -> void:
	_reg("foot", "res://audio/foot1.ogg")
	_reg("foot2", "res://audio/foot2.ogg")
	_reg("door_open", "res://audio/door_open.ogg")
	_reg("door_close", "res://audio/door_close.ogg")
	if ResourceLoader.exists("res://audio/music.ogg"):
		AudioManager.play_music(load("res://audio/music.ogg"), -10.0)


func _reg(n: String, path: String) -> void:
	if ResourceLoader.exists(path):
		AudioManager.register_sfx(n, load(path))


func _swap_ambient(zone: String) -> void:
	var path := "res://audio/amb_city.ogg"
	match zone:
		"forest": path = "res://audio/amb_forest.ogg"
		"beach": path = "res://audio/amb_beach.ogg"
		_: path = "res://audio/amb_city.ogg"
	if ResourceLoader.exists(path):
		AudioManager.play_ambient(load(path), -11.0)


# ---------------- anim / joystick helpers ----------------

func _play_anim(clip: String) -> void:
	if anim == null or anim_cur == clip:
		return
	var resolved := clip
	if not anim.has_animation(resolved):
		for nm in anim.get_animation_list():
			if String(nm).to_lower().ends_with(clip):
				resolved = nm
				break
	if anim.has_animation(resolved):
		anim.play(resolved, 0.2)
		anim_cur = clip


func _find_anim(n: Node) -> AnimationPlayer:
	var stack: Array = [n]
	while not stack.is_empty():
		var x = stack.pop_back()
		if x is AnimationPlayer:
			return x
		for c in x.get_children():
			stack.append(c)
	return null


func _loop_clips(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	for nm in ap.get_animation_list():
		var a := ap.get_animation(nm)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR


func _joy_show(active: bool, base: Vector2, knob: Vector2) -> void:
	if joy == null:
		return
	joy.active = active
	joy.base_pos = base
	joy.knob_pos = knob
	joy.queue_redraw()


# ---------------- loading veil (covers the boot stream-in) ----------------

var loading_veil: CanvasLayer

func _show_loading() -> void:
	loading_veil = CanvasLayer.new()
	loading_veil.layer = 150
	add_child(loading_veil)
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.08, 0.11, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_veil.add_child(dim)
	var lbl := Label.new()
	lbl.text = "Loading the coast..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_veil.add_child(lbl)

func _hide_loading() -> void:
	if loading_veil != null and is_instance_valid(loading_veil):
		loading_veil.queue_free()
		loading_veil = null
