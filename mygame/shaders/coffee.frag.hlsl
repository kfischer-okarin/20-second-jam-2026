// The coffee's surface in the cup. t0 is CoffeeSurface's grid (red: foam, green: milk mixed in, blue: ripples
// around 0.5); this runs for every pixel of the sprite that draws it as an ellipse into the solid layer.
// Sampling the grid between cells and thresholding the foam keeps its edges crisp although the grid is coarse.
Texture2D field_tex : register(t0, space2);
SamplerState field_sampler : register(s0, space2);

cbuffer Uniforms : register(b0, space3) {
  float4 params;  // x: time, y: milk mixed into all of the coffee 0..1, z: radius of the disc in uv, w: glow
  float4 clip;    // the cup's opening in uv (center xy, radii zw): the rim hides what lies outside it
  float4 sun;     // rgb: sun color, a: the sun's elevation in radians
  float4 ambient; // rgb: ambient color, a: the elevation the eye looks down at the surface from
  float4 look;    // x: 1 for flat colors and an ink line along the cup (the ink look)
};

static const float3 INK = float3(24.0, 20.0, 30.0) / 255.0;
static const float3 FLAT_CREMA = float3(146.0, 92.0, 58.0) / 255.0;
static const float3 FLAT_MIXED = float3(192.0, 136.0, 90.0) / 255.0;
static const float3 FLAT_FOAM = float3(250.0, 244.0, 232.0) / 255.0;

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

// Filters by hand, so the result does not depend on the sampler's filter mode
float4 field(float2 uv, float2 size) {
  float2 q = uv * size - 0.5;
  float2 i = floor(q);
  float2 f = q - i;
  float4 a = texel(i, size);
  float4 b = texel(i + float2(1.0, 0.0), size);
  float4 c = texel(i + float2(0.0, 1.0), size);
  float4 d = texel(i + float2(1.0, 1.0), size);
  return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float hash(float2 p) {
  return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float noise(float2 p) {
  float2 i = floor(p);
  float2 f = p - i;
  f = f * f * (3.0 - 2.0 * f);
  return lerp(lerp(hash(i), hash(i + float2(1.0, 0.0)), f.x),
              lerp(hash(i + float2(0.0, 1.0)), hash(i + float2(1.0, 1.0)), f.x), f.y);
}

Output main(Input input) {
  Output output;
  float2 size;
  field_tex.GetDimensions(size.x, size.y);
  float2 uv = input.tex_coord;
  float r = length(uv - 0.5) / params.z;
  float2 q = (uv - clip.xy) / clip.zw;
  if (r > 1.0 || dot(q, q) > 1.0) {
    output.frag_color = float4(0.0, 0.0, 0.0, 0.0);
    return output;
  }

  float step_uv = 0.75 / size.x;
  float4 f = field(uv, size);

  if (look.x > 0.5) {
    float3 flat = saturate(f.g * 0.6 + params.y) > 0.45 ? FLAT_MIXED : FLAT_CREMA;
    flat = f.r > 0.48 ? FLAT_FOAM : flat;
    flat += FLAT_FOAM * step(0.48, f.r) * params.w;
    output.frag_color = float4(r > 1.0 - fwidth(r) * 1.2 ? INK : flat, 1.0);
    return output;
  }
  float4 left = field(uv - float2(step_uv, 0.0), size);
  float4 right = field(uv + float2(step_uv, 0.0), size);
  float4 far = field(uv - float2(0.0, step_uv), size);
  float4 near = field(uv + float2(0.0, step_uv), size);

  // Crema, mottled, and lighter where milk dove under it
  float2 p = uv * size;
  float mottle = noise(p * 0.8 + 3.1) * 0.65 + noise(p * 2.1 + 7.7) * 0.35;
  float3 crema = lerp(float3(0.2, 0.1, 0.06), float3(0.42, 0.24, 0.13), mottle);
  float mixed = saturate(f.g * 0.6 + params.y);
  float3 base = lerp(crema, float3(0.5, 0.3, 0.17), mixed);

  // Foam with a crisp edge, and a thin darker line of crema pressed against it
  float foam = smoothstep(0.38, 0.58, f.r);
  float pressed = smoothstep(0.06, 0.32, f.r) * (1.0 - foam);
  base *= 1.0 - pressed * 0.4;
  float3 foam_color = float3(0.99, 0.96, 0.91) * (0.94 + 0.06 * noise(p * 2.7));
  float3 albedo = lerp(base, foam_color, foam);

  // Foam stands a little above the crema, ripples tilt the surface
  float2 slope = float2(right.b - left.b, near.b - far.b) * 0.8 + float2(right.r - left.r, near.r - far.r) * 0.35;
  float3 normal = normalize(float3(-slope.x, 1.0, -slope.y));
  float3 to_sun = float3(0.0, sin(sun.a), -cos(sun.a));
  float3 to_eye = float3(0.0, sin(ambient.a), cos(ambient.a));
  // Liquid takes little diffuse light; foam is matte and takes more
  float diffuse = saturate(dot(normal, to_sun) * 1.4 + 0.1);
  float3 light = ambient.rgb * 0.75 + sun.rgb * diffuse * lerp(0.4, 0.6, foam);
  float3 color = albedo * light;

  // The low sun glints on ripples (the coffee is a dark mirror, foam reflects less)
  float3 halfway = normalize(to_sun + to_eye);
  float glint = pow(saturate(dot(normal, halfway)), 2500.0);
  color += sun.rgb * glint * (1.2 - foam);

  // The meniscus along the wall catches light
  color += sun.rgb * smoothstep(0.86, 1.0, r) * 0.18 * (1.0 - foam);

  // In the ending the foam glows in the light
  color += foam_color * foam * params.w;

  output.frag_color = float4(color, 1.0);
  return output;
}
