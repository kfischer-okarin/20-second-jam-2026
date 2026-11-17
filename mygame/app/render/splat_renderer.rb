# Projects the splats of a model orthographically into a batch. Each splat becomes a gaussian ellipse: a disc
# lying on the surface, squashed along its projected normal, so silhouettes stay crisp and slopes read as strokes.
# tx, ty is the screen position of the model's origin; tz only serves the distance to point lights, there is no
# depth sorting (batches draw in order, and a model's splats in the order of its parts).
#
# A splat's aux (0..1) is its gloss: that much of its light is the environment reflected around its normal (see
# Lighting), which makes metal and glaze. flash (0..1) adds white.
module SplatRenderer
  RAD_TO_DEG = 180.0 / Math::PI
  MIN_ASPECT = 0.32
  # Where the reflected sun starts to glare, as the cosine between the reflection and the sun's direction
  GLARE_START = 0.82

  extend self

  # Hot loop: comparisons stay operators instead of [a, b].max or #positive?, which allocate or send in mruby.
  # rubocop:disable-next Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockNesting, Style/MinMaxComparison, Style/NumericPredicate, Metrics/MethodLength, Metrics/AbcSize
  def render(batch, model, matrix, tx, ty, tz, scale, lighting, flash: 0.0, glow: 1.0, cull: -0.12)
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = matrix
    px = model.px
    py = model.py
    pz = model.pz
    nx = model.nx
    ny = model.ny
    nz = model.nz
    cr = model.cr
    cg = model.cg
    cb = model.cb
    em = model.em
    sizes = model.size
    gloss = model.aux
    lx, ly, lz = lighting.sun
    ux, uy, uz = lighting.up
    sun_r, sun_g, sun_b = lighting.sun_color
    gnd_r, gnd_g, gnd_b = lighting.ground
    amb_r, amb_g, amb_b = lighting.ambient
    amb_r -= gnd_r
    amb_g -= gnd_g
    amb_b -= gnd_b
    rim_r, rim_g, rim_b = lighting.rim
    flr_r, flr_g, flr_b = lighting.floor
    sky_r, sky_g, sky_b = lighting.sky
    sky_r -= flr_r
    sky_g -= flr_g
    sky_b -= flr_b
    bhd_r, bhd_g, bhd_b = lighting.behind
    glare_scale = 1.0 / (1.0 - GLARE_START)
    lights = lighting.points_near(tx, ty, model.bounding_radius * scale)
    light_count = lights.length
    keep = 1.0 - flash
    flash_add = 255.0 * flash
    out = batch.data
    stride = SplatBatch::STRIDE
    j = batch.count * stride
    i = 0
    n = model.count
    while i < n
      ax = nx[i]
      ay = ny[i]
      az = nz[i]
      wz = (m6 * ax) + (m7 * ay) + (m8 * az)
      if wz > cull
        wx = (m0 * ax) + (m1 * ay) + (m2 * az)
        wy = (m3 * ax) + (m4 * ay) + (m5 * az)
        ox = px[i]
        oy = py[i]
        oz = pz[i]
        sx = tx + (((m0 * ox) + (m1 * oy) + (m2 * oz)) * scale)
        sy = ty + (((m3 * ox) + (m4 * oy) + (m5 * oz)) * scale)

        diffuse = (wx * lx) + (wy * ly) + (wz * lz)
        diffuse = 0.0 if diffuse < 0.0
        rim = 1.0 - (wz < 0.0 ? 0.0 : wz)
        rim *= rim * rim
        hemi = 0.5 + (0.5 * ((wx * ux) + (wy * uy) + (wz * uz)))
        lr = gnd_r + (hemi * amb_r) + (diffuse * sun_r) + (rim * rim_r)
        lg = gnd_g + (hemi * amb_g) + (diffuse * sun_g) + (rim * rim_g)
        lb = gnd_b + (hemi * amb_b) + (diffuse * sun_b) + (rim * rim_b)

        shine = gloss[i]
        if shine > 0.0
          # The view direction (0, 0, 1) reflected around the normal
          twice = wz + wz
          rx = twice * wx
          ry = twice * wy
          rz = (twice * wz) - 1.0
          horizon = 0.5 + (1.1 * ((rx * ux) + (ry * uy) + (rz * uz)))
          horizon = 0.0 if horizon < 0.0
          horizon = 1.0 if horizon > 1.0
          ahead = 0.45 - (0.9 * rz)
          ahead = 0.0 if ahead < 0.0
          ahead = 1.0 if ahead > 1.0
          er = flr_r + (horizon * sky_r)
          eg = flr_g + (horizon * sky_g)
          eb = flr_b + (horizon * sky_b)
          er = bhd_r + ((er - bhd_r) * ahead)
          eg = bhd_g + ((eg - bhd_g) * ahead)
          eb = bhd_b + ((eb - bhd_b) * ahead)
          glare = ((rx * lx) + (ry * ly) + (rz * lz) - GLARE_START) * glare_scale
          if glare > 0.0
            glare = glare * glare * 2.5
            er += glare * sun_r
            eg += glare * sun_g
            eb += glare * sun_b
          end
          matte = 1.0 - shine
          lr = (lr * matte) + (er * shine)
          lg = (lg * matte) + (eg * shine)
          lb = (lb * matte) + (eb * shine)
        end

        if light_count > 0
          sz = tz + (((m6 * ox) + (m7 * oy) + (m8 * oz)) * scale)
          k = 0
          while k < light_count
            light = lights[k]
            dx = light[0] - sx
            dy = light[1] - sy
            dz = light[2] - sz
            reach = light[6]
            d2 = (dx * dx) + (dy * dy) + (dz * dz)
            if d2 < reach * reach
              d = Math.sqrt(d2) + 0.001
              facing = ((wx * dx) + (wy * dy) + (wz * dz)) / d
              if facing > -0.2
                falloff = 1.0 - (d / reach)
                falloff *= falloff * (facing + 0.2)
                lr += light[3] * falloff
                lg += light[4] * falloff
                lb += light[5] * falloff
              end
            end
            k += 1
          end
        end

        e = em[i] * glow
        r = (cr[i] * (lr + e) * keep) + flash_add
        g = (cg[i] * (lg + e) * keep) + flash_add
        b = (cb[i] * (lb + e) * keep) + flash_add
        r = 255.0 if r > 255.0
        g = 255.0 if g > 255.0
        b = 255.0 if b > 255.0

        w = sizes[i] * scale
        aspect = wz < 0.0 ? -wz : wz
        aspect = MIN_ASPECT if aspect < MIN_ASPECT
        out[j] = sx
        out[j + 1] = sy
        out[j + 2] = w
        out[j + 3] = w * aspect
        out[j + 4] = (Math.atan2(wy, wx) * RAD_TO_DEG) - 90.0
        out[j + 5] = r
        out[j + 6] = g
        out[j + 7] = b
        out[j + 8] = 255
        j += stride
      end
      i += 1
    end
    batch.count = j.idiv(stride)
  end
end
