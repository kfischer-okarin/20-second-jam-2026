// Resolves splats drawn at twice the resolution into pixel art (after ink-studio's PixelLook): every pixel takes
// the palette color that most of its 2 by 2 samples are nearest to, so silhouettes come out clean, and where a
// neighboring pixel is clearly nearer, the pixel becomes a contour of that nearer shape: ink, or a darker shade of
// the shape's own color.
// t0: the splats' colors (premultiplied), t1: their depth (0 near, 1 far), t2: the palette as a row of pixels
Texture2D color_tex : register(t0, space2);
Texture2D depth_tex : register(t1, space2);
Texture2D palette_tex : register(t2, space2);
SamplerState color_sampler : register(s0, space2);
SamplerState depth_sampler : register(s1, space2);
SamplerState palette_sampler : register(s2, space2);

cbuffer Uniforms : register(b0, space3) {
  float4 params; // x: palette colors, y: depth step that makes a contour, z: contour 0 none, 1 ink, 2 shade
  float4 ink;    // rgb: the ink's color
};

struct Input {
  float4 tex_color : COLOR0;
  float2 tex_coord : TEXCOORD0;
};

struct Output {
  float4 frag_color : SV_Target;
};

static const float PALETTE_SLOTS = 64.0;

float3 palette_color(int i) {
  return palette_tex.SampleLevel(palette_sampler, float2((float(i) + 0.5) / PALETTE_SLOTS, 0.5), 0).rgb;
}

int nearest(float3 c) {
  int best = 0;
  float best_distance = 1e9;
  int count = int(params.x);
  for (int i = 0; i < count; i++) {
    float3 d = c - palette_color(i);
    float distance = dot(d * d, float3(0.30, 0.55, 0.15));
    if (distance < best_distance) {
      best_distance = distance;
      best = i;
    }
  }
  return best;
}

float4 sample_color(int2 q, int2 size) {
  q = clamp(q, int2(0, 0), size - 1);
  float4 c = color_tex.SampleLevel(color_sampler, (float2(q) + 0.5) / float2(size), 0);
  return c.a > 0.01 ? float4(c.rgb / c.a, c.a) : float4(0.0, 0.0, 0.0, 0.0);
}

float sample_depth(int2 q, int2 size) {
  q = clamp(q, int2(0, 0), size - 1);
  float4 d = depth_tex.SampleLevel(depth_sampler, (float2(q) + 0.5) / float2(size), 0);
  return d.a > 0.5 ? d.r / d.a : 1.0;
}

// The nearest depth among a pixel's samples
float block_depth(int2 p, int2 size) {
  int2 q = p * 2;
  return min(min(sample_depth(q, size), sample_depth(q + int2(1, 0), size)),
             min(sample_depth(q + int2(0, 1), size), sample_depth(q + int2(1, 1), size)));
}

// The palette color most of a pixel's covered samples are nearest to (-1 when none is covered)
int block_label(int2 p, int2 size) {
  int labels[4];
  bool covered[4];
  for (int i = 0; i < 4; i++) {
    float4 c = sample_color(p * 2 + int2(i & 1, i >> 1), size);
    covered[i] = c.a > 0.5;
    labels[i] = covered[i] ? nearest(c.rgb) : -1;
  }
  int best = -1;
  int score = 0;
  for (int i = 0; i < 4; i++) {
    if (!covered[i]) continue;
    int n = 0;
    for (int j = 0; j < 4; j++) {
      if (labels[j] == labels[i]) n++;
    }
    if (n > score) {
      score = n;
      best = labels[i];
    }
  }
  return best;
}

// A darker shade of a color that never gets too dark to tell its hue
float3 shade_of(float3 body) {
  float3 tone = body * 0.6;
  float luma = dot(tone, float3(0.30, 0.55, 0.15));
  return min(float3(1.0, 1.0, 1.0), tone * max(1.0, 0.12 / max(luma, 0.001)));
}

Output main(Input input) {
  Output output;
  float2 full;
  color_tex.GetDimensions(full.x, full.y);
  int2 size = int2(full);
  int2 p = int2(floor(input.tex_coord * full * 0.5));
  int label = block_label(p, size);
  if (label < 0) {
    output.frag_color = float4(0.0, 0.0, 0.0, 0.0);
    return output;
  }
  float3 color = palette_color(label);
  if (params.z > 0.5) {
    // A contour where the pixel lies clearly behind the average of its neighbors along a row or a column (the
    // depth's second derivative, which a slanted surface leaves at 0), in the color of the nearer neighbor
    float here = block_depth(p, size);
    float left = block_depth(p - int2(1, 0), size);
    float right = block_depth(p + int2(1, 0), size);
    float down = block_depth(p - int2(0, 1), size);
    float up = block_depth(p + int2(0, 1), size);
    float across = 2.0 * here - left - right;
    float along = 2.0 * here - down - up;
    if (max(across, along) > params.y) {
      int2 nearest_side = across > along ? (left < right ? int2(-1, 0) : int2(1, 0))
                                         : (down < up ? int2(0, -1) : int2(0, 1));
      int nearer = block_label(p + nearest_side, size);
      color = params.z > 1.5 && nearer >= 0 ? shade_of(palette_color(nearer)) : ink.rgb;
    }
  }
  output.frag_color = float4(color, 1.0);
  return output;
}
