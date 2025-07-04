shader_type spatial;
render_mode blend_mix, cull_back, unshaded;

uniform sampler2D custom_texture : source_color;
uniform bool use_custom_texture = false;

uniform vec2 texture_offset = vec2(0.0, 0.0);
uniform vec2 texture_scale = vec2(1.0, 1.0);
uniform float texture_rotation = 0.0; // em radianos

uniform float color_steps = 6.0;
uniform float dither_strength = 0.25;
uniform float pixel_size = 1.0;

vec3 quantize_color(vec3 color, float steps) {
    return floor(color * steps) / steps;
}

float bayer_dither(vec2 uv) {
    int x = int(mod(uv.x, 4.0));
    int y = int(mod(uv.y, 4.0));
    float bayer[16] = float[16](
         1.0,  9.0,  3.0, 11.0,
        13.0,  5.0, 15.0,  7.0,
         4.0, 12.0,  2.0, 10.0,
        16.0,  8.0, 14.0,  6.0
    );
    return bayer[y * 4 + x] / 17.0;
}

vec2 transform_uv(vec2 uv) {
    float cos_r = cos(texture_rotation);
    float sin_r = sin(texture_rotation);

    uv = uv * texture_scale + texture_offset;
    uv -= 0.5; // centraliza rotação
    mat2 rot = mat2(vec2(cos_r, -sin_r), vec2(sin_r, cos_r));
    uv = rot * uv;
    uv += 0.5;

    return uv;
}

void fragment() {
    vec2 pixel_uv = floor(FRAGCOORD.xy / pixel_size);
    float dither = bayer_dither(pixel_uv);

    vec4 base_color;

    if (use_custom_texture) {
        vec2 uv = transform_uv(UV);
        base_color = texture(custom_texture, uv);
    } else {
        base_color = vec4(ALBEDO, 1.0);
    }

    vec3 quantized_rgb = quantize_color(base_color.rgb + dither * dither_strength, color_steps);

    ALBEDO = quantized_rgb;
    ALPHA = base_color.a;
}