shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon; //cull disabled to avoid invisible tree bottoms

group_uniforms toon_shader_settings;
uniform bool toon_shaded = true;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float shadow_size = 0.045;
uniform float shadow_blend = 0.001;
uniform float shadow_extra_intensity = 0.0;
uniform vec4 shadow_color : source_color;
uniform vec4 light_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rimlight_size = 0.921;
uniform float rimlight_blend = 0.01;
uniform vec4 rimlight_color : source_color;
uniform bool use_shadow_normalmap = true;
uniform bool animated = true;
uniform float time_scale = 0.02;
uniform vec3 normal_bias = vec3(0.0);
uniform vec3 light_bias = vec3(0.0);
uniform bool use_view = true;
uniform vec4 view_bias : source_color = vec4(1.0, 0.0, 1.0, 1.0);
uniform float view_multiplier : hint_range(-1.0, 1.0) = -1.0;
uniform sampler2D shadow_edge_normal_map : source_color;


group_uniforms triplanar_texture_settings;
uniform bool world_project_toggle = false;
uniform float normal_intensity : hint_range(-16.0, 16.0);
varying vec3 triplanar_pos;

uniform float blend_sharpness : hint_range(0.0, 150.0, 0.001) = 10.;
varying vec3 power_normal;

uniform float Tiling_Scale = 0.5;
uniform float Tiling_Offset = 0.0;

group_uniforms textures;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_albedo1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_albedo2 : source_color, filter_linear_mipmap, repeat_enable;


uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_normal1 : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_normal2 : hint_roughness_normal, filter_linear_mipmap, repeat_enable;


float fresnel(float amount, vec3 normal, vec3 view)
{
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0 )), amount);
}


void vertex(){

	if (world_project_toggle)
	{
		vec3 normal = MODEL_NORMAL_MATRIX * NORMAL;

		TANGENT = vec3(0.0, 0.0, -1.0) * abs(normal.x);
		TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.y);
		TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.z);
		TANGENT = inverse(MODEL_NORMAL_MATRIX) * normalize(TANGENT);

		BINORMAL = vec3(0.0, 1.0, 0.0) * abs(normal.x);
		BINORMAL += vec3(0.0, 0.0, -1.0) * abs(normal.y);
		BINORMAL += vec3(0.0, 1.0, 0.0) * abs(normal.z);
		BINORMAL = inverse(MODEL_NORMAL_MATRIX) * normalize(BINORMAL);

		power_normal = pow(abs(normal), vec3(blend_sharpness));
		triplanar_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * Tiling_Scale + Tiling_Offset;
		power_normal /= dot(power_normal, vec3(1.0));
		triplanar_pos *= vec3(1., -.5, 1.0);
	}
	else
	{
		vec3 normal = NORMAL;

		TANGENT = vec3(0.0, 0.0, -1.0) * abs(normal.x);
		TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.y);
		TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.z);
		TANGENT = normalize(TANGENT);

		BINORMAL = vec3(0.0, 1.0, 0.0) * abs(normal.x);
		BINORMAL += vec3(0.0, 0.0, -1.0) * abs(normal.y);
		BINORMAL += vec3(0.0, 1.0, 0.0) * abs(normal.z);
		BINORMAL = normalize(BINORMAL);

		// UV1 Triplanar: Enabled
		power_normal = pow(abs(NORMAL), vec3(blend_sharpness));
		triplanar_pos = VERTEX * Tiling_Scale + Tiling_Offset;
		power_normal /= dot(power_normal, vec3(1.0));
		triplanar_pos *= vec3(1.0, -1.0, 1.0);
	}
}

