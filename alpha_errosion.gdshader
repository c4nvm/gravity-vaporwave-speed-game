
shader_type spatial;

// Sample the texture and determine the alpha from summing the components
vec4 tex_color = {alpha_texture_str}; // Input texture
tex_color *= {alpha_channel_weights_str}; // Channel weights
float alpha = saturate(sum_components(tex_color));

if  ({invert_str}) { // invert
	alpha = 1.0 - alpha;
}

// Erosion factor is inverted to maintain values post-smoothstep
float erosion_midpoint = saturate(1.0 - {alpha_threshold_str}); // Erosion threshold

// At this point, the alpha is always between 0 and 1, and the erosion factor
// is also between 0 and 1. 
// If you imagine the ranges produced by erosion_midpoint - half_range and erosion_midpoint + half_range, 
// there will still be overlap between alpha and the erosion range when the erosion threshold is 0 or 1.
// This will cause graiients in the output. To avoid this, when erosion_threshold is zero or one, we can 
// expand the range of erosion_midpoint to extend from -0.5 to 1.5 and clamp the half-range slightly
// to ensure that there is never value overlap in the case of 0 or 1.

{erosion_midpoint_str}

// Clamp is to ensure exact 0 / 1 alpha values do not overlap with smootstep range
// when erosion threshold is 0 / 1
float half_range = clamp({alpha_range_str}, 0.01, 0.99) / 2.0; // Erosion range

// Apply erosion
alpha = smoothstep(
	erosion_midpoint - half_range, 
	erosion_midpoint + half_range, 
	alpha
);
float ranged_alpha = mix({output_range_str}.x, {output_range_str}.y, alpha);
{output_alpha_str} = alpha;

{output_ranged_alpha_str} = ranged_alpha;

""".format(str_dict) 


func _get_global_code(mode: Shader.Mode) -> String:
	return\
"""

float sum_components(vec4 color) {
	return color.r + color.g + color.b + color.a;
}

float saturate(float value) {
	return clamp(value, 0.0, 1.0);
}
"""
