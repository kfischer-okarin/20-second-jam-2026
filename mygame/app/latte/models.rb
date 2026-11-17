# The objects on the terrace as SDF parts, baked into splat models once (see ModelCache). Model space is world
# space in centimetres (x right, y up, z towards the viewer), each model around its own origin.
module Models
  GLAZE = [78, 96, 132].freeze
  PORCELAIN = [246, 240, 228].freeze
  STEEL = [178, 188, 206].freeze
  ALUMINIUM = [168, 176, 192].freeze
  BAKELITE = [40, 34, 42].freeze
  MILK = [250, 246, 236].freeze

  extend self

  def cup
    ModelCache.fetch(:cup) do
      SdfBaker.bake(cup_parts, bounds: [-7.6, -0.2, -5.6, 5.6, 6.4, 5.6], spacing: 0.3, size: 0.9, seed: 11,
                               keep: ->(x, y, z) { Cup.visible_surface?(x, y, z) })
    end
  end

  def saucer
    ModelCache.fetch(:saucer) do
      SdfBaker.bake(saucer_parts, bounds: [-8.0, -0.2, -8.0, 8.0, 1.4, 8.0], spacing: 0.38, size: 1.15, seed: 12,
                                  keep: ->(x, y, z) { y > 0.2 && (x * x) + (z * z) > 4.0 })
    end
  end

  def pitcher
    ModelCache.fetch(:pitcher) do
      SdfBaker.bake(pitcher_parts, bounds: [-0.6, -6.6, -3.0, 8.4, 0.6, 3.0], spacing: 0.28, size: 0.84, seed: 13,
                                   keep: ->(x, y, z) { Pitcher.visible_surface?(x, y, z) })
    end
  end

  def moka_pot
    ModelCache.fetch(:moka_pot) do
      SdfBaker.bake(moka_pot_parts, bounds: [-4.4, -0.2, -3.2, 5.4, 9.8, 3.2], spacing: 0.3, size: 0.9, seed: 14)
    end
  end

  # A footed latte bowl with its handle on the left, glazed outside and white inside. Its foot stands on y = 0.
  def cup_parts
    [
      { sdf: ->(x, y, z) { Sdf.cylinder(x, y - 0.75, z, 2.35, 0.75, 0.25) }, color: GLAZE, gloss: 0.12, shade: 0.04 },
      { sdf: ->(x, y, z) { Cup.wall(x, y, z) }, color: GLAZE, gloss: 0.12, shade: 0.04, blend: 0.6 },
      { sdf: ->(x, y, z) { Sdf.torus(x, y - Cup::RIM_Y, z, Cup::RADIUS, Cup::WALL) }, color: PORCELAIN, blend: 0.1 },
      { sdf: ->(x, y, z) { [Sdf.torus_xy(x + 5.55, y - 3.7, z, 1.3, 0.36), x + 4.5].max }, color: GLAZE,
        gloss: 0.25, blend: 0.35 },
      { sdf: ->(x, y, z) { Cup.middle(x, y, z) }, color: PORCELAIN, gloss: 0.1, shade: 0.04, paint: true },
      { sdf: ->(x, y, z) { Sdf.torus(x, y - Cup::RIM_Y, z, Cup::RADIUS, Cup::WALL + 0.12) }, color: PORCELAIN,
        gloss: 0.2, paint: true }
    ]
  end

  # A wide plate with a shallow well for the cup and a raised lip, white on top and glazed around its edge
  def saucer_parts
    [
      { sdf: ->(x, y, z) { Sdf.cylinder(x, y - 0.32, z, 7.4, 0.32, 0.28) }, color: GLAZE, gloss: 0.12, shade: 0.04 },
      { sdf: lambda { |x, y, z|
        Sdf.torus(x, y - 0.62, z, 6.95, 0.26)
      }, color: GLAZE, gloss: 0.12, shade: 0.04, blend: 0.5 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y - 1.15, z, 5.6, 0.62, 5.6) }, subtract: true, blend: 0.8 },
      { sdf: ->(x, y, z) { Sdf.cylinder(x, y - 0.9, z, 6.6, 0.7) }, color: PORCELAIN, gloss: 0.1, shade: 0.04,
        paint: true }
    ]
  end

  # A steel milk pitcher with its origin at the tip of its spout, which points left, so that tilting it around
  # the origin pours where it is held. Its bottom is Pitcher::BOTTOM below and right of the spout.
  def pitcher_parts
    bx, by, = Pitcher::BOTTOM
    [
      { sdf: ->(x, y, z) { Pitcher.wall(x, y, z) }, color: STEEL, gloss: 0.8, shade: 0.03 },
      { sdf: ->(x, y, z) { Pitcher.spout(x, y, z) }, color: STEEL, gloss: 0.8, shade: 0.03, blend: 0.35 },
      { sdf: ->(x, y, z) { [Sdf.torus_xy(x - bx - 3.3, y - by - 3.4, z, 1.45, 0.3), bx + 2.3 - x].max },
        color: STEEL, gloss: 0.8, shade: 0.03, blend: 0.3 },
      { sdf: ->(x, y, z) { Sdf.cylinder(x - bx, y - by - Pitcher::MILK_Y, z, 2.2, 0.08) }, color: MILK },
      { sdf: ->(x, y, z) { Sdf.cylinder(x - bx, y - by - Pitcher::MILK_Y - 0.1, z, 2.25, 0.12) }, color: MILK,
        paint: true }
    ]
  end

  # An octagonal stovetop pot: a boiler that narrows to the waist, a collector that widens to the lid, a black
  # knob and handle on the right (towards the cup) and its spout on the left
  def moka_pot_parts
    [
      { sdf: lambda { |x, y, z|
        Sdf.ngon_frustum(x, y - 2.1, z, 8, 2.1, 2.55, 2.0)
      }, color: ALUMINIUM, gloss: 0.72, shade: 0.05 },
      { sdf: ->(x, y, z) { Sdf.cylinder(x, y - 4.3, z, 1.95, 0.25, 0.1) }, color: ALUMINIUM, gloss: 0.72, shade: 0.05,
        blend: 0.15 },
      { sdf: lambda { |x, y, z|
        Sdf.ngon_frustum(x, y - 6.45, z, 8, 2.0, 2.0, 2.45)
      }, color: ALUMINIUM, gloss: 0.72, shade: 0.05,
        blend: 0.15 },
      { sdf: lambda { |x, y, z|
        Sdf.ngon_frustum(x, y - 8.6, z, 8, 0.18, 2.5, 2.2)
      }, color: ALUMINIUM, gloss: 0.72, shade: 0.05,
        blend: 0.1 },
      { sdf: ->(x, y, z) { Sdf.cone_between(x, y, z, [-1.6, 7.6, 0.0], [-3.4, 8.7, 0.0], 0.75, 0.3) },
        color: ALUMINIUM, gloss: 0.72, shade: 0.05, blend: 0.3 },
      { sdf: ->(x, y, z) { Sdf.cylinder(x, y - 9.05, z, 0.45, 0.3, 0.15) }, color: BAKELITE, gloss: 0.3 },
      { sdf: ->(x, y, z) { Sdf.capsule(x, y, z, [2.3, 8.0, 0.0], [4.3, 7.5, 0.0], 0.4) }, color: BAKELITE,
        gloss: 0.3, blend: 0.2 },
      { sdf: ->(x, y, z) { Sdf.capsule(x, y, z, [4.3, 7.5, 0.0], [3.8, 5.0, 0.0], 0.45) }, color: BAKELITE,
        gloss: 0.3, blend: 0.3 }
    ]
  end
end
