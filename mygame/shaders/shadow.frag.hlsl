// Turns the coverage of overlapping shadow splats (t0's alpha) into an even shadow with a soft edge. Drawn with
// LayerSprite::MULTIPLY_BLENDMODE, (tint * a, a) multiplies what lies below by lerp(1, tint, a).
Texture2D coverage_tex : register(t0, space2);
SamplerState coverage_sampler : register(s0, space2);

cbuffer Uniforms : register(b0, space3) {
  float4 shadow; // rgb: what the shadow multiplies the lit color by, a: its strength
};

struct Input {
  float4 tex_color : COLOR0;
  float2 tex_coord : TEXCOORD0;
};

struct Output {
  float4 frag_color : SV_Target;
};

float coverage_at(float2 uv) {
  return coverage_tex.SampleLevel(coverage_sampler, uv, 0).a;
}

// Averages the coverage with its neighbors first, so that a shadow cast by sparse splats comes out whole
Output main(Input input) {
  Output output;
  float2 size;
  coverage_tex.GetDimensions(size.x, size.y);
  float2 step_uv = 1.5 / size;
  float2 uv = input.tex_coord;
  float coverage = (coverage_at(uv) * 2.0 + coverage_at(uv + float2(step_uv.x, 0.0)) +
                    coverage_at(uv - float2(step_uv.x, 0.0)) + coverage_at(uv + float2(0.0, step_uv.y)) +
                    coverage_at(uv - float2(0.0, step_uv.y))) / 6.0;
  float a = smoothstep(0.15, 0.4, coverage) * shadow.a;
  output.frag_color = float4(shadow.rgb * a, a);
  return output;
}
