# Places splats on the zero level set of an SDF that is combined from parts:
#   { sdf: ->(x, y, z) { distance }, color: [r, g, b], emission: 0.0..1.0, blend: smoothing, subtract: false,
#     group: 0 }
# Parts are combined in order: a union with the parts before, or with subtract: true cut out of them; blend is
# the distance over which they melt together. Every splat takes the color and emission of the nearest part that
# has a color, so a subtracting part with a color paints the cut surface and one without takes the color of the
# nearest other part. group ends up in SplatModel#group for code that wants to tell parts apart.
# Splats keep the order of the parts they belong to, so later parts draw on top of earlier ones.
# keep: ->(x, y, z) { true/false } drops splats, e.g. ones that would be hidden inside something else.
class SdfBaker
  def self.bake(parts, bounds:, spacing:, size:, seed:, keep: nil)
    new(parts, Rng.new(seed)).bake(bounds, spacing, size, keep)
  end

  def initialize(parts, rng)
    @parts = parts
    @rng = rng
  end

  def bake(bounds, spacing, size, keep)
    candidates = shuffle(surface_candidates(bounds, spacing))
    taken = {}
    splats = []
    candidates.each do |x, y, z|
      next if keep && !keep.call(x, y, z)
      next if too_close?(taken, x, y, z, spacing)

      remember(taken, x, y, z, spacing)
      splats << splat_at(x, y, z, size)
    end
    build_model(splats)
  end

  def distance(x, y, z)
    result = nil
    @parts.each do |part|
      d = part[:sdf].call(x, y, z)
      result = if result.nil?
                 d
               elsif part[:subtract]
                 Sdf.smooth_subtract(result, d, part[:blend] || 0.0)
               else
                 Sdf.smooth_union(result, d, part[:blend] || 0.0)
               end
    end
    result
  end

  private

  # Grid points close to the surface, pulled onto it. Baking time is dominated by the projection, so the grid is
  # only a little finer than the final splat spacing.
  def surface_candidates(bounds, spacing)
    min_x, min_y, min_z, max_x, max_y, max_z = bounds
    step = spacing * 0.7
    jitter = step * 0.35
    result = []
    x = min_x
    while x <= max_x
      y = min_y
      while y <= max_y
        z = min_z
        while z <= max_z
          point = project_to_surface(x + @rng.range(-jitter, jitter), y + @rng.range(-jitter, jitter),
                                     z + @rng.range(-jitter, jitter), step)
          result << point if point
          z += step
        end
        y += step
      end
      x += step
    end
    result
  end

  def project_to_surface(x, y, z, band)
    d = distance(x, y, z)
    return nil if d.abs > band

    3.times do
      gx, gy, gz = gradient(x, y, z)
      x -= gx * d
      y -= gy * d
      z -= gz * d
      d = distance(x, y, z)
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

  def too_close?(taken, x, y, z, spacing)
    cx = (x / spacing).floor
    cy = (y / spacing).floor
    cz = (z / spacing).floor
    min_distance_squared = spacing * spacing
    ((cx - 1)..(cx + 1)).each do |ix|
      ((cy - 1)..(cy + 1)).each do |iy|
        ((cz - 1)..(cz + 1)).each do |iz|
          bucket = taken[cell_key(ix, iy, iz)]
          next unless bucket

          bucket.each do |ox, oy, oz|
            return true if ((ox - x)**2) + ((oy - y)**2) + ((oz - z)**2) < min_distance_squared
          end
        end
      end
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
    shade = @rng.range(0.86, 1.12)
    color = part[:color]
    {
      part: part_index, x: x, y: y, z: z, nx: nx, ny: ny, nz: nz,
      r: color[0] * shade, g: color[1] * shade, b: color[2] * shade,
      emission: part[:emission] || 0.0,
      size: size * @rng.range(0.85, 1.15),
      group: part[:group] || 0
    }
  end

  def material_part_index(x, y, z)
    best = 0
    best_distance = nil
    @parts.each_with_index do |part, index|
      next unless part[:color]

      d = part[:sdf].call(x, y, z).abs
      if best_distance.nil? || d < best_distance
        best = index
        best_distance = d
      end
    end
    best
  end

  def build_model(splats)
    model = SplatModel.new
    splats.each_with_index.sort_by { |splat, index| [splat[:part], index] }.each do |splat, _index|
      model.add(splat[:x], splat[:y], splat[:z], splat[:nx], splat[:ny], splat[:nz],
                splat[:r], splat[:g], splat[:b], splat[:emission], splat[:size], splat[:group])
    end
    model
  end
end
