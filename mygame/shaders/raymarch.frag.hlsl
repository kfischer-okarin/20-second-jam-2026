// Raymarches the set pieces of the render lab per pixel: the cup with its coffee on the saucer, the pitcher and the
// moka pot on a tabletop, seen through an orthographic camera that looks down at view.y radians. The shapes are
// the same SDFs as the baked models (Models, Cup, Pitcher). t0 is CoffeeSurface's grid for the coffee's art.
//
// mode.x selects what to output: 0 the shaded color (alpha 1 where something is hit), 1 geometry for the ink
// pass (r: depth, gb: normal, a: material).
// mode.y selects the shading: 0 smooth (soft shadows, occlusion, highlights, reflections), 1 toon (bands, a rim
// band, a hard highlight), 2 flat (one shadow tone), 3 clay (wrap light, strong occlusion, no shine), 4 ramps
// (ink-studio's light, for a palette of ramps to snap)
Texture2D field_tex : register(t0, space2);
SamplerState field_sampler : register(s0, space2);

cbuffer Uniforms : register(b0, space3) {
  float4 view;    // x: pixels per centimetre, y: elevation, zw: screen size in pixels
  float4 center;  // xyz: the world point at the middle of the screen
  float4 mode;    // x: output, y: shading
  float4 light;   // xyz: direction towards the light (world space), w: sky fill
  float4 coffee;  // x: level above the cup's foot, y: radius of the surface, z: the disc's radius in the grid (uv)
  float4 pitcher; // xyz: tip of the spout, w: yaw
  float4 moka;    // xyz: base, w: yaw
};

struct Input {
  float4 tex_color : COLOR0;
  float2 tex_coord : TEXCOORD0;
};

struct Output {
  float4 frag_color : SV_Target;
};

static const float CUP_BASE = 0.56;
static const float RIM = 5.8;
static const float3 PITCHER_BOTTOM = float3(2.95, -6.3, 0.0);

static const int TABLE = 0;
static const int GLAZE = 1;
static const int PORCELAIN = 2;
static const int COFFEE = 3;
static const int STEEL = 4;
static const int ALUMINIUM = 5;
static const int BAKELITE = 6;
static const int MILK = 7;

// --- Primitives (see Sdf) ------------------------------------------------------------------------------------

float sd_ellipsoid(float3 p, float3 r) {
  float k0 = length(p / r);
  float k1 = length(p / (r * r));
  return k0 * (k0 - 1.0) / max(k1, 1e-6);
}

float sd_torus(float3 p, float ring, float tube) {
  return length(float2(length(p.xz) - ring, p.y)) - tube;
}

float sd_torus_xy(float3 p, float ring, float tube) {
  return length(float2(length(p.xy) - ring, p.z)) - tube;
}

float sd_cylinder(float3 p, float radius, float half_height, float rounding) {
  float2 d = float2(length(p.xz) - radius + rounding, abs(p.y) - half_height + rounding);
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rounding;
}

