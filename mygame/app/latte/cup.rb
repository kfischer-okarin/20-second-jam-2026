# The shape of the latte cup, shared by its model, the coffee in it and the milk spilled over it. The bowl is
# the lower half of a thick ellipsoid shell cut at the rim, which a torus rolls round; heights are from the bottom
# of its foot, which stands in the saucer's well at BASE_Y.
module Cup
  RIM_Y = 5.8
  # Radius of the middle of the wall at the rim, and how far below the rim the ellipsoid reaches
  RADIUS = 5.0
  DEPTH = 4.8
  WALL = 0.38
  BASE_Y = 0.72
  # The coffee before any milk, and the highest it can rise before it runs over
  START_LEVEL = 3.9
  FULL_LEVEL = 5.4
  SAUCER_RADIUS = 7.3
  SAUCER_Y = 0.88

  extend self

  # Compares with an operator instead of [a, b].max, which allocates: baking calls it hundreds of thousands of
  # times (see Sdf)
  def wall(x, y, z)
    shell = middle(x, y, z).abs - WALL
    cut = y - RIM_Y
    # rubocop:disable-next Style/MinMaxComparison
    shell > cut ? shell : cut
  end

  # Negative inside the middle of the wall
  def middle(x, y, z)
    Sdf.ellipsoid(x, y - RIM_Y, z, RADIUS, DEPTH, RADIUS)
  end

  # Negative on the top of the rim, which is white like the inside
  def rim_top(x, y, z)
    ring = Sdf.torus(x, y - RIM_Y, z, RADIUS, WALL + 0.1)
    below = RIM_Y - 0.05 - y
    # rubocop:disable-next Style/MinMaxComparison
    ring > below ? ring : below
  end

  def inner_radius(y)
    (RADIUS * Math.sqrt([1.0 - (((y - RIM_Y) / DEPTH)**2), 0.0].max)) - WALL
  end

  def outer_radius(y)
    (RADIUS * Math.sqrt([1.0 - (((y - RIM_Y) / DEPTH)**2), 0.0].max)) + WALL
  end

  # The coffee hides the inside of the bowl below where it starts
  def visible_surface?(x, y, z)
    y > START_LEVEL - 0.5 || middle(x, y, z).positive? || y < 1.2
  end
end
