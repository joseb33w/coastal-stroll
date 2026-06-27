shader_type spatial;
// Procedural skyscraper facade: a grid of windows (some lit) over a concrete wall.
// Compatibility/WebGL2 safe — no screen reads, no GPU-only features.
render_mode cull_back;

uniform vec3 wall_color : source_color = vec3(0.46, 0.47, 0.50);
uniform vec3 window_color : source_color = vec3(0.09, 0.12, 0.17);
uniform vec3 lit_color : source_color = vec3(1.0, 0.86, 0.55);
uniform float floor_h = 1.5;
uniform float win_w = 1.25;
uniform float lit_frac = 0.34;
uniform float seed = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1)) + seed) * 43758.5453);
}

void fragment() {
	vec3 n = abs(NORMAL);
	if (n.y > 0.6) {
		// roof / floor faces -> plain concrete
		ALBEDO = wall_color * 0.82;
		ROUGHNESS = 0.92;
		METALLIC = 0.0;
	} else {
		vec2 uv = (n.x > n.z) ? vec2(lp.z, lp.y) : vec2(lp.x, lp.y);
		vec2 cell = vec2(win_w, floor_h);
		vec2 g = floor(uv / cell);
		vec2 f = fract(uv / cell);
		float mx = 0.20;
		float my = 0.24;
		float inwin = step(mx, f.x) * step(f.x, 1.0 - mx) * step(my, f.y) * step(f.y, 1.0 - my);
		float r = h21(g);
		float lit = step(1.0 - lit_frac, r);
		vec3 glass = mix(window_color, lit_color, lit * 0.85);
		ALBEDO = mix(wall_color, glass, inwin);
		ROUGHNESS = mix(0.88, 0.22, inwin);
		METALLIC = mix(0.0, 0.25, inwin);
		EMISSION = lit_color * inwin * lit * 1.4;
	}
}
