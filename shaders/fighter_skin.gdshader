// fighter_skin.gdshader
// PBR character shader with sweat, blood decal, and rim light.
// Assign to: res://assets/fighters/shared/mat_fighter_skin.tres
// Uses: albedo_tex, normal_tex, orm_tex (OcclusionRoughnessMetallic), emissive_tex

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ── PBR Inputs ──────────────────────────────
uniform sampler2D albedo_tex         : source_color,   filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex         : hint_normal,    filter_linear_mipmap;
uniform sampler2D orm_tex            : hint_default_white, filter_linear_mipmap; // R=AO G=Rough B=Metal
uniform sampler2D emissive_tex       : source_color,   filter_linear_mipmap;

// ── Tint / Identity ─────────────────────────
uniform vec4  skin_tint              : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_boost        : hint_range(0.0, 1.0) = 0.0;

// ── Sweat Effect ─────────────────────────────
uniform float sweat_intensity        : hint_range(0.0, 1.0) = 0.0;
uniform float sweat_drip_speed       : hint_range(0.0, 4.0) = 1.2;
uniform sampler2D sweat_noise        : hint_default_white, filter_linear_mipmap;

// ── Blood Decal ──────────────────────────────
uniform float blood_amount           : hint_range(0.0, 1.0) = 0.0;
uniform vec4  blood_color            : source_color = vec4(0.45, 0.0, 0.0, 1.0);
uniform sampler2D blood_mask         : hint_default_white;

// ── Rim Light ────────────────────────────────
uniform float rim_intensity          : hint_range(0.0, 2.0) = 0.8;
uniform vec4  rim_color              : source_color = vec4(1.0, 0.5, 0.1, 1.0);  // Orange rim

// ── Hit Flash ────────────────────────────────
uniform float hit_flash              : hint_range(0.0, 1.0) = 0.0; // Drive from GDScript on impact

// ── Globals ──────────────────────────────────
uniform float time_elapsed           : hint_range(0.0, 1000.0) = 0.0; // Set from FighterController

// ─────────────────────────────────────────────
varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos    = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;

	// ── Base Albedo ──────────────────────────
	vec4 albedo = texture(albedo_tex, uv) * skin_tint;

	// ── Blood Overlay ────────────────────────
	float blood_mask_val = texture(blood_mask, uv).r;
	vec4  blood_layer    = blood_color * blood_mask_val * blood_amount;
	albedo.rgb           = mix(albedo.rgb, blood_layer.rgb, blood_layer.a);

	// ── Sweat Wet Sheen ──────────────────────
	vec2 drip_uv    = uv + vec2(0.0, time_elapsed * sweat_drip_speed * 0.02);
	float sweat_val = texture(sweat_noise, drip_uv * 3.0).r;
	float sweat_wet = sweat_val * sweat_intensity;
	// Sweat darkens skin slightly and increases specularity
	albedo.rgb     *= 1.0 - sweat_wet * 0.18;

	// ── Hit Flash ────────────────────────────
	albedo.rgb = mix(albedo.rgb, vec3(1.0), hit_flash * 0.85);

	// ── ORM Texture ──────────────────────────
	vec3  orm         = texture(orm_tex, uv).rgb;
	float ao          = orm.r;
	float roughness   = clamp(orm.g + roughness_boost - sweat_wet * 0.35, 0.04, 1.0);
	float metallic    = orm.b;

	// ── Normal Map ───────────────────────────
	vec3 normal_map = texture(normal_tex, uv).rgb;
	NORMAL_MAP      = normal_map;
	NORMAL_MAP_DEPTH = 1.0;

	// ── Emissive (e.g. glowing tattoos) ──────
	vec3 emissive = texture(emissive_tex, uv).rgb;

	// ── Rim Light (non-PBR approximation) ────
	float rim       = 1.0 - dot(normalize(NORMAL), normalize(VIEW));
	rim             = pow(rim, 3.0) * rim_intensity;
	vec3 rim_contrib = rim_color.rgb * rim;

	// ── Final Output ─────────────────────────
	ALBEDO      = albedo.rgb;
	ROUGHNESS   = roughness;
	METALLIC    = metallic;
	AO          = ao;
	EMISSION    = emissive + rim_contrib;
	ALPHA       = albedo.a;
}
