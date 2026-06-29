shader_type spatial;
render_mode blend_add, unshaded, cull_back;

// Demerzel holographic face shader — gold wireframe aesthetic with scanlines,
// Fresnel edge glow, and holographic flicker. Foundation-era inspired.

uniform vec4 base_color : source_color = vec4(1.0, 0.84, 0.0, 0.7);
uniform float scanline_density : hint_range(50.0, 500.0) = 200.0;
uniform float scanline_speed : hint_range(0.1, 5.0) = 1.0;
uniform float fresnel_power : hint_range(1.0, 8.0) = 3.0;
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.08;
uniform float emission_strength : hint_range(0.0, 4.0) = 1.5;
uniform float wireframe_blend : hint_range(0.0, 1.0) = 0.15;
uniform float speaking_pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Fresnel — bright edges, transparent at direct angles
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);

	// Dual scanlines — coarse moving down, fine moving up
	float scan_coarse = sin(SCREEN_UV.y * scanline_density + TIME * scanline_speed * 20.0) * 0.5 + 0.5;
	float scan_fine = sin(SCREEN_UV.y * scanline_density * 3.0 - TIME * scanline_speed * 8.0) * 0.5 + 0.5;
	float scan = mix(0.6, 1.0, scan_coarse) * mix(0.85, 1.0, scan_fine);

	// Random flicker — ~8% chance per frame to dim
	float noise = fract(sin(dot(vec2(TIME * 43.758, SCREEN_UV.y * 12.9898), vec2(12.9898, 78.233))) * 43758.5453);
	float flicker = 1.0 - step(1.0 - flicker_intensity, noise) * 0.7;

	// Speaking pulse — rhythmic glow when Demerzel speaks
	float speak = 1.0 + speaking_pulse * sin(TIME * 12.0) * 0.3;

	// Wireframe hint — subtle edge darkening via barycentric approximation
	float edge = smoothstep(0.0, wireframe_blend, min(UV.x, min(UV.y, 1.0 - UV.x)));

	// Combine
	float alpha = base_color.a * scan * flicker * speak * (0.3 + fresnel * 0.7) * edge;

	ALBEDO = base_color.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
	EMISSION = base_color.rgb * emission_strength * (0.4 + fresnel * 0.6) * speak;
}
