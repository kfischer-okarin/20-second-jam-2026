// Keeps only what is bright enough to bloom, from the solid layer (this target's own content, drawn at half
// resolution) plus the glow layer. Additive splats leave the glow layer's alpha at 0, so drawing it into this
// target would add nothing; it is read as a texture instead.
Texture2D scene : register(t0, space2);
Texture2D glow : register(t1, space2);
SamplerState scene_sampler : register(s0, space2);
SamplerState glow_sampler : register(s1, space2);

cbuffer Uniforms : register(b0, space3) {
  float threshold;
  float gain;
  float solid; // 1 lets the solid layer bloom too, 0 only the glow layer
};

struct Input {
  float4 tex_color : COLOR0;
  float2 tex_coord : TEXCOORD0;
};

struct Output {
  float4 frag_color : SV_Target;
};

// Each pixel of this target covers 2x2 glow pixels
float3 glow_average(float2 uv) {
  float2 size;
  glow.GetDimensions(size.x, size.y);
  float2 half_texel = 0.5 / size;
  return (glow.SampleLevel(glow_sampler, uv + float2(-half_texel.x, -half_texel.y), 0).rgb +
          glow.SampleLevel(glow_sampler, uv + float2(half_texel.x, -half_texel.y), 0).rgb +
          glow.SampleLevel(glow_sampler, uv + float2(-half_texel.x, half_texel.y), 0).rgb +
          glow.SampleLevel(glow_sampler, uv + float2(half_texel.x, half_texel.y), 0).rgb) * 0.25;
}

Output main(Input input) {
  Output output;
  float3 color = scene.SampleLevel(scene_sampler, input.tex_coord, 0).rgb * solid + glow_average(input.tex_coord);
  float brightest = max(color.r, max(color.g, color.b));
  float amount = saturate((brightest - threshold) / max(1.0 - threshold, 0.001));
  output.frag_color = float4(color * amount * amount * gain, 1.0);
  return output;
}
