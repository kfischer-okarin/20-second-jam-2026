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

Output main(Input input) {
  Output output;
  float coverage = coverage_tex.SampleLevel(coverage_sampler, input.tex_coord, 0).a;
  float a = smoothstep(0.2, 0.5, coverage) * shadow.a;
  output.frag_color = float4(shadow.rgb * a, a);
  return output;
}
