shader_type canvas_item;
// Full-screen faint / wake effect: blur, chromatic split, tearing bands, vignette, black.
// Driven by game/fx/faint_fx.gd. All zeros = no visible change.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 1.0) = 0.0;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// "weak graphic anomaly": a few horizontal bands slip sideways
	float row = floor(uv.y * 48.0);
	float tear = step(1.0 - 0.06 * glitch, hash(row + floor(TIME * 12.0)));
	uv.x += tear * glitch * 0.035 * (hash(row * 3.1) - 0.5);
	float lod = blur * 4.5;
	vec2 split = vec2(glitch * 0.01, 0.0);
	vec3 col = vec3(
		textureLod(screen_tex, uv + split, lod).r,
		textureLod(screen_tex, uv, lod).g,
		textureLod(screen_tex, uv - split, lod).b);
	float vignette = smoothstep(0.95, 0.25, distance(SCREEN_UV, vec2(0.5)));
	col *= mix(1.0, vignette, clamp(blur * 1.2, 0.0, 1.0));
	col = mix(col, vec3(0.0), darkness);
	COLOR = vec4(col, 1.0);
}
