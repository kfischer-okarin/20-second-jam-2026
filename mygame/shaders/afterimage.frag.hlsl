// The latte art burnt into the eye after the white: the foam of CoffeeSurface's grid (t0's red) as a faint
// colored ghost, drawn into the HUD. The sprite's alpha fades it.
Texture2D field_tex : register(t0, space2);
SamplerState field_sampler : register(s0, space2);

cbuffer Uniforms : register(b0, space3) {
  float4 params; // x: radius of the disc in uv
};

struct Input {
  float4 tex_color : COLOR0;
  float2 tex_coord : TEXCOORD0;
};

struct Output {
  float4 frag_color : SV_Target;
};

float4 texel(float2 cell, float2 size) {
  cell = clamp(cell, float2(0.0, 0.0), size - 1.0);
  return field_tex.SampleLevel(field_sampler, (cell + 0.5) / size, 0);
}

float4 field(float2 uv, float2 size) {
  float2 q = uv * size - 0.5;
  float2 i = floor(q);
  float2 f = q - i;
  return lerp(lerp(texel(i, size), texel(i + float2(1.0, 0.0), size), f.x),
              lerp(texel(i + float2(0.0, 1.0), size), texel(i + float2(1.0, 1.0), size), f.x), f.y);
}

Output main(Input input) {
  Output output;
  float2 size;
  field_tex.GetDimensions(size.x, size.y);
  float2 uv = input.tex_coord;
  float r = length(uv - 0.5) / params.x;
  // Wider and softer than the art itself, the way an afterimage blooms
  float foam = smoothstep(0.25, 0.7, field(uv, size).r) * (1.0 - smoothstep(0.85, 1.0, r));
  float a = foam * 0.75 * input.tex_color.a;
  output.frag_color = float4(0.62, 0.56, 0.8, a);
  return output;
}
