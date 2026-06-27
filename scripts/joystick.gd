extends Control
## On-screen movement joystick visual (drawn only; input is handled in main._input).

var active := false
var base_pos := Vector2.ZERO
var knob_pos := Vector2.ZERO

func _draw() -> void:
	if not active:
		return
	draw_circle(base_pos, 74.0, Color(0.05, 0.06, 0.08, 0.30))
	draw_circle(base_pos, 74.0, Color(1, 1, 1, 0.22), false, 3.0)
	draw_circle(knob_pos, 36.0, Color(1, 1, 1, 0.38))
	draw_circle(knob_pos, 36.0, Color(1, 1, 1, 0.55), false, 2.0)
