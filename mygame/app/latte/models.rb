# The objects on the terrace as SDF parts, baked into splat models once (see ModelCache). Model space is world
# space in centimetres (x right, y up, z towards the viewer), each model around its own origin.
module Models
  GLAZE = [78, 96, 132].freeze
  PORCELAIN = [246, 240, 228].freeze
  STEEL = [178, 188, 206].freeze
  ALUMINIUM = [168, 176, 192].freeze
  BAKELITE = [40, 34, 42].freeze
  MILK = [250, 246, 236].freeze

  # How each model is baked: the method with its parts, its bounds, splat spacing, seed, and which splats it keeps
  BAKES = {
    cup: [:cup_parts, [-8.0, -0.2, -5.8, 5.8, 6.5, 5.8], 0.3, 11, ->(x, y, z) { Cup.visible_surface?(x, y, z) }],
    saucer: [:saucer_parts, [-8.0, -0.2, -8.0, 8.0, 1.4, 8.0], 0.38, 12,
             ->(x, y, z) { y > 0.2 && (x * x) + (z * z) > 4.0 }],
    pitcher: [:pitcher_parts, [-1.0, -6.6, -3.1, 9.0, 0.8, 3.1], 0.28, 13,
              ->(x, y, z) { Pitcher.visible_surface?(x, y, z) }],
    moka_pot: [:moka_pot_parts, [-4.4, -0.2, -3.2, 5.4, 9.8, 3.2], 0.3, 14, nil]
  }.freeze

  extend self

  def cup = model(:cup)
  def saucer = model(:saucer)
  def pitcher = model(:pitcher)
  def moka_pot = model(:moka_pot)

  def model(name)
    ModelCache.fetch(name) { bake(name) }
  end

  # The same model with splats closer together by detail (0.5: twice as close, four times as many)
  def fine(name, detail)
    ModelCache.fetch(:"#{name}_#{detail}") { bake(name, detail) }
  end

  def bake(name, detail = 1.0)
    parts, bounds, spacing, seed, keep = BAKES.fetch(name)
    spacing *= detail
    SdfBaker.bake(send(parts), bounds: bounds, spacing: spacing, size: spacing * 3.0, seed: seed, keep: keep)
  end

  # The models are simple blobs: round chunky forms with thick walls, every part one plain color without the
  # baker's random shading (shade) or gloss, which would make them grainy.

  # A deep round latte bowl with a rolled rim on a short foot, and a fat ring for a handle on the left; glazed
  # outside, white inside and on top of the rim. Its foot stands on y = 0.
  def cup_parts
    [
      { sdf: ->(x, y, z) { Cup.wall(x, y, z) }, color: GLAZE, shade: 0.0 },
      { sdf: ->(x, y, z) { Sdf.torus(x, y - Cup::RIM_Y, z, Cup::RADIUS, Cup::WALL) }, color: GLAZE, shade: 0.0,
        blend: 0.2 },
      { sdf: ->(x, y, z) { Sdf.cylinder(x, y - 0.6, z, 2.4, 0.6, 0.45) }, color: GLAZE, shade: 0.0, blend: 1.0 },
      { sdf: ->(x, y, z) { [Sdf.torus_xy(x + 5.7, y - 3.6, z, 1.35, 0.6), x + 4.6].max }, color: GLAZE, shade: 0.0,
        blend: 0.7 },
      { sdf: ->(x, y, z) { Cup.middle(x, y, z) }, color: PORCELAIN, shade: 0.0, paint: true },
      { sdf: ->(x, y, z) { Cup.rim_top(x, y, z) }, color: PORCELAIN, shade: 0.0, paint: true }
    ]
  end

  # A thick rounded plate with a shallow well for the cup, white on top and glazed around its edge
  def saucer_parts
    [
      { sdf: ->(x, y, z) { Sdf.cylinder(x, y - 0.45, z, 7.4, 0.45, 0.45) }, color: GLAZE, shade: 0.0 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y - 1.6, z, 5.2, 0.9, 5.2) }, subtract: true, blend: 1.2 },
      { sdf: ->(x, y, z) { Sdf.cylinder(x, y - 1.0, z, 6.6, 0.42) }, color: PORCELAIN, shade: 0.0, paint: true }
    ]
  end

  # A steel milk pitcher with its origin at the tip of its spout, which points left, so that tilting it around
  # the origin pours where it is held. Its bottom is Pitcher::BOTTOM below and right of the spout.
  def pitcher_parts
    bx, by, = Pitcher::BOTTOM
    [
      { sdf: ->(x, y, z) { Pitcher.wall(x, y, z) }, color: STEEL, shade: 0.0 },
      { sdf: ->(x, y, z) { Sdf.torus(x - bx, y - by - Pitcher::RIM, z, Pitcher::RIM_RADIUS, Pitcher::WALL) },
        color: STEEL, shade: 0.0, blend: 0.15 },
      { sdf: ->(x, y, z) { Pitcher.spout(x, y, z) }, color: STEEL, shade: 0.0, blend: 0.6 },
      { sdf: ->(x, y, z) { [Sdf.torus_xy(x - bx - 3.2, y - by - 3.4, z, 1.5, 0.5), bx + 2.2 - x].max },
        color: STEEL, shade: 0.0, blend: 0.6 },
      { sdf: ->(x, y, z) { Sdf.cylinder(x - bx, y - by - Pitcher::MILK_Y, z, 2.1, 0.08) }, color: MILK, shade: 0.0 }
    ]
  end

  # A stovetop pot: two round frustums, rounded off and pinched at the waist, a domed lid, a stubby spout on the
  # left, and a black knob and chunky handle on the right (towards the cup)
  def moka_pot_parts
    round = 0.45
    [
      { sdf: ->(x, y, z) { Sdf.capped_cone(x, y - 2.1, z, 2.1 - round, 2.55 - round, 2.0 - round) - round },
        color: ALUMINIUM, shade: 0.0 },
      { sdf: ->(x, y, z) { Sdf.capped_cone(x, y - 6.4, z, 2.0 - round, 2.0 - round, 2.45 - round) - round },
        color: ALUMINIUM, shade: 0.0, blend: 0.5 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y - 8.4, z, 2.3, 0.6, 2.3) }, color: ALUMINIUM, shade: 0.0, blend: 0.4 },
      { sdf: ->(x, y, z) { Sdf.cone_between(x, y, z, [-1.6, 7.4, 0.0], [-3.3, 8.5, 0.0], 0.8, 0.35) },
        color: ALUMINIUM, shade: 0.0, blend: 0.5 },
      { sdf: ->(x, y, z) { Sdf.ellipsoid(x, y - 9.1, z, 0.6, 0.45, 0.6) }, color: BAKELITE, shade: 0.0 },
      { sdf: ->(x, y, z) { Sdf.capsule(x, y, z, [2.4, 7.9, 0.0], [4.3, 7.5, 0.0], 0.5) }, color: BAKELITE,
        shade: 0.0 },
      { sdf: ->(x, y, z) { Sdf.capsule(x, y, z, [4.3, 7.5, 0.0], [3.9, 5.0, 0.0], 0.55) }, color: BAKELITE,
        shade: 0.0, blend: 0.4 }
    ]
  end
end
