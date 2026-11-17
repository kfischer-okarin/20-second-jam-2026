// Pixel post-processing of the low resolution scene:
// shockwave distortion -> alpha-tested splats with outlines over the background -> additive glow -> bloom
// -> exposure, flash, grading, vignette and veil -> UI -> the nearest color of the palette (ordered
// dithering between the two nearest as much as params.w says)
Texture2D solid_tex : register(t0, space2);
Texture2D bg_tex : register(t1, space2);
Texture2D glow_tex : register(t2, space2);
Texture2D blur1_tex : register(t3, space2);
Texture2D blur2_tex : register(t4, space2);
Texture2D blur3_tex : register(t5, space2);
Texture2D ui_tex : register(t6, space2);
Texture2D palette_tex : register(t7, space2);
SamplerState solid_sampler : register(s0, space2);
SamplerState bg_sampler : register(s1, space2);
SamplerState glow_sampler : register(s2, space2);
SamplerState blur1_sampler : register(s3, space2);
SamplerState blur2_sampler : register(s4, space2);
SamplerState blur3_sampler : register(s5, space2);
SamplerState ui_sampler : register(s6, space2);
SamplerState palette_sampler : register(s7, space2);

cbuffer Uniforms : register(b0, space3) {
  float4 params; // x: time, y: bloom strength, z: chromatic aberration in pixels, w: dither strength
  float4 flash;  // rgb: flash color, a: flash amount
  float4 grade;  // x: shadow tint 0..1, y: vignette, z: saturation, w: outline strength
  float4 tint;   // rgb: the color the shadow tint adds to dark tones, w: smoothing radius in pixels (0: off)
  float4 wave0;  // xy: center in pixels from the top left, z: radius, w: strength in pixels
  float4 wave1;
  float4 wave2;
  float4 wave3;
  float4 veil;   // x: how far the veil has closed in from the edges 0..1, y: its softness, z: exposure,
                 // w: the number of palette colors
  float4 veil_color; // rgb: the veil's color, w: how different a neighbor's color may be to be smoothed with
};

struct Input {
  float4 tex_color : COLOR0;
  float2 tex_coord : TEXCOORD0;
};

struct Output {
  float4 frag_color : SV_Target;
};

// The palette is a row of PostProcess::PALETTE_SLOTS pixels, of which the first veil.w are used
static const float PALETTE_SLOTS = 64.0;

float3 palette_color(int i) {
  return palette_tex.SampleLevel(palette_sampler, float2((float(i) + 0.5) / PALETTE_SLOTS, 0.5), 0).rgb;
}

static const float BAYER[16] = {
  0.0, 8.0, 2.0, 10.0,
  12.0, 4.0, 14.0, 6.0,
  3.0, 11.0, 1.0, 9.0,
  15.0, 7.0, 13.0, 5.0
};

static const float3 OUTLINE = float3(40, 32, 44) / 255.0;
// Coverage at which overlapping splats count as a solid pixel
static const float SOLID_ALPHA = 0.25;

float4 texel(Texture2D tex, SamplerState samp, float2 pixel, float2 size) {
  pixel = clamp(pixel, float2(0.0, 0.0), size - 1.0);
  return tex.SampleLevel(samp, (pixel + 0.5) / size, 0);
}

