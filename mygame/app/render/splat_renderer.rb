# Projects the splats of a model orthographically into a batch. Each splat becomes a gaussian ellipse: a disc
# lying on the surface, squashed along its projected normal, so silhouettes stay crisp and slopes read as strokes.
# tx, ty is the screen position of the model's origin; tz only serves the distance to point lights, there is no
# depth sorting (batches draw in order, and a model's splats in the order of its parts).
module SplatRenderer
  RAD_TO_DEG = 180.0 / Math::PI
  MIN_ASPECT = 0.32

  extend self

  # Hot loop: comparisons stay operators instead of [a, b].max or #positive?, which allocate or send in mruby.
  # rubocop:disable-next Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockNesting, Style/MinMaxComparison, Style/NumericPredicate
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
    lx, ly, lz = lighting.sun
    sun_r, sun_g, sun_b = lighting.sun_color
    amb_r, amb_g, amb_b = lighting.ambient
    rim_r, rim_g, rim_b = lighting.rim
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
        lr = amb_r + (diffuse * sun_r) + (rim * rim_r)
        lg = amb_g + (diffuse * sun_g) + (rim * rim_g)
        lb = amb_b + (diffuse * sun_b) + (rim * rim_b)

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
