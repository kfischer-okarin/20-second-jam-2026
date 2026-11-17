// Ink lines from the raymarcher's geometry (t0: r depth, gb normal, a material): a pixel is inked where a
// neighbor is clearly nearer, made of something else, or turns away sharply. Only the farther side of an edge is
// inked, so lines are one pixel wide and hug the nearer shape. Drawn over the shaded image (t1), transparent
// elsewhere. The line is ink, or a darker shade of the nearer shape's own color.
Texture2D geometry_tex : register(t0, space2);
Texture2D color_tex : register(t1, space2);
SamplerState geometry_sampler : register(s0, space2);
SamplerState color_sampler : register(s1, space2);

cbuffer Uniforms : register(b0, space3) {
  float4 ink;     // rgb: line color, a: how sharply surfaces must turn to get a line (normal dot threshold)
  float4 params;  // x: depth step that makes a line (fraction of the depth range), y: lines inside objects 0/1,
                  // z: 1 for lines in a darker shade of the nearer shape
};

struct Input {
  float4 tex_color : COLOR0;
  float2 tex_coord : TEXCOORD0;
};

struct Output {
  float4 frag_color : SV_Target;
};

float4 geometry(float2 pixel, float2 size) {
  pixel = clamp(pixel, float2(0.0, 0.0), size - 1.0);
  return geometry_tex.SampleLevel(geometry_sampler, (pixel + 0.5) / size, 0);
}

float3 color_at(float2 pixel, float2 size) {
  pixel = clamp(pixel, float2(0.0, 0.0), size - 1.0);
  return color_tex.SampleLevel(color_sampler, (pixel + 0.5) / size, 0).rgb;
}

bool edge_towards(float4 here, float4 there) {
  if (there.a == 0.0) return false;
  if (here.a == 0.0) return true;
  if (there.r < here.r - params.x) return true;
  if (params.y < 0.5) return false;
  if (abs(there.a - here.a) > 0.01 && there.a > here.a) return true;
  float2 a = here.gb * 2.0 - 1.0;
  float2 b = there.gb * 2.0 - 1.0;
  float3 na = float3(a.x, sqrt(saturate(1.0 - dot(a, a))), a.y);
  float3 nb = float3(b.x, sqrt(saturate(1.0 - dot(b, b))), b.y);
  return dot(na, nb) < ink.a && there.r <= here.r;
}

// A darker shade of a color that never gets too dark to tell its hue
float3 shade_of(float3 body) {
  float3 tone = body * 0.6;
  float luma = dot(tone, float3(0.30, 0.55, 0.15));
  return min(float3(1.0, 1.0, 1.0), tone * max(1.0, 0.12 / max(luma, 0.001)));
}

Output main(Input input) {
  Output output;
  float2 size;
  geometry_tex.GetDimensions(size.x, size.y);
  float2 pixel = floor(input.tex_coord * size);
  float4 here = geometry(pixel, size);
  float2 sides[4] = { float2(1.0, 0.0), float2(-1.0, 0.0), float2(0.0, 1.0), float2(0.0, -1.0) };
  output.frag_color = float4(0.0, 0.0, 0.0, 0.0);
  for (int i = 0; i < 4; i++) {
    float2 other = pixel + sides[i];
    if (edge_towards(here, geometry(other, size))) {
      float3 line_color = params.z > 0.5 ? shade_of(color_at(other, size)) : ink.rgb;
      output.frag_color = float4(line_color, 1.0);
      break;
    }
  }
  return output;
}
