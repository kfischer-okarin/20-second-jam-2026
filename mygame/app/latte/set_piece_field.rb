# The distance to the nearest surface of the set pieces standing on the table (the table top is y = 0), for light
# traced through the scene while baking (see RampLighting). Each piece is its model's SDF parts, turned and moved
# into place; a piece whose bounding sphere is farther than what is already near is skipped.
class SetPieceField
  # pieces: [parts, rotation (model to world), position, bounding radius]
  def initialize(pieces)
    @pieces = pieces.map { |parts, rotation, position, radius|
      baker = SdfBaker.new(parts, Rng.new(1))
      [baker, transpose(rotation), *position, radius]
    }
  end

  # Traced many times per splat while baking, so it compares without allocating an array for [a, b].min
  def distance(x, y, z)
    pieces = distance_to_pieces(x, y, z, y)
    # rubocop:disable-next Style/MinMaxComparison
    pieces < y ? pieces : y
  end

  # The distance to the nearest piece, not counting the table, if it is nearer than best
  # rubocop:disable-next Metrics/AbcSize
  def distance_to_pieces(x, y, z, best = 1e9)
    @pieces.each do |baker, inverse, px, py, pz, radius|
      dx = x - px
      dy = y - py
      dz = z - pz
      next if Math.sqrt((dx * dx) + (dy * dy) + (dz * dz)) - radius > best

      m0, m1, m2, m3, m4, m5, m6, m7, m8 = inverse
      d = baker.distance((m0 * dx) + (m1 * dy) + (m2 * dz), (m3 * dx) + (m4 * dy) + (m5 * dz),
                         (m6 * dx) + (m7 * dy) + (m8 * dz))
      best = d if d < best
    end
    best
  end

  private

  def transpose(matrix)
    m0, m1, m2, m3, m4, m5, m6, m7, m8 = matrix
    [m0, m3, m6, m1, m4, m7, m2, m5, m8]
  end
end
