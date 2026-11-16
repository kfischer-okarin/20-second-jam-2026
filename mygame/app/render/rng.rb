# Deterministic random numbers, so baked models look the same on every run
class Rng
  # A number in 0..1 that depends only on the seed, an index and a channel name. Unlike drawing from a stream,
  # adding a channel or a call never changes the numbers anything else gets.
  def self.at(seed, index, channel)
    hash = (seed * 73_856_093) ^ (index * 19_349_663) ^ name_hash(channel)
    hash &= 0xffffffff
    hash = ((hash ^ (hash >> 16)) * 0x45d9f3b) & 0xffffffff
    hash = ((hash ^ (hash >> 16)) * 0x45d9f3b) & 0xffffffff
    (hash ^ (hash >> 16)) / 4_294_967_295.0
  end

  def self.name_hash(name)
    name.to_s.bytes.reduce(7) { |hash, byte| ((hash * 31) + byte) & 0xffffffff }
  end

  def initialize(seed)
    @state = seed % 2_147_483_647
    @state = 1 if @state <= 0
  end

  def float
    @state = (@state * 16_807) % 2_147_483_647
    (@state - 1) / 2_147_483_646.0
  end

  def range(min, max)
    min + ((max - min) * float)
  end

  def int(count)
    (float * count).floor.clamp(0, count - 1)
  end

  # Uniformly distributed unit vector
  def unit_vector
    z = range(-1.0, 1.0)
    angle = range(0.0, Math::PI * 2)
    r = Math.sqrt(1.0 - (z * z))
    [r * Math.cos(angle), r * Math.sin(angle), z]
  end
end
