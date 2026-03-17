// arena_floor_wet.gdshader
// Wet asphalt / dirt arena floor with dynamic rain ripples and puddle reflections.
// Assign to arena ground plane MeshInstance3D material.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ── Base surface ──────────────────────────────
uniform sampler2D albedo_tex    : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex    : hint_normal,  filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex       : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2      tiling        = vec2(8.0, 8.0);

// ── Wetness ───────────────────────────────────
uniform float wetness           : hint_range(0.0, 1.0) = 0.7;   // 0 = dry, 1 = soaked
uniform vec3  water_tint        : source_color = vec3(0.15, 0.18, 0.22);
uniform sampler2D puddle_mask   : hint_default_white, filter_linear_mipmap;  // where puddles form

// ── Rain ripples ──────────────────────────────
uniform float rain_intensity    : hint_range(0.0, 1.0) = 0.6;
uniform float ripple_speed      : hint_range(0.0, 4.0) = 1.5;
uniform float ripple_scale      : hint_range(1.0, 30.0) = 12.0;

// ── Blood stains ──────────────────────────────
uniform sampler2D blood_map     : hint_default_white;  // painted at runtime via Decal nodes

// ── Time ─────────────────────────────────────
uniform float time_val          : hint_range(0.0, 1000.0) = 0.0;

// ─────────────────────────────────────────────
varying vec2 world_uv;

void vertex() {
	world_uv = (UV * tiling);
}

// ── Ripple function ────────────────────────────
// Generates expanding ring pattern from random drop points
vec2 rain_ripple(vec2 uv, float t) {
	vec2 result = vec2(0.0);
	// 4 overlapping ripple sources
	for (int i = 0; i < 4; i++) {
		float fi   = float(i);
		vec2  seed = vec2(fract(sin(fi * 127.1 + 311.7) * 43758.5), fract(sin(fi * 269.5 + 183.3) * 43758.5));
		vec2  pos  = (uv / ripple_scale) + seed;
		float d    = length(fract(pos) - 0.5);
		float phase = fract(t * ripple_speed + fi * 0.25);
		float ring  = 1.0 - abs(d - phase * 0.5) * 8.0;
		ring        = clamp(ring, 0.0, 1.0) * (1.0 - phase);   // fade as ring expands
		result.x   += ring * 0.015;
		result.y   += ring * 0.015 * sign(fract(pos.y) - 0.5);
	}
	return result * rain_intensity;
}

void fragment() {
	vec2 uv = world_uv;

	// ── Base textures ────────────────────────
	vec4 albedo = texture(albedo_tex, uv);
	vec3 orm    = texture(orm_tex,    uv).rgb;
	vec3 normal = texture(normal_tex, uv).rgb;

	// ── Puddle mask ──────────────────────────
	float puddle = texture(puddle_mask, UV).r * wetness;

	// ── Rain ripples (perturb normal) ────────
	vec2 ripple = rain_ripple(uv, time_val);
	normal.xy  += ripple * puddle;
	normal       = normalize(normal);

	// ── Wet surface effect ───────────────────
	// Darkens albedo, increases specularity/metalness
	vec3 wet_albedo = mix(albedo.rgb, albedo.rgb * 0.55 + water_tint * 0.15, puddle);

	float wet_roughness = mix(orm.g, 0.04, puddle * 0.9);   // Very smooth when wet
	float wet_metallic  = mix(orm.b, 0.25, puddle * 0.6);

	// ── Blood decals (sampled from blood_map, not runtime painted) ──
	vec4  blood      = texture(blood_map, UV);
	vec3  final_alb  = mix(wet_albedo, blood.rgb * 0.5, blood.a * 0.8);

	ALBEDO      = final_alb;
	NORMAL_MAP  = normal;
	ROUGHNESS   = wet_roughness;
	METALLIC    = wet_metallic;
	AO          = orm.r;
}