// Filters by hand, so the result does not depend on the sampler's filter mode
float3 bilinear(Texture2D tex, SamplerState samp, float2 uv) {
  float2 size;
  tex.GetDimensions(size.x, size.y);
  float2 q = uv * size - 0.5;
  float2 i = floor(q);
  float2 f = q - i;
  float3 a = texel(tex, samp, i, size).rgb;
  float3 b = texel(tex, samp, i + float2(1.0, 0.0), size).rgb;
  float3 c = texel(tex, samp, i + float2(0.0, 1.0), size).rgb;
  float3 d = texel(tex, samp, i + float2(1.0, 1.0), size).rgb;
  return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float2 wave_offset(float2 p, float4 wave) {
  if (wave.w == 0.0) {
    return float2(0.0, 0.0);
  }
  float2 d = p - wave.xy;
  float dist = length(d);
  float x = (dist - wave.z) / 5.0;
  float push = -x * exp(-x * x) * 2.0;
  return d / max(dist, 0.001) * push * wave.w;
}

// Averages the solid pixels around p whose color is close to center's, so that the mottle of neighboring splats
// evens out before the palette turns it into patches, while edges between different colors stay sharp
float3 smooth_solid(float2 p, float2 size, float3 center) {
  int radius = int(tint.w);
  float3 sum = center;
  float total = 1.0;
  for (int dy = -radius; dy <= radius; dy++) {
    for (int dx = -radius; dx <= radius; dx++) {
      float4 other = texel(solid_tex, solid_sampler, p + float2(float(dx), float(dy)), size);
      if ((dx != 0 || dy != 0) && other.a > SOLID_ALPHA) {
        float3 color = other.rgb / other.a;
        float3 d = color - center;
        float weight = exp(-dot(d, d) * veil_color.w);
        sum += color * weight;
        total += weight;
      }
    }
  }
  return sum / total;
}

// Splats are alpha tested into hard pixel edges and get a dark outline against the background
float3 composite(float2 p, float2 size) {
  float4 solid = texel(solid_tex, solid_sampler, p, size);
  float3 color;
  if (solid.a > SOLID_ALPHA) {
    color = solid.rgb / solid.a;
    if (tint.w > 0.0) {
      color = smooth_solid(p, size, color);
    }
  } else {
    float neighbor = max(max(texel(solid_tex, solid_sampler, p + float2(1.0, 0.0), size).a,
                             texel(solid_tex, solid_sampler, p - float2(1.0, 0.0), size).a),
                         max(texel(solid_tex, solid_sampler, p + float2(0.0, 1.0), size).a,
                             texel(solid_tex, solid_sampler, p - float2(0.0, 1.0), size).a));
    color = texel(bg_tex, bg_sampler, p, size).rgb;
    if (neighbor > SOLID_ALPHA) {
      color = lerp(color, OUTLINE, grade.w);
    }
  }
  return color + texel(glow_tex, glow_sampler, p, size).rgb;
}

float color_distance(float3 a, float3 b) {
  float3 d = a - b;
  float red_mean = (a.r + b.r) * 0.5;
  return (2.0 + red_mean) * d.r * d.r + 4.0 * d.g * d.g + (3.0 - red_mean) * d.b * d.b;
}

// Picks the nearest palette color or the second nearest, in the proportion that mixes them into the input
float3 dither_to_palette(float3 color, float threshold, float strength) {
  float best = 1e9;
  float second = 1e9;
  float3 best_color = palette_color(0);
  float3 second_color = best_color;
  int count = int(veil.w);
  for (int i = 0; i < count; i++) {
    float3 candidate = palette_color(i);
    float d = color_distance(color, candidate);
    if (d < best) {
      second = best;
      second_color = best_color;
      best = d;
      best_color = candidate;
    } else if (d < second) {
      second = d;
      second_color = candidate;
    }
  }
  float3 span = second_color - best_color;
  float t = saturate(dot(color - best_color, span) / max(dot(span, span), 0.00001));
  return (t * strength > threshold) ? second_color : best_color;
}

Output main(Input input) {
  Output output;
  float2 size;
  solid_tex.GetDimensions(size.x, size.y);
  float2 cell = floor(input.tex_coord * size);
  float2 center = cell + 0.5;

  float2 offset = wave_offset(center, wave0) + wave_offset(center, wave1) +
                  wave_offset(center, wave2) + wave_offset(center, wave3);
  float2 p = floor(center + offset);

  float2 from_center = center / size - 0.5;
  float aberration = params.z * (0.35 + 1.3 * length(from_center));
  float3 color;
  if (aberration >= 0.5) {
    float2 shift = round(normalize(from_center + float2(0.0001, 0.0)) * aberration);
    color = float3(composite(p + shift, size).r, composite(p, size).g, composite(p - shift, size).b);
  } else {
    color = composite(p, size);
  }

  float2 uv = (p + 0.5) / size;
  float3 bloom = bilinear(blur1_tex, blur1_sampler, uv) * 0.6 +
                 bilinear(blur2_tex, blur2_sampler, uv) * 0.5 +
                 bilinear(blur3_tex, blur3_sampler, uv) * 0.25;
  color += bloom * params.y;
  color *= veil.z;

  color = lerp(color, flash.rgb, flash.a);

  float luma = dot(color, float3(0.299, 0.587, 0.114));
  color = lerp(float3(luma, luma, luma), color, grade.z);
  color += tint.rgb * grade.x * (1.0 - saturate(luma * 2.0));
  color *= 1.0 - grade.y * dot(from_center, from_center) * 2.2;

  // The veil closes in from the edges: at 0 it stays outside the screen, at 1 it covers all of it
  float edge = length(from_center * float2(2.0, 2.0 * size.y / size.x)) * 1.2;
  float reach = 1.45 - veil.x * (1.45 + veil.y);
  color = lerp(color, veil_color.rgb, smoothstep(reach, reach + veil.y, edge));

  // The HUD is stored premultiplied, and blends with its alpha so that it can fade
  float4 ui = texel(ui_tex, ui_sampler, cell, size);
  color = color * (1.0 - ui.a) + ui.rgb;

  int index = (int(cell.y) % 4) * 4 + (int(cell.x) % 4);
  float threshold = (BAYER[index] + 0.5) / 16.0;
  output.frag_color = float4(dither_to_palette(saturate(color), threshold, params.w), 1.0);
  return output;
}
