# Lights splats once, at bake time, in the colors of their material (the way ink-studio's sculptor does): every
# material is a ramp of palette colors from dark to light, and a splat takes the one its light falls on. The light
# is a sun (half-Lambert, with a soft shadow traced through the scene's distance field), occlusion from the field
# along the normal, and the sky, plus a little random jitter so the steps between colors look drawn by hand.
# A glossy material shows a hard glint, one palette color, where it mirrors the sun to the eye.
#
# field responds to distance(x, y, z) in world space; materials are { ramp: [palette indices], glint: index }.
class RampLighting
  attr_accessor :sun, :view

  def initialize(field, sun:, view:, ambient: 0.14, sky: 0.3, sun_strength: 0.72, occlusion: 1.5, jitter: 0.12,
                 seed: 1)
    @field = field
    @sun = normalize(*sun)
    @view = normalize(*view)
    @ambient = ambient
    @sky = sky
    @sun_strength = sun_strength
    @occlusion = occlusion
    @jitter = jitter
    @rng = Rng.new(seed)
  end

  # The palette index a splat at x, y, z with normal nx, ny, nz takes from material
  def color(material, x, y, z, nx, ny, nz)
    return material[:glint] if material[:glint] && glinting?(nx, ny, nz, material[:glint_at] || 0.96)

    ramp = material[:ramp]
    t = light(x, y, z, nx, ny, nz) + ((@rng.float - 0.5) * @jitter)
    ramp[(t * ramp.length).floor.clamp(0, ramp.length - 1)]
  end

  def light(x, y, z, nx, ny, nz)
    lx, ly, lz = @sun
    sun = (nx * lx) + (ny * ly) + (nz * lz)
    sun = sun.positive? ? sun * shadow(x + (nx * 0.05), y + (ny * 0.05), z + (nz * 0.05)) : 0.0
    (occlusion(x, y, z, nx, ny, nz) * (@ambient + (@sky * (0.5 + (0.5 * ny))))) + (@sun_strength * sun)
  end

  private

  def glinting?(nx, ny, nz, threshold)
    hx = @sun[0] + @view[0]
    hy = @sun[1] + @view[1]
    hz = @sun[2] + @view[2]
    ((nx * hx) + (ny * hy) + (nz * hz)) / Math.sqrt((hx * hx) + (hy * hy) + (hz * hz)) > threshold
  end

  # Soft shadow: how close the ray towards the sun passes to something, relative to how far it went
  def shadow(x, y, z)
    lx, ly, lz = @sun
    t = 0.07
    lit = 1.0
    24.times do
      d = @field.distance(x + (lx * t), y + (ly * t), z + (lz * t))
      return 0.0 if d < 0.004

      ratio = 9.0 * d / t
      lit = ratio if ratio < lit
      t += d.clamp(0.05, 0.9)
      break if t > 30.0
    end
    lit
  end

  def occlusion(x, y, z, nx, ny, nz)
    occluded = 0.0
    weight = 1.0
    [0.18, 0.36, 0.54].each do |h|
      d = @field.distance(x + (nx * h), y + (ny * h), z + (nz * h))
      occluded += (h - d).clamp(0.0, h) * weight / h
      weight *= 0.6
    end
    (1.0 - (@occlusion * occluded / 1.96)).clamp(0.0, 1.0)
  end

  def normalize(x, y, z)
    length = Math.sqrt((x * x) + (y * y) + (z * z))
    [x / length, y / length, z / length]
  end
end
