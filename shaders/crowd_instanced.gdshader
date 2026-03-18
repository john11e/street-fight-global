// crowd_instanced.gdshader
// MultiMeshInstance3D crowd shader — zero CPU animation cost.
// Each crowd figure is one mesh instance; all animation is vertex-shader driven.
//
// Per-instance data encoding (set via MultiMesh.set_instance_custom_data):
//   r = cheer state (0.0 = idle, 1.0 = arms raised / cheering)
//   g = sway phase offset (0.0–1.0, randomised per instance at spawn)
//   b = shirt atlas row  (0.0–1.0, maps to albedo atlas V coordinate)
//   a = reserved

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

// ── Textures ─────────────────────────────────
uniform sampler2D albedo_atlas  : source_color, filter_linear_mipmap;   // 4×4 grid of shirt colors
uniform sampler2D normal_map    : hint_normal,  filter_linear_mipmap;

// ── Animation ────────────────────────────────
uniform float time_uniform      : hint_range(0.0, 1000.0) = 0.0;  // Set from GDScript each frame
uniform float sway_amplitude    : hint_range(0.0, 0.1)    = 0.025; // Body sway magnitude
uniform float cheer_arm_angle   : hint_range(0.0, 1.5)    = 1.2;   // Arm raise radians
uniform float crowd_density_fog : hint_range(0.0, 1.0)    = 0.35;  // Far-crowd opacity fade

// ── Colour ───────────────────────────────────
uniform vec4  skin_base         : source_color = vec4(0.8, 0.65, 0.5, 1.0);
uniform float atlas_cols        : hint_range(1.0, 8.0) = 4.0;
uniform float atlas_rows        : hint_range(1.0, 8.0) = 4.0;

// ─────────────────────────────────────────────
varying vec3 world_pos;
varying vec4 instance_data;

void vertex() {
	// Read per-instance custom data
	instance_data = INSTANCE_CUSTOM;
	float cheer        = instance_data.r;
	float phase_offset = instance_data.g;
	float atlas_row    = instance_data.b;

	// ── Idle body sway ───────────────────────
	float t     = time_uniform + phase_offset * 6.2832;
	float sway  = sin(t * 1.8) * sway_amplitude;
	// Apply to upper body only (Y > 0.5 in local space)
	float upper = clamp((VERTEX.y - 0.5) * 2.0, 0.0, 1.0);
	VERTEX.x   += sway * upper;

	// ── Cheer: raise arms ────────────────────
	// Arms are identified by mesh vertices near X extremes and Y ~ 0.5–1.0
	float is_arm = step(0.45, abs(VERTEX.x)) * step(0.3, VERTEX.y);
	float arm_raise = cheer * cheer_arm_angle;
	// Rotate arm vertices upward around shoulder pivot
	if (is_arm > 0.5) {
		float sign_x = sign(VERTEX.x);
		float py     = VERTEX.y - 0.6;
		float px     = VERTEX.x - sign_x * 0.35;
		float cos_a  = cos(arm_raise * sign_x);
		float sin_a  = sin(arm_raise * sign_x);
		VERTEX.x = (cos_a * px - sin_a * py) + sign_x * 0.35;
		VERTEX.y = (sin_a * px + cos_a * py) + 0.6;
	}

	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	instance_data  = INSTANCE_CUSTOM;
	float atlas_row = instance_data.b;
	float cheer     = instance_data.r;

	// ── Atlas shirt color ────────────────────
	// Map UV.x to column, atlas_row to V band
	float col_idx = floor(UV.x * atlas_cols);
	float u_band  = (col_idx + 0.5) / atlas_cols;
	float v_band  = (atlas_row * atlas_rows + 0.5) / atlas_rows;
	vec2  atlas_uv = vec2(UV.x, v_band);
	vec4  shirt    = texture(albedo_atlas, atlas_uv);

	// ── Skin areas (UV.y < 0.35 = head/hands) ─
	float skin_mask = step(UV.y, 0.35);
	vec3  albedo    = mix(shirt.rgb, skin_base.rgb, skin_mask);

	// ── Cheer tint: slight brightness boost ──
	albedo += cheer * 0.08;

	// ── Distance fade (far crowd less opaque) ─
	float dist  = length(world_pos - CAMERA_POSITION_WORLD);
	float alpha = 1.0 - smoothstep(18.0, 28.0, dist) * crowd_density_fog;

	// ── Normal map ───────────────────────────
	NORMAL_MAP = texture(normal_map, UV).rgb;

	ALBEDO    = albedo;
	ROUGHNESS = 0.85;
	METALLIC  = 0.0;
	ALPHA     = alpha;
}
