shader_type spatial;
// Opaque stylized ocean — sine/Gerstner vertex waves + fresnel foam.
// No SCREEN_TEXTURE refraction (broken on web). Compatibility safe.

uniform vec3 deep : source_color = vec3(0.04, 0.22, 0.34);
uniform vec3 shallow : source_color = vec3(0.10, 0.40, 0.52);
uniform vec3 foam : source_color = vec3(0.85, 0.92, 0.95);
uniform float wave_amp = 0.18;

void vertex() {
	float w = sin(VERTEX.x * 0.35 + TIME * 1.4) * wave_amp
		+ cos(VERTEX.z * 0.28 + TIME * 1.1) * wave_amp * 0.8
		+ sin((VERTEX.x + VERTEX.z) * 0.5 + TIME * 0.7) * wave_amp * 0.4;
	VERTEX.y += w;
}

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	vec3 body = mix(deep, shallow, clamp(f * 1.6, 0.0, 1.0));
	ALBEDO = mix(body, foam, smoothstep(0.78, 1.0, f) * 0.7);
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
