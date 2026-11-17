# Places splats on the zero level set of an SDF that is combined from parts:
#   { sdf: ->(x, y, z) { distance }, color: [r, g, b], emission: 0.0..1.0, gloss: 0.0..1.0, blend: smoothing,
#     subtract: false, intersect: false, group: 0, shade: 0.13 }
# shade is how much the brightness of its splats varies at random, which gives matte surfaces some texture and
# makes smooth glossy ones look grainy.
# Parts are combined in order: a union with the parts before, with subtract: true cut out of them, or with
# intersect: true cutting away everything outside them; blend is the distance over which they melt together.
# Every splat takes the color, emission and gloss (see SplatRenderer) of the nearest part that has a color, so a
# subtracting part with a color paints the cut surface and one without takes the color of the nearest other part.
# A part with paint: true does not change the shape: splats inside it (where its sdf is negative) take its
# color, such as a glaze on the inside of a cup only. The first paint part that contains a splat wins.
# group ends up in SplatModel#group for code that wants to tell parts apart.
# Splats keep the order of the parts they belong to, so later parts draw on top of earlier ones.
# keep: ->(x, y, z) { true/false } drops splats, e.g. ones that would be hidden inside something else.
class SdfBaker
  # How much farther than exact distances SDFs may lie when skipping empty blocks (see surface_candidates)
  ROOM = 1.25

  def self.bake(parts, bounds:, spacing:, size:, seed:, keep: nil)
    new(parts, Rng.new(seed)).bake(bounds, spacing, size, keep)
  end

  def initialize(parts, rng)
    @parts = parts
    @paint_parts, @shape_parts = parts.partition { |part| part[:paint] }
    @colored = (0...parts.length).select { |index| parts[index][:color] }.reject { |index| parts[index][:paint] }
    @sdfs = @shape_parts.map { |part| part[:sdf] }
    @blends = @shape_parts.map { |part| part.fetch(:blend, 0.0) }
    @modes = @shape_parts.map { |part| combination(part) }
    @rng = rng
  end

  # Candidates near the surface are visited in random order. Most of them would end up too close to a splat
  # taken before, so that is checked before pulling them onto the surface, which is what costs.
  # Baking in the background pauses at ModelCache.checkpoint now and then.
  # Hot loop over every candidate.
  # rubocop:disable-next Metrics/CyclomaticComplexity
  def bake(bounds, spacing, size, keep)
    band = spacing * 0.7
    candidates = shuffle(surface_candidates(bounds, spacing))
    taken = {}
    splats = []
    i = 0
    while i < candidates.length
      ModelCache.checkpoint if (i % 32).zero?
      cx, cy, cz = candidates[i]
      i += 1
      next if too_close?(taken, cx, cy, cz, spacing, spacing * 0.7)

      point = project_to_surface(cx, cy, cz, band)
      next unless point

      x, y, z = point
      next if keep && !keep.call(x, y, z)
      next if too_close?(taken, x, y, z, spacing)

      remember(taken, x, y, z, spacing)
      splats << splat_at(x, y, z, size)
    end
    build_model(splats)
  end

  def distance(x, y, z)
    sdfs = @sdfs
    result = sdfs[0].call(x, y, z)
    i = 1
    n = sdfs.length
    while i < n
      d = sdfs[i].call(x, y, z)
      result = case @modes[i]
               when :union then Sdf.smooth_union(result, d, @blends[i])
               when :subtract then Sdf.smooth_subtract(result, d, @blends[i])
               else Sdf.smooth_intersect(result, d, @blends[i])
               end
      i += 1
    end
    result
  end

  private

  # How a part combines with the parts before it
  def combination(part)
    return :subtract if part[:subtract]
    return :intersect if part[:intersect]

    :union
  end

  # Jittered grid points within a band around the surface, not yet pulled onto it. The grid is only a little
  # finer than the final splat spacing. It is visited in blocks of 4³ points, each made of 2³ cubes of 2³ points;
  # a block or cube whose center lies farther from the surface than its corners reach (with some ROOM for SDFs
  # that are only bounds, like ellipsoids and smooth blends) is skipped whole.
  def surface_candidates(bounds, spacing)
    step = spacing * 0.7
    size = step * 4.0
    middle = step * 1.5
    # From a block's center to its farthest point (1.5 steps along each axis), plus the band
    reach = ((1.5 * 1.732) + 1.0) * step * ROOM
    result = []
    min_x, min_y, min_z, max_x, max_y, max_z = bounds
    x = min_x
    while x <= max_x
      y = min_y
      while y <= max_y
        ModelCache.checkpoint
        z = min_z
        while z <= max_z
          block_candidates(result, x, y, z, step, bounds) if distance(x + middle, y + middle, z + middle).abs <= reach
          z += size
        end
        y += size
      end
      x += size
    end
    result
  end

  def block_candidates(result, start_x, start_y, start_z, step, bounds)
    reach = ((0.5 * 1.732) + 1.0) * step * ROOM
    [0, 2].each do |i|
      [0, 2].each do |j|
        [0, 2].each do |k|
          x = start_x + (i * step)
          y = start_y + (j * step)
          z = start_z + (k * step)
          next if distance(x + (step * 0.5), y + (step * 0.5), z + (step * 0.5)).abs > reach

          cube_candidates(result, x, y, z, step, bounds)
        end
      end
    end
  end

  def cube_candidates(result, start_x, start_y, start_z, step, bounds)
    jitter = step * 0.35
    _min_x, _min_y, _min_z, max_x, max_y, max_z = bounds
    2.times do |i|
      x = start_x + (i * step)
      next if x > max_x

      2.times do |j|
        y = start_y + (j * step)
        next if y > max_y

        2.times do |k|
          z = start_z + (k * step)
          next if z > max_z

          px = x + @rng.range(-jitter, jitter)
          py = y + @rng.range(-jitter, jitter)
          pz = z + @rng.range(-jitter, jitter)
          result << [px, py, pz] if distance(px, py, pz).abs <= step
        end
      end
    end
  end

  def project_to_surface(x, y, z, band)
    d = distance(x, y, z)
    close = band * 0.015
    3.times do
      gx, gy, gz = gradient(x, y, z)
      x -= gx * d
      y -= gy * d
      z -= gz * d
      d = distance(x, y, z)
      break if d.abs < close
    end
    d.abs < band * 0.06 ? [x, y, z] : nil
  end

  # Tetrahedral differences need four distance evaluations instead of six
  def gradient(x, y, z)
    e = 0.02
    a = distance(x + e, y - e, z - e)
    b = distance(x - e, y - e, z + e)
    c = distance(x - e, y + e, z - e)
    d = distance(x + e, y + e, z + e)
    gx = a - b - c + d
    gy = -a - b + c + d
    gz = -a + b - c + d
    length = Math.sqrt((gx * gx) + (gy * gy) + (gz * gz))
    return [0.0, 1.0, 0.0] if length < 1e-9

    [gx / length, gy / length, gz / length]
  end

  def shuffle(points)
    (points.length - 1).downto(1) do |i|
      j = @rng.int(i + 1)
      points[i], points[j] = points[j], points[i]
    end
    points
  end

  # Whether a splat was taken within radius (at most spacing, the size of the cells remember sorts them into)
  # Runs for every candidate, so it loops with while and builds keys without a method call
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/BlockNesting
  def too_close?(taken, x, y, z, spacing, radius = spacing)
    cx = (x / spacing).floor + 512
    cy = (y / spacing).floor + 512
    cz = (z / spacing).floor + 512
    min_distance_squared = radius * radius
    ix = cx - 1
    while ix <= cx + 1
      iy = cy - 1
      while iy <= cy + 1
        iz = cz - 1
        while iz <= cz + 1
          bucket = taken[(ix << 20) | (iy << 10) | iz]
          if bucket
            b = 0
            while b < bucket.length
              other = bucket[b]
              dx = other[0] - x
              dy = other[1] - y
              dz = other[2] - z
              return true if (dx * dx) + (dy * dy) + (dz * dz) < min_distance_squared

              b += 1
            end
          end
          iz += 1
        end
        iy += 1
      end
      ix += 1
    end
    false
  end

  def remember(taken, x, y, z, spacing)
    key = cell_key((x / spacing).floor, (y / spacing).floor, (z / spacing).floor)
    (taken[key] ||= []) << [x, y, z]
  end

  def cell_key(cell_x, cell_y, cell_z)
    ((cell_x + 512) << 20) | ((cell_y + 512) << 10) | (cell_z + 512)
  end

  def splat_at(x, y, z, size)
    nx, ny, nz = gradient(x, y, z)
    part_index = material_part_index(x, y, z)
    part = @parts[part_index]
    variation = part[:shade] || 0.13
    shade = @rng.range(1.0 - variation, 1.0 + (variation * 0.9))
    color = part[:color]
    {
      part: part_index, x: x, y: y, z: z, nx: nx, ny: ny, nz: nz,
      r: color[0] * shade, g: color[1] * shade, b: color[2] * shade,
      emission: part[:emission] || 0.0,
      size: size * @rng.range(0.85, 1.15),
      group: part[:group] || 0,
      gloss: part[:gloss] || 0.0
    }
  end

  def material_part_index(x, y, z)
    painted = @paint_parts.find { |part| part[:sdf].call(x, y, z).negative? }
    return @parts.index(painted) if painted

    @colored.min_by { |index| @parts[index][:sdf].call(x, y, z).abs } || 0
  end

  def build_model(splats)
    model = SplatModel.new
    splats.each_with_index.sort_by { |splat, index| [splat[:part], index] }.each do |splat, _index|
      model.add(splat[:x], splat[:y], splat[:z], splat[:nx], splat[:ny], splat[:nz],
                splat[:r], splat[:g], splat[:b], splat[:emission], splat[:size], splat[:group], splat[:gloss])
    end
    model
  end
end
