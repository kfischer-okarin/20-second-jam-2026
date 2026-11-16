# 3D value noise, only used while baking
class Noise3
  def initialize(seed)
    rng = Rng.new(seed)
    perm = (0..255).to_a
    255.downto(1) do |i|
      j = rng.int(i + 1)
      perm[i], perm[j] = perm[j], perm[i]
    end
    @perm = perm + perm
    @values = Array.new(256) { rng.range(-1.0, 1.0) }
  end

  def fbm(x, y, z, octaves: 4)
    sum = 0.0
    amplitude = 0.5
    frequency = 1.0
    octaves.times do
      sum += amplitude * value(x * frequency, y * frequency, z * frequency)
      amplitude *= 0.5
      frequency *= 2.03
    end
    sum
  end

  def value(x, y, z)
    xi = x.floor
    yi = y.floor
    zi = z.floor
    u = fade(x - xi)
    v = fade(y - yi)
    w = fade(z - zi)
    xi &= 255
    yi &= 255
    zi &= 255
    lerp(lerp(lerp(lattice(xi, yi, zi), lattice(xi + 1, yi, zi), u),
              lerp(lattice(xi, yi + 1, zi), lattice(xi + 1, yi + 1, zi), u), v),
         lerp(lerp(lattice(xi, yi, zi + 1), lattice(xi + 1, yi, zi + 1), u),
              lerp(lattice(xi, yi + 1, zi + 1), lattice(xi + 1, yi + 1, zi + 1), u), v),
         w)
  end

  private

  def lattice(cell_x, cell_y, cell_z)
    @values[@perm[@perm[@perm[cell_x] + cell_y] + cell_z]]
  end

  def fade(t)
    t * t * (3.0 - (2.0 * t))
  end

  def lerp(a, b, t)
    a + ((b - a) * t)
  end
end
