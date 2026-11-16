# Bakes the planet's splats once at startup: a crust that is a heightfield over a sphere, with hills, craters
# and domain-warped Voronoi plates whose borders sink into lava cracks, and a molten core below it.
# Crust splats carry their plate as group and how close they are to a crack (0..1) as aux; core splats carry
# the plate above them as group and the phase of their churning as aux.
# Per-splat randomness comes from #jitter, which depends only on the splat and a named channel, so a new random
# property leaves the rest of the planet as it was.
class PlanetBaker
  CORE_RADIUS = 40.5
  CRUST_SPLATS = 2500
  CORE_SPLATS = 1700
  CRUST_SPLAT_SIZE = 9.6
  CORE_SPLAT_SIZE = 9.8

  attr_reader :plate_centers

  def initialize(seed)
    @seed = seed
    rng = Rng.new(seed)
    @noise = Noise3.new(seed)
    @plate_centers = Array.new(Planet::PLATE_COUNT) { rng.unit_vector }
    @craters = Array.new(7) { [rng.unit_vector, rng.range(0.12, 0.28)] }
  end

  # Glowing crack splats come last so the rock next to them never paints over the lava
  def crust
    splats = fibonacci_directions(CRUST_SPLATS, :crust).each_with_index.map { |(dx, dy, dz), i|
      height, plate, crack, hills = surface(dx, dy, dz)
      r = Planet::RADIUS + height
      group = crack > 0.62 ? Planet::CRACK_GROUP : plate
      size = CRUST_SPLAT_SIZE * jitter(i, :crust_size, 0.8, 1.2) * (group == Planet::CRACK_GROUP ? 0.8 : 1.0)
      tint = jitter(i, :crust_tint, 0.9, 1.1)
      [dx * r, dy * r, dz * r, *surface_normal(dx, dy, dz, height), *crust_color(hills, crack, tint), 0.0, size,
       group, group == Planet::CRACK_GROUP ? 1.0 : crack]
    }
    model = SplatModel.new
    splats.partition { |splat| splat[11] != Planet::CRACK_GROUP }.flatten(1).each do |splat|
      model.add(*splat)
    end
    model
  end

  def core
    model = SplatModel.new
    fibonacci_directions(CORE_SPLATS, :core).each_with_index do |(dx, dy, dz), i|
      _height, plate, = surface(dx, dy, dz)
      r = CORE_RADIUS + (1.2 * @noise.fbm(dx * 4.0, dy * 4.0, dz * 4.0, octaves: 2))
      churn_phase = (@noise.fbm(dx * 2.2, dy * 2.2, dz * 2.2, octaves: 3) * 9.0) + jitter(i, :core_churn, 0.0, 0.8)
      model.add(dx * r, dy * r, dz * r, dx, dy, dz, 255.0, 110.0, 30.0, 1.0,
                CORE_SPLAT_SIZE * jitter(i, :core_size, 0.8, 1.2), plate, churn_phase)
    end
    model
  end

  private

  def jitter(index, channel, min, max)
    min + ((max - min) * Rng.at(@seed, index, channel))
  end

  # Evenly spread directions with some jitter, so splats do not line up in visible spirals
  def fibonacci_directions(count, layer)
    golden_angle = Math::PI * (3.0 - Math.sqrt(5.0))
    Array.new(count) do |i|
      y = 1.0 - (((i + 0.5) / count) * 2.0)
      ring = Math.sqrt(1.0 - (y * y))
      angle = (golden_angle * i) + (jitter(i, "#{layer}_angle", -0.35, 0.35) / (ring + 0.3))
      dx = (Math.cos(angle) * ring) + jitter(i, "#{layer}_x", -0.012, 0.012)
      dy = y + jitter(i, "#{layer}_y", -0.012, 0.012)
      dz = (Math.sin(angle) * ring) + jitter(i, "#{layer}_z", -0.012, 0.012)
      length = Math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
      [dx / length, dy / length, dz / length]
    end
  end

  # Height above the base radius, the plate a direction belongs to, how close it is to a crack (0..1) and the
  # raw hill noise
  def surface(dx, dy, dz)
    plate, edge = voronoi(dx, dy, dz)
    crack = 1.0 - smoothstep(0.0, 0.085, edge)
    hills = @noise.fbm(dx * 2.4, dy * 2.4, dz * 2.4)
    height = (hills * 5.0) - (crack * crack * 3.2) + crater_height(dx, dy, dz)
    [height, plate, crack, hills]
  end

  def voronoi(dx, dy, dz)
    warp = 0.28
    wx = dx + (warp * @noise.value((dx * 3.1) + 17.0, dy * 3.1, dz * 3.1))
    wy = dy + (warp * @noise.value(dx * 3.1, (dy * 3.1) + 31.0, dz * 3.1))
    wz = dz + (warp * @noise.value(dx * 3.1, dy * 3.1, (dz * 3.1) + 47.0))
    best = -2.0
    second = -2.0
    plate = 0
    @plate_centers.each_with_index do |(cx, cy, cz), index|
      dot = (wx * cx) + (wy * cy) + (wz * cz)
      if dot > best
        second = best
        best = dot
        plate = index
      elsif dot > second
        second = dot
      end
    end
    [plate, best - second]
  end

  def crater_height(dx, dy, dz)
    @craters.sum do |(cx, cy, cz), size|
      distance = Math.acos(((dx * cx) + (dy * cy) + (dz * cz)).clamp(-1.0, 1.0)) / size
      next 0.0 if distance > 1.4

      bowl = distance < 1.0 ? -2.2 * (1.0 - (distance * distance)) : 0.0
      rim = 1.3 * Math.exp(-(((distance - 1.0) / 0.22)**2))
      bowl + rim
    end
  end

  def surface_normal(dx, dy, dz, height)
    # Tangent basis around the direction
    ax, ay, az = dy.abs < 0.9 ? [0.0, 1.0, 0.0] : [1.0, 0.0, 0.0]
    t1x, t1y, t1z = normalize((ay * dz) - (az * dy), (az * dx) - (ax * dz), (ax * dy) - (ay * dx))
    t2x = (dy * t1z) - (dz * t1y)
    t2y = (dz * t1x) - (dx * t1z)
    t2z = (dx * t1y) - (dy * t1x)
    e = 0.012
    h1 = surface(*normalize(dx + (t1x * e), dy + (t1y * e), dz + (t1z * e)))[0]
    h2 = surface(*normalize(dx + (t2x * e), dy + (t2y * e), dz + (t2z * e)))[0]
    slope1 = (h1 - height) / e
    slope2 = (h2 - height) / e
    r = Planet::RADIUS + height
    normalize((r * dx) - (slope1 * t1x) - (slope2 * t2x),
              (r * dy) - (slope1 * t1y) - (slope2 * t2y),
              (r * dz) - (slope1 * t1z) - (slope2 * t2z))
  end

  def crust_color(hills, crack, tint)
    t = ((hills + 0.45) / 0.9).clamp(0.0, 1.0)
    low = [48.0, 44.0, 70.0]
    mid = [84.0, 84.0, 112.0]
    high = [128.0, 132.0, 156.0]
    color = t < 0.5 ? mix(low, mid, t * 2.0) : mix(mid, high, (t - 0.5) * 2.0)
    color = mix(color, [78.0, 34.0, 46.0], crack * 0.9)
    color.map { |channel| channel * tint }
  end

  def mix(a, b, t)
    [a[0] + ((b[0] - a[0]) * t), a[1] + ((b[1] - a[1]) * t), a[2] + ((b[2] - a[2]) * t)]
  end

  def smoothstep(edge0, edge1, x)
    t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0)
    t * t * (3.0 - (2.0 * t))
  end

  def normalize(x, y, z)
    length = Math.sqrt((x * x) + (y * y) + (z * z))
    [x / length, y / length, z / length]
  end
end