float sd_capped_cone(float3 p, float h, float r1, float r2) {
  float2 q = float2(length(p.xz), p.y);
  float2 k1 = float2(r2, h);
  float2 k2 = float2(r2 - r1, 2.0 * h);
  float2 ca = float2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
  float2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
  float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
  return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

float sd_cone_between(float3 p, float3 a, float3 b, float ra, float rb) {
  float rba = rb - ra;
  float baba = dot(b - a, b - a);
  float papa = dot(p - a, p - a);
  float paba = dot(p - a, b - a) / baba;
  float x = sqrt(max(papa - paba * paba * baba, 0.0));
  float cax = max(0.0, x - ((paba < 0.5) ? ra : rb));
  float cay = abs(paba - 0.5) - 0.5;
  float k = rba * rba + baba;
  float f = clamp((rba * (x - ra) + paba * baba) / k, 0.0, 1.0);
  float cbx = x - ra - f * rba;
  float cby = paba - f;
  float s = (cbx < 0.0 && cay < 0.0) ? -1.0 : 1.0;
  return s * sqrt(min(cax * cax + cay * cay * baba, cbx * cbx + cby * cby * baba));
}

float sd_capsule(float3 p, float3 a, float3 b, float r) {
  float3 pa = p - a;
  float3 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

float sd_ngon_frustum(float3 p, float sides, float half_height, float bottom, float top) {
  float sector = 6.2831853 / sides;
  float angle = atan2(p.z, p.x);
  angle = fmod(angle + sector * 0.5 + 62.831853, sector) - sector * 0.5;
  float across = length(p.xz) * cos(angle);
  float t = saturate((p.y / half_height + 1.0) * 0.5);
  float apothem = lerp(bottom, top, t);
  float slope = (top - bottom) / (2.0 * half_height);
  return max((across - apothem) / sqrt(1.0 + slope * slope), abs(p.y) - half_height);
}

float smin(float a, float b, float k) {
  float h = saturate(0.5 + 0.5 * (b - a) / k);
  return lerp(b, a, h) - k * h * (1.0 - h);
}

float ssub(float a, float b, float k) {
  float h = saturate(0.5 - 0.5 * (a + b) / k);
  return lerp(a, -b, h) + k * h * (1.0 - h);
}

float3 rotate_y(float3 p, float angle) {
  float c = cos(angle);
  float s = sin(angle);
  return float3(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
}

// --- The set pieces ------------------------------------------------------------------------------------------

float cup_middle(float3 p) {
  return sd_ellipsoid(p - float3(0.0, RIM, 0.0), float3(5.0, 4.6, 5.0));
}

float sd_cup(float3 p) {
  float d = sd_cylinder(p - float3(0.0, 0.75, 0.0), 2.35, 0.75, 0.25);
  d = smin(d, max(abs(cup_middle(p)) - 0.22, p.y - RIM), 0.6);
  d = smin(d, sd_torus(p - float3(0.0, RIM, 0.0), 5.0, 0.22), 0.1);
  return smin(d, max(sd_torus_xy(p - float3(-5.55, 3.7, 0.0), 1.3, 0.36), p.x + 4.5), 0.35);
}

// The coffee fills the bowl up to its level
float sd_coffee(float3 p) {
  return max(p.y - coffee.x, cup_middle(p) + 0.2);
}

float sd_saucer(float3 p) {
  float d = sd_cylinder(p - float3(0.0, 0.32, 0.0), 7.4, 0.32, 0.28);
  d = smin(d, sd_torus(p - float3(0.0, 0.62, 0.0), 6.95, 0.26), 0.5);
  return ssub(d, sd_ellipsoid(p - float3(0.0, 1.15, 0.0), float3(5.6, 0.62, 5.6)), 0.8);
}

float sd_pitcher_body(float3 p) {
  float cy = p.y - PITCHER_BOTTOM.y - 3.0;
  float d = max(abs(sd_capped_cone(float3(p.x - PITCHER_BOTTOM.x, cy, p.z), 3.0, 2.5, 2.15)) - 0.12, cy - 3.0);
  float beak = abs(sd_cone_between(p, float3(1.75, -0.8, 0.0), float3(0.1, 0.0, 0.0), 0.95, 0.16)) - 0.1;
  beak = max(beak, (p.x - 1.75) * 0.43 + (p.y + 0.8) * 0.9 - 0.05);
  d = smin(d, beak, 0.35);
  float handle = sd_torus_xy(p - float3(PITCHER_BOTTOM.x + 3.3, PITCHER_BOTTOM.y + 3.4, 0.0), 1.45, 0.3);
  return smin(d, max(handle, PITCHER_BOTTOM.x + 2.3 - p.x), 0.3);
}

float sd_pitcher_milk(float3 p) {
  return sd_cylinder(p - float3(PITCHER_BOTTOM.x, PITCHER_BOTTOM.y + 4.3, 0.0), 2.2, 0.08, 0.0);
}

float sd_moka_metal(float3 p) {
  float d = sd_ngon_frustum(p - float3(0.0, 2.1, 0.0), 8.0, 2.1, 2.55, 2.0);
  d = smin(d, sd_cylinder(p - float3(0.0, 4.3, 0.0), 1.95, 0.25, 0.1), 0.15);
  d = smin(d, sd_ngon_frustum(p - float3(0.0, 6.45, 0.0), 8.0, 2.0, 2.0, 2.45), 0.15);
  d = smin(d, sd_ngon_frustum(p - float3(0.0, 8.6, 0.0), 8.0, 0.18, 2.5, 2.2), 0.1);
  return smin(d, sd_cone_between(p, float3(-1.6, 7.6, 0.0), float3(-3.4, 8.7, 0.0), 0.75, 0.3), 0.3);
}

float sd_moka_bakelite(float3 p) {
  float d = sd_cylinder(p - float3(0.0, 9.05, 0.0), 0.45, 0.3, 0.15);
  d = min(d, sd_capsule(p, float3(2.3, 8.0, 0.0), float3(4.3, 7.5, 0.0), 0.4));
  return smin(d, sd_capsule(p, float3(4.3, 7.5, 0.0), float3(3.8, 5.0, 0.0), 0.45), 0.3);
}

// Distance to the scene and the material of the nearest surface
float2 scene(float3 p) {
  float2 best = float2(p.y, TABLE);
  float3 c = p - float3(0.0, CUP_BASE, 0.0);
  float d = sd_saucer(p);
  if (d < best.x) best = float2(d, GLAZE);
  d = sd_cup(c);
  if (d < best.x) best = float2(d, GLAZE);
  d = sd_coffee(c);
  if (d < best.x) best = float2(d, COFFEE);
  float3 q = rotate_y(p - pitcher.xyz, -pitcher.w);
  d = sd_pitcher_body(q);
  if (d < best.x) best = float2(d, STEEL);
  d = sd_pitcher_milk(q);
  if (d < best.x) best = float2(d, MILK);
  float3 m = rotate_y(p - moka.xyz, -moka.w);
  d = sd_moka_metal(m);
  if (d < best.x) best = float2(d, ALUMINIUM);
  d = sd_moka_bakelite(m);
  if (d < best.x) best = float2(d, BAKELITE);
  return best;
}

// The glaze is white inside the cup, on its rim and on top of the saucer
int refine_material(float3 p, int material) {
  if (material != GLAZE) return material;
  float3 c = p - float3(0.0, CUP_BASE, 0.0);
  if (cup_middle(c) < 0.0 || sd_torus(c - float3(0.0, RIM, 0.0), 5.0, 0.34) < 0.0) return PORCELAIN;
  if (p.y > 0.4 && p.y < 1.4 && length(p.xz) < 6.6 && sd_saucer(p) < 0.05) return PORCELAIN;
  return material;
}

float3 normal_at(float3 p) {
  float2 e = float2(0.01, -0.01);
  return normalize(e.xyy * scene(p + e.xyy).x + e.yyx * scene(p + e.yyx).x +
                   e.yxy * scene(p + e.yxy).x + e.xxx * scene(p + e.xxx).x);
}

float soft_shadow(float3 p, float3 l) {
  float result = 1.0;
  float t = 0.05;
  for (int i = 0; i < 40; i++) {
    float d = scene(p + l * t).x;
    result = min(result, 10.0 * d / t);
    t += clamp(d, 0.05, 0.8);
    if (result < 0.01 || t > 30.0) break;
  }
  return saturate(result);
}

float occlusion(float3 p, float3 n) {
  float occluded = 0.0;
  float weight = 1.0;
  for (int i = 1; i <= 5; i++) {
    float h = 0.12 * float(i);
    occluded += (h - scene(p + n * h).x) * weight;
    weight *= 0.7;
  }
  return saturate(1.0 - occluded * 1.8);
}

// --- Shading -------------------------------------------------------------------------------------------------

float4 coffee_field(float3 p) {
  float2 uv = float2(p.x, p.z) / coffee.y * coffee.z + 0.5;
  float2 size;
  field_tex.GetDimensions(size.x, size.y);
  float2 q = uv * size - 0.5;
  float2 i = floor(q);
  float2 f = q - i;
  float4 a = field_tex.SampleLevel(field_sampler, (i + 0.5) / size, 0);
  float4 b = field_tex.SampleLevel(field_sampler, (i + float2(1.5, 0.5)) / size, 0);
  float4 c = field_tex.SampleLevel(field_sampler, (i + float2(0.5, 1.5)) / size, 0);
  float4 d = field_tex.SampleLevel(field_sampler, (i + 1.5) / size, 0);
  return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float3 albedo(int material, float3 p) {
  if (material == TABLE) return float3(0.78, 0.66, 0.52);
  if (material == GLAZE) return float3(0.31, 0.38, 0.55);
  if (material == PORCELAIN) return float3(0.95, 0.93, 0.88);
  if (material == STEEL) return float3(0.72, 0.75, 0.8);
  if (material == ALUMINIUM) return float3(0.68, 0.7, 0.74);
  if (material == BAKELITE) return float3(0.16, 0.13, 0.15);
  if (material == MILK) return float3(0.98, 0.96, 0.92);
  float4 field = coffee_field(p - float3(0.0, CUP_BASE, 0.0));
  float foam = smoothstep(0.38, 0.58, field.r);
  float3 crema = lerp(float3(0.28, 0.15, 0.09), float3(0.5, 0.3, 0.17), saturate(field.g * 0.6 + 0.15));
  return lerp(crema, float3(0.99, 0.96, 0.91), foam);
}

float shininess(int material) {
  if (material == STEEL) return 0.85;
  if (material == ALUMINIUM) return 0.6;
  if (material == GLAZE || material == PORCELAIN || material == COFFEE) return 0.25;
  if (material == BAKELITE) return 0.2;
  return 0.0;
}

float3 sky(float3 r) {
  return lerp(float3(0.62, 0.56, 0.5), float3(1.0, 0.98, 0.95), saturate(r.y * 0.8 + 0.5));
}

float3 shade(float3 p, float3 n, float3 v, int material) {
  float3 base = albedo(material, p);
  float3 l = normalize(light.xyz);
  float ndl = dot(n, l);
  float shadow = soft_shadow(p + n * 0.03, l);
  float ao = occlusion(p, n);
  float3 key = float3(1.0, 0.94, 0.84);
  float3 fill = float3(0.52, 0.56, 0.66) * light.w;
  float shine = shininess(material);
  float3 h = normalize(l + v);
  int style = int(mode.y);

  if (style == 1) {
    float lit = ndl * shadow;
    float band = lit > 0.45 ? 1.0 : (lit > 0.05 ? 0.72 : 0.48);
    float rim = (1.0 - saturate(dot(n, v))) > 0.62 && lit > 0.05 ? 0.12 : 0.0;
    float3 color = base * (band + rim) * (ao > 0.55 ? 1.0 : 0.85);
    if (shine > 0.3 && pow(saturate(dot(n, h)), 60.0) * shadow > 0.5) color = float3(1.0, 1.0, 1.0);
    return color;
  }
  if (style == 2) {
    float lit = ndl * shadow;
    float3 color = base * (lit > 0.12 ? 1.0 : 0.66);
    if (shine > 0.5 && pow(saturate(dot(n, h)), 40.0) * shadow > 0.6) color = float3(1.0, 1.0, 1.0);
    return color;
  }
  if (style == 4) {
    // ink-studio's light: occlusion times ambient and sky, plus the shadowed sun, for the palette's ramps to snap
    float v = ao * (0.14 + 0.3 * (0.5 + 0.5 * n.y)) + 0.72 * saturate(ndl) * shadow;
    if (shine > 0.3 && dot(n, h) > 0.96 && shadow > 0.5) return float3(1.0, 1.0, 1.0);
    return base * (0.25 + 0.85 * v);
  }
  if (style == 3) {
    float wrap = saturate((ndl + 0.6) / 1.6) * lerp(0.55, 1.0, shadow);
    float3 clay = lerp(base, dot(base, float3(0.3, 0.59, 0.11)).xxx, 0.25);
    return clay * (0.35 + 0.75 * wrap) * lerp(0.45, 1.0, ao);
  }

  float diffuse = saturate(ndl) * shadow;
  float3 color = base * (key * diffuse + fill * ao * (0.6 + 0.4 * n.y));
  float3 r = reflect(-v, n);
  float fresnel = 0.04 + 0.96 * pow(1.0 - saturate(dot(n, v)), 5.0);
  color = lerp(color, sky(r) * lerp(0.5, 1.0, ao), shine * (0.35 + 0.65 * fresnel) * (shine > 0.5 ? 1.0 : 0.35));
  color += key * pow(saturate(dot(n, h)), 20.0 + 180.0 * shine) * shine * shadow * 1.4;
  return color;
}

Output main(Input input) {
  Output output;
  float2 pixel = input.tex_coord * view.zw;
  float2 offset = float2(pixel.x - view.z * 0.5, view.w * 0.5 - pixel.y) / view.x;
  float e = view.y;
  float3 forward = float3(0.0, -sin(e), -cos(e));
  float3 up = float3(0.0, cos(e), -sin(e));
  float3 origin = center.xyz + float3(1.0, 0.0, 0.0) * offset.x + up * offset.y - forward * 40.0;

  float t = 0.0;
  float2 hit = float2(1e9, -1.0);
  for (int i = 0; i < 160; i++) {
    float2 d = scene(origin + forward * t);
    if (d.x < 0.002) {
      hit = float2(t, d.y);
      break;
    }
    t += d.x * 0.9;
    if (t > 90.0) break;
  }
  if (hit.y < 0.0) {
    output.frag_color = float4(0.0, 0.0, 0.0, 0.0);
    return output;
  }

  float3 p = origin + forward * hit.x;
  float3 n = normal_at(p);
  int material = refine_material(p, int(hit.y));
  if (mode.x > 0.5) {
    output.frag_color = float4(hit.x / 90.0, n.x * 0.5 + 0.5, n.z * 0.5 + 0.5, (float(material) + 0.5) / 8.0);
    return output;
  }
  output.frag_color = float4(shade(p, n, -forward, material), 1.0);
  return output;
}
