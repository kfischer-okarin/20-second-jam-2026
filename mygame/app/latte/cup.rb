# The shape of the latte cup, shared by its model, the coffee in it and the milk spilled over it. The bowl is
# the lower half of an ellipsoid shell cut at the rim; heights are from the bottom of its foot, which stands in
# the saucer's well at BASE_Y.
module Cup
  RIM_Y = 5.8
  # Radius of the middle of the wall at the rim, and how far below the rim the ellipsoid reaches
  RADIUS = 5.0
  DEPTH = 4.6
  WALL = 0.22
  BASE_Y = 0.56
  # The coffee before any milk, and the highest it can rise before it runs over
  START_LEVEL = 3.9
  FULL_LEVEL = 5.55
  SAUCER_RADIUS = 7.3
  SAUCER_Y = 0.66

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