vec4 triplanar_texture(sampler2D p_sampler, sampler2D p_sampler1, sampler2D p_sampler2, vec3 p_weights, vec3 p_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(p_sampler, p_triplanar_pos.xy) * p_weights.z;
	samp += texture(p_sampler1, p_triplanar_pos.xz) * p_weights.y;
	samp += texture(p_sampler2, p_triplanar_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
	return samp;
}

void fragment(){
	vec4 albedo_tex = triplanar_texture(texture_albedo, texture_albedo1, texture_albedo2, power_normal, triplanar_pos);

	ALBEDO = albedo_tex.rgb * tint.rgb;
	NORMAL_MAP = triplanar_texture(texture_normal, texture_normal1, texture_normal2, power_normal, triplanar_pos).rgb;
	NORMAL_MAP_DEPTH = normal_intensity;
}

// Begin Region: Functions that reset lighting to defauit Godot lighting
float DistributionGGX(float cos_theta_m, float alpha)
{
	float alpha2 = alpha * alpha;
	float d = 1.0 + (alpha2 - 1.0) * cos_theta_m * cos_theta_m;
	return alpha2 / (PI * d * d);
}

float GeometryGGX(float NdotL, float NdotV, float alpha)
{
	return 0.5 / mix(2.0 * NdotL * NdotV, NdotL + NdotV, alpha);
}

vec3 SchlickBaseReflectivity(float metallic, float specular, vec3 albedo)
{
	float dielectric = 0.04 * specular * specular;
	return mix(vec3(dielectric), albedo, vec3(metallic));
}

float SchlickFresnel(float u)
{
	float m = 1.0 - u;
	float m2 = m * m;
	return m2 * m2 * m;
}
// End Region

void light(){
	vec3 normal;
	if (toon_shaded)
	{
		if (use_shadow_normalmap){
			vec3 normal_from_texture;
			if (animated){
				normal_from_texture = texture(shadow_edge_normal_map, UV + TIME * time_scale).rgb;
			}else{
				normal_from_texture = texture(shadow_edge_normal_map, UV).rgb;
			}
			normal = vec3(normal_from_texture.x * NORMAL.x,
			normal_from_texture.y * NORMAL.y, normal_from_texture.z);

			normal = NORMAL - normal_from_texture;
		}else{
			normal = NORMAL;
		}

		if (use_view){
			normal -= VIEW * view_bias.rgb * view_multiplier;
		}

		float NdotL = dot(normal + normal_bias, LIGHT + light_bias);

		float rounded = smoothstep(shadow_size, shadow_blend + shadow_size, NdotL);
		float one_minus = 1.0 - rounded;
		vec3 mult1 = LIGHT_COLOR * rounded * light_tint.rgb * ATTENUATION;
		vec3 mult2 = (one_minus * 1.4 * shadow_color.rgb) - shadow_extra_intensity;
		//vec3 add1 = mult1 + mult2;
		vec3 add1 = mult1 + mult2;

		float add3  = rimlight_blend + rimlight_size;
		float basic_fresnel = fresnel(1.0, NORMAL, VIEW);
		float smoothed = smoothstep(rimlight_size, add3, basic_fresnel);

		//vec3 add2 = add1 + smoothed * rimlight_color.rgb;
		vec3 add2 = add1 + smoothed * rimlight_color.rgb;
		DIFFUSE_LIGHT += ALBEDO * add2;
	}
	else // reset lighting to default Godot Lighting
	{
		vec3 lightColor = LIGHT_COLOR / PI;

		vec3 half = normalize(VIEW + LIGHT);

		float NdotL = max(dot(NORMAL, LIGHT), 0.0);
		float NdotV = max(dot(NORMAL, VIEW), 0.0);
		float NdotH = max(dot(NORMAL, half), 0.0);
		float LdotH = max(dot(LIGHT, half), 0.0);

		// Diffuse light (Lambert).
		DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * lightColor;

		// Specular light (Schlick-GGX).
		float ggxAlpha = ROUGHNESS * ROUGHNESS;
		float D = DistributionGGX(NdotH, ggxAlpha);
		float G = GeometryGGX(NdotL, NdotV, ggxAlpha);

		vec3 f0 = SchlickBaseReflectivity(METALLIC, SPECULAR_AMOUNT, ALBEDO);
		float LdotH5 = SchlickFresnel(LdotH);
		float f90 = clamp(50.0 * f0.g, 0.0, 1.0);
		vec3 F = f0 + (f90 - f0) * LdotH5;

		vec3 specularBRDF = max(NdotL * D * G * F, 0.0);
		SPECULAR_LIGHT += specularBRDF * LIGHT_COLOR * ATTENUATION;
	}
}
