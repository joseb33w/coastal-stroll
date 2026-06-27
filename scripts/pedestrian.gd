extends Node3D
## A wandering pedestrian: walks to random spots within a home radius, pauses, repeats.
## Drives its own embedded idle/walk clips (realistic chars ship them). Decorative (no
## collider); parented to its cell so it evicts with the cell.

const WALK_SPEED := 1.7

var model: Node3D
var anim: AnimationPlayer
var home: Vector3
var radius := 5.0
var target: Vector3
var paused := true
var pause_t := 0.0
var _cur := ""
var yaw := 0.0

func init(m: Node3D, home_pos: Vector3, r: float) -> void:
	model = m
	home = home_pos
	radius = r
	add_child(model)
	position = home_pos
	anim = _find_anim(model)
	_loopify_clips()
	yaw = randf() * TAU
	model.rotation.y = yaw
	_pick_target()
	pause_t = randf() * 1.5
	_play("idle")

func _find_anim(n: Node) -> AnimationPlayer:
	var stack: Array = [n]
	while not stack.is_empty():
		var x = stack.pop_back()
		if x is AnimationPlayer:
			return x
		for c in x.get_children():
			stack.append(c)
	return null

func _loopify_clips() -> void:
	if anim == null:
		return
	for nm in anim.get_animation_list():
		var a := anim.get_animation(nm)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR

func _play(clip: String) -> void:
	if anim == null or _cur == clip:
		return
	# resolve the actual clip name (libraries may prefix, e.g. "default/walk")
	var resolved := clip
	if not anim.has_animation(resolved):
		for nm in anim.get_animation_list():
			if String(nm).to_lower().ends_with(clip):
				resolved = nm
				break
	if anim.has_animation(resolved):
		anim.play(resolved, 0.2)
		_cur = clip

func _process(delta: float) -> void:
	if paused:
		pause_t -= delta
		_play("idle")
		if pause_t <= 0.0:
			paused = false
			_pick_target()
		return
	var to := target - position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.4:
		paused = true
		pause_t = randf_range(1.2, 3.5)
		_play("idle")
		return
	var dir := to / dist
	position += dir * WALK_SPEED * delta
	var want := atan2(dir.x, dir.z)
	yaw = lerp_angle(yaw, want, clampf(delta * 7.0, 0.0, 1.0))
	model.rotation.y = yaw
	_play("walk")

func _pick_target() -> void:
	var a := randf() * TAU
	var rr := sqrt(randf()) * radius
	target = home + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
